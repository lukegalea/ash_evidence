# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.PacketsTest do
  @moduledoc """
  The evaluation run row and the packet: the ParseRun-pattern lifecycle,
  the packet as an ids-only join to the ledger, and the observation-join
  validation that keeps answers out of the packet.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.{Domain, Packet}
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(60)
    run = Fixtures.start_run(version)
    atoms = Fixtures.seed_atoms(version, run, ["clause one", "clause two", "clause three"])
    {:ok, version: version, run: run, atoms: atoms}
  end

  describe "EvidenceEvaluation — the ParseRun-pattern lifecycle" do
    test "an evaluation starts pending with its loop inputs, closes once" do
      version = Fixtures.ingest_document(61)

      evaluation =
        Fixtures.start_evaluation(version,
          rule_ref: %{bundle_hash: Fixtures.hash_of("b"), rule_id: "r-9", predicate_id: "p-9"}
        )

      assert evaluation.status == :pending
      assert is_nil(evaluation.closed_at)
      assert evaluation.subject == Fixtures.subject()
      assert evaluation.predicate == Fixtures.predicate()
      assert evaluation.rule_ref.rule_id == "r-9"
      assert evaluation.call_shape == :candidate_local

      evaluation = Domain.mark_evaluation_ok!(evaluation)
      assert evaluation.status == :ok
      assert %DateTime{} = evaluation.closed_at

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(evaluation, %{}, action: :mark_ok, authorize?: false)
    end

    test "closing failed is terminal too, and evaluations cascade with their version" do
      version = Fixtures.ingest_document(62)
      evaluation = Fixtures.start_evaluation(version)
      evaluation = Domain.mark_evaluation_failed!(evaluation)
      assert evaluation.status == :failed

      # The version cascade is a DB-level FK (host-driven erasure), so
      # assert where it lives: the declared ON DELETE CASCADE.
      %{rows: rows} =
        AshEvidence.Repo.query!(
          "SELECT confdeltype FROM pg_constraint WHERE conname = 'evidence_evaluations_document_version_id_fkey'"
        )

      assert [["c"]] = rows
    end

    test "expansion steps record candidate set and observation ids" do
      version = Fixtures.ingest_document(63)

      steps = [
        %{step: 1, candidate_set_id: Ash.UUID.generate(), observation_ids: [Ash.UUID.generate()]}
      ]

      evaluation =
        Fixtures.start_evaluation(version,
          candidate_set_ids: [Ash.UUID.generate(), hd(steps).candidate_set_id],
          expansion_steps: steps
        )

      assert length(evaluation.candidate_set_ids) == 2
      assert [%{step: 1}] = evaluation.expansion_steps
    end
  end

  describe "Packet — ids only, joins not copies" do
    test "a packet carries atom ids and the observation join", %{atoms: atoms} do
      evaluation = Fixtures.start_evaluation(Fixtures.ingest_document(64))

      joins =
        Map.new(atoms, fn atom ->
          {atom.id, Fixtures.observation_join(Ash.UUID.generate(), Fixtures.hash_of(atom.id))}
        end)

      packet =
        Fixtures.assemble_packet(evaluation, Enum.map(atoms, & &1.id),
          candidate_observations: joins,
          selected_atom_ids: [hd(atoms).id],
          limiting_atom_ids: [Enum.at(atoms, 1).id],
          missing_dimensions: ["effective_date"],
          requires_expansion: true
        )

      assert packet.candidate_atom_ids == Enum.map(atoms, & &1.id)
      # The stored shape is string-keyed (jsonb round-trip).
      assert packet.candidate_observations[hd(atoms).id]["observation_id"]
      assert packet.selected_atom_ids == [hd(atoms).id]
      assert packet.missing_dimensions == ["effective_date"]
      assert packet.requires_expansion == true
    end

    test "the observation join REJECTS a copied answer", %{atoms: [atom | _]} do
      evaluation = Fixtures.start_evaluation(Fixtures.ingest_document(65))

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Packet,
                 %{
                   evaluation_id: evaluation.id,
                   candidate_atom_ids: [atom.id],
                   candidate_observations: %{
                     atom.id => %{
                       observation_id: Ash.UUID.generate(),
                       question_hash: Fixtures.hash_of(atom.id),
                       answer: "supports"
                     }
                   }
                 },
                 action: :assemble,
                 authorize?: false
               )
    end

    test "the observation join REJECTS an extra key of any name", %{atoms: [atom | _]} do
      evaluation = Fixtures.start_evaluation(Fixtures.ingest_document(66))

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Packet,
                 %{
                   evaluation_id: evaluation.id,
                   candidate_atom_ids: [atom.id],
                   candidate_observations: %{
                     atom.id => %{
                       observation_id: Ash.UUID.generate(),
                       question_hash: Fixtures.hash_of(atom.id),
                       value: "supports"
                     }
                   }
                 },
                 action: :assemble,
                 authorize?: false
               )
    end

    test "record_adjudication fills the pipeline fields, join still enforced", %{
      atoms: [atom | _]
    } do
      evaluation = Fixtures.start_evaluation(Fixtures.ingest_document(67))
      packet = Fixtures.assemble_packet(evaluation, [atom.id])

      packet =
        Domain.record_packet_adjudication!(packet, %{
          candidate_observations: %{
            atom.id => Fixtures.observation_join(Ash.UUID.generate(), Fixtures.hash_of("q"))
          },
          selected_atom_ids: [atom.id],
          missing_dimensions: ["amount"],
          requires_expansion: false
        })

      assert packet.selected_atom_ids == [atom.id]
      assert packet.candidate_observations[atom.id]["question_hash"] == Fixtures.hash_of("q")

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(
                 packet,
                 %{candidate_observations: %{atom.id => %{"answer" => "0.97"}}},
                 action: :record_adjudication,
                 authorize?: false
               )
    end
  end
end
