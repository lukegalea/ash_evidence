# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Packet do
  @moduledoc """
  The evidence packet: what one evaluation's adjudication saw and chose,
  as **atom ids only** — never text, never copied answers.

  The packet is the join between the search proof and the judgment
  ledger, and it cites rather than carries:

    * `candidate_atom_ids` — the atoms adjudication was narrowed to
      (feeds each observation's `source_enum`, so a citation outside
      the packet cannot decode).
    * `candidate_observations` — `atom_id → %{observation_id,
      question_hash}`: the LEDGER IDS. The answers live on the ledger
      rows; the packet references them, never copies them (a
      validation rejects anything that is not exactly the id+hash
      join — an answer has no key to hide in).
    * `selected_atom_ids` / `limiting_atom_ids` / `missing_dimensions`
      — what the deterministic pipeline steps chose, limited and found
      absent (amounts, dates, units, parties, modality are code-checked,
      not model-guessed).
    * `requires_expansion` — the proof-growth flag: insufficient evidence
      expands one step, to budget, each step a new persisted CandidateSet
      cited by the evaluation.

  Search provenance stays on the cited `CandidateSet` rows (hashes,
  index versions, k, per-framing ranks); the packet adds none. Retrieval
  scores are provenance, never inputs to aggregation. The packet
  cascades away with its evaluation (and so with the document version):
  it is blob-class — a description of a search over content, dying with
  the content, while the assertion that cites it survives as ids.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshEvidence.Validations.ObservationJoin

  postgres do
    table "evidence_packets"
    repo AshEvidence.Repo

    references do
      reference :evaluation, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :assemble do
      primary? true

      accept [
        :evaluation_id,
        :candidate_atom_ids,
        :candidate_observations,
        :selected_atom_ids,
        :limiting_atom_ids,
        :missing_dimensions,
        :requires_expansion
      ]

      validate ObservationJoin
    end

    update :record_adjudication do
      description """
      The deterministic pipeline steps fill in what was chosen, limited
      and found absent, and the observation join as the per-candidate
      judgments land. Ids and hashes only — the validation keeps it a
      join, not a copy.
      """

      accept [
        :candidate_observations,
        :selected_atom_ids,
        :limiting_atom_ids,
        :missing_dimensions,
        :requires_expansion
      ]

      validate ObservationJoin

      # The ObservationJoin check inspects the shape of a jsonb payload
      # (per-atom join maps) — not expressible as a single SQL
      # expression. Adjudication fills one packet from one orchestrator
      # process; concurrent fills of one packet are not a sanctioned
      # shape, so eager validation loses nothing here.
      require_atomic? false
    end

    read :for_evaluation do
      argument :evaluation_id, :uuid, allow_nil?: false
      filter expr(evaluation_id == ^arg(:evaluation_id))
      prepare build(sort: [:created_at])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :candidate_atom_ids, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :candidate_observations, :map do
      allow_nil? false
      public? true
      default %{}
    end

    attribute :selected_atom_ids, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :limiting_atom_ids, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :missing_dimensions, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :requires_expansion, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end
  end

  relationships do
    belongs_to :evaluation, AshEvidence.EvidenceEvaluation do
      allow_nil? false
      public? true
    end
  end
end
