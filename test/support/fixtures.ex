# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Test.Fixtures do
  @moduledoc """
  Synthetic fixtures for the suite: a fake document (deterministic bytes,
  not a real certificate), and the seed helpers that mirror the slice-0
  pipeline sequence — version → run → atoms — with NO instrument on the
  path (the atoms are seeded directly; that is the seam this package
  leaves to the host).
  """

  import Ash.Changeset, only: [for_create: 3]

  alias AshEvidence.{AddressedAtom, Domain}

  @doc "Deterministic fake document bytes: the serial is in the content."
  def document_bytes(serial), do: "SYNTH-DOC-#{serial}\n" <> String.duplicate("body ", 64)

  @doc "The lowercase hex SHA-256 the caller computes (the slice-0 discipline)."
  def sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @doc """
  Ingest a synthetic document version via the domain's code interface.
  """
  def ingest_document(serial \\ 1) do
    bytes = document_bytes(serial)
    Domain.ingest_document!("image/png", bytes, sha256(bytes))
  end

  @doc """
  Start a parse run over a version with a synthetic instrument name. No
  model id or endpoint literal ever belongs here — the package pins no
  instrument.
  """
  def start_run(version, opts \\ []) do
    Domain.start_parse_run!(
      version.id,
      Keyword.get(opts, :instrument, "synthetic-test-instrument"),
      Keyword.get(opts, :config, %{})
    )
  end

  @doc """
  Seed atoms directly (no instrument): `lines` become seq-ordered spans of
  the version. Returns them in seq order.
  """
  def seed_atoms(version, run, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {text, seq} ->
      Domain.ingest_atom!(version.id, run.id, seq, text)
    end)
  end

  @doc """
  The changeset form, for tests that exercise `Ash.create` directly rather
  than the domain interfaces.
  """
  def atom_changeset(version, run, seq, text, extra \\ %{}) do
    for_create(
      AddressedAtom,
      :ingest,
      Map.merge(
        %{
          document_version_id: version.id,
          parse_run_id: run.id,
          seq: seq,
          text: text
        },
        extra
      )
    )
  end

  @doc """
  The embedding model name fixtures use: a SYNTHETIC model label, not a
  real model id — the package never names (or calls) an embedder, and the
  fixtures follow the package contract.
  """
  def embedder, do: "synthetic-test-embedder"

  @doc """
  Project an atom for the vector leg (the host-side seam, exercised):
  representation defaults to the atom's own text.
  """
  def project_atom(atom, representation \\ nil) do
    Domain.project_atom!(
      atom.id,
      atom.document_version_id,
      representation || atom.text
    )
  end

  @doc """
  Record an embedding on a projection — the vector the host's embedder
  computed for the representation, plus which synthetic model produced it.
  """
  def record_embedding(rep, vector, opts \\ []) do
    Domain.record_embedding!(
      rep.id,
      vector,
      Keyword.get(opts, :model, embedder()),
      Keyword.get(opts, :version, "1")
    )
  end

  @doc "A synthetic subject term (§7.4 composite subject)."
  def subject(serial \\ "1"), do: %{type: "synthetic_subject", id: "subj-#{serial}"}

  @doc "A synthetic hash of some term."
  def hash_of(term), do: Base.encode16(:crypto.hash(:sha256, term), case: :lower)

  @doc "A synthetic question id (the registry's shape, never a real one)."
  def predicate, do: "judgment:v0:synth#judgments/synthetic_predicate"

  @doc """
  Start an evaluation run row over a version (the orchestrator's first
  record; synthetic profile/predicate — the package pins no instrument).
  """
  def start_evaluation(version, opts \\ []) do
    Domain.start_evaluation!(%{
      subject: Keyword.get(opts, :subject, subject()),
      predicate: Keyword.get(opts, :predicate, predicate()),
      rule_ref: Keyword.get(opts, :rule_ref, nil),
      document_version_id: version.id,
      question_set_hash: Keyword.get(opts, :question_set_hash, hash_of("question-set")),
      candidate_set_ids: Keyword.get(opts, :candidate_set_ids, []),
      expansion_steps: Keyword.get(opts, :expansion_steps, []),
      profile: Keyword.get(opts, :profile, "synthetic-test-profile"),
      call_shape: Keyword.get(opts, :call_shape, :candidate_local)
    })
  end

  @doc "Assemble a packet for an evaluation: atom ids and observation joins only."
  def assemble_packet(evaluation, candidate_atom_ids, opts \\ []) do
    Domain.assemble_packet!(%{
      evaluation_id: evaluation.id,
      candidate_atom_ids: candidate_atom_ids,
      candidate_observations: Keyword.get(opts, :candidate_observations, %{}),
      selected_atom_ids: Keyword.get(opts, :selected_atom_ids, []),
      limiting_atom_ids: Keyword.get(opts, :limiting_atom_ids, []),
      missing_dimensions: Keyword.get(opts, :missing_dimensions, []),
      requires_expansion: Keyword.get(opts, :requires_expansion, false)
    })
  end

  @doc """
  The observation join the packet records for one judged atom: the
  ledger row's id and the question hash — never the answer.
  """
  def observation_join(observation_id, question_hash) do
    %{observation_id: observation_id, question_hash: question_hash}
  end

  @doc "A synthetic evidence observation for the aggregation surface."
  def observation(value, probabilities), do: %{value: value, probabilities: probabilities}
end
