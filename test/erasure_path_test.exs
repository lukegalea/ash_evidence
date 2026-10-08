# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.ErasurePathTest do
  @moduledoc """
  The erasure path (§1.2/R3), tested rather than assumed: the assertion
  SURVIVES document erasure; the blob-class records it cites (evaluation,
  packet, candidate set) cascade away; the dangling references read
  sanely afterwards, and the record_hash still verifies — because
  nothing hashed was ever payload-class.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Assertions
  alias AshEvidence.{CandidateSet, EvidenceEvaluation, Packet, Retrieval}
  alias AshEvidence.Test.{Fixtures, HostAssertion}

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  test "assertion survives erasure; packet, evaluation and candidates cascade" do
    # The full loop, as the orchestrator assembles it: retrieval with a
    # persisted search proof, the evaluation run row, the packet, the
    # assertion through the host's fragment.
    version = Fixtures.ingest_document(80)
    run = Fixtures.start_run(version)

    atoms =
      Fixtures.seed_atoms(version, run, [
        "the certificate coverage expires on 2026-05-28",
        "the certificate coverage never expires and is without limit"
      ])

    retrieval =
      Retrieval.retrieve!(version, "the certificate coverage expires",
        persist?: true,
        hypotheses: [:supports, :contradicts]
      )

    evaluation =
      Fixtures.start_evaluation(version, candidate_set_ids: [retrieval.candidate_set_id])

    observation_ids = for _ <- atoms, do: Ash.UUID.generate()

    joins =
      Map.new(Enum.zip(atoms, observation_ids), fn {atom, observation_id} ->
        {atom.id, Fixtures.observation_join(observation_id, Fixtures.hash_of(atom.id))}
      end)

    packet =
      Fixtures.assemble_packet(evaluation, Enum.map(atoms, & &1.id),
        candidate_observations: joins,
        selected_atom_ids: [hd(atoms).id]
      )

    aggregate = %{
      disposition: :contradicts,
      distribution: %{
        "supports" => "0.485",
        "contradicts" => "0.4",
        "insufficient" => "0.115",
        "not_applicable" => "0.0",
        "wrong_scope" => "0.0"
      },
      rule_version: Assertions.aggregation_rule_version()
    }

    assertion =
      Ash.create!(
        HostAssertion,
        %{
          id: Ash.UUID.generate(),
          packet_id: packet.id,
          evaluation_id: evaluation.id,
          disposition: aggregate.disposition,
          distribution: aggregate.distribution,
          aggregation_rule_version: aggregate.rule_version,
          observation_ids: observation_ids,
          subject: Fixtures.subject("erase"),
          predicate: Fixtures.predicate(),
          subject_state_digest: Fixtures.hash_of("state"),
          question_set_hash: Fixtures.hash_of("question-set")
        },
        action: :record,
        authorize?: false
      )

    # Everything resolves before erasure.
    assert {:ok, _} = Ash.get(HostAssertion, assertion.id)
    assert {:ok, _} = Ash.get(Packet, packet.id)
    assert {:ok, _} = Ash.get(EvidenceEvaluation, evaluation.id)
    assert {:ok, _} = Ash.get(CandidateSet, retrieval.candidate_set_id)

    # --- The host's erasure linkage, at the level it lives: the host
    # deletes the content it owns — atoms first (they cite runs), then
    # the runs — then the version row; the version cascade takes
    # evaluations (and their packets) and the candidate sets with it.
    AshEvidence.Repo.query!("DELETE FROM addressed_atoms WHERE document_version_id = $1", [
      Ecto.UUID.dump!(version.id)
    ])

    AshEvidence.Repo.query!("DELETE FROM parse_runs WHERE document_version_id = $1", [
      Ecto.UUID.dump!(version.id)
    ])

    AshEvidence.Repo.query!("DELETE FROM document_versions WHERE id = $1", [
      Ecto.UUID.dump!(version.id)
    ])

    # The envelope-class record survives; the blob-class records died.
    assert {:ok, surviving} = Ash.get(HostAssertion, assertion.id)
    assert {:error, _} = Ash.get(Packet, packet.id)
    assert {:error, _} = Ash.get(EvidenceEvaluation, evaluation.id)
    assert {:error, _} = Ash.get(CandidateSet, retrieval.candidate_set_id)

    # Dangling references degrade honestly: the explanation resolves the
    # assertion's observation sources to NOTHING and says so — a valid
    # reference to something that no longer resolves.
    explanation =
      AshEvidence.explanation([
        %{
          observation_id: hd(observation_ids),
          disposition: surviving.disposition,
          probability: "0.8",
          question_version: 1,
          model_digest: "sha256:" <> String.duplicate("0", 64),
          source_ids: Enum.map(atoms, & &1.id)
        }
      ])
      |> hd()

    assert explanation.sources == []
    assert Enum.sort(explanation.unresolved_source_ids) == Enum.sort(Enum.map(atoms, & &1.id))

    # And the surviving row still verifies: nothing hashed was
    # payload-class, so erasure moved no byte of the hashed inputs.
    recomputed =
      Assertions.record_hash(%{
        id: surviving.id,
        record_version: surviving.record_version,
        packet_id: surviving.packet_id,
        evaluation_id: surviving.evaluation_id,
        disposition: surviving.disposition,
        distribution: surviving.distribution,
        aggregation_rule_version: surviving.aggregation_rule_version,
        observation_ids: surviving.observation_ids,
        subject: surviving.subject,
        predicate: surviving.predicate,
        subject_state_digest: surviving.subject_state_digest,
        question_set_hash: surviving.question_set_hash
      })

    assert recomputed == surviving.record_hash

    # The read the host's banding/admission would do still works against
    # the surviving row alone (the host-composed read).
    assert [%HostAssertion{}] =
             HostAssertion
             |> Ash.Query.for_read(:by_subject, %{
               subject_type: "synthetic_subject",
               subject_id: "subj-erase"
             })
             |> Ash.read!(authorize?: false)
  end
end
