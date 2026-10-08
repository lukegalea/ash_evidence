# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvidenceEvaluation do
  @moduledoc """
  One adjudication run: one predicate × subject × document version ×
  question-set hash — the unit the packets ticket evaluates.

  The run row is the ParseRun pattern applied to adjudication: it starts
  `:pending` BEFORE any instrument work, and closes exactly once,
  `:ok` or `:failed`, by no-input actions (`:ok`/`:failed` cannot be
  rewritten, and a closed evaluation cannot re-close). The host's
  orchestrator does the actual adjudication — per-candidate evidence
  questions through its judge actions — outside this package; this row
  records that the loop ran and how it ended.

  Ids, never content: `candidate_set_ids` cite the persisted
  `AshEvidence.CandidateSet` search proofs (initial retrieval plus one
  per expansion step), `expansion_steps` records each proof-growth step
  as `%{step, candidate_set_id, observation_ids}` — observation IDs are
  ledger row ids, never copied answers. The row cascades away with its
  document version (erasure linkage): it is a search-describing record,
  blob-class like the packets and candidate sets it cites.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshEvidence.Validations.PendingTransition

  postgres do
    table "evidence_evaluations"
    repo AshEvidence.Repo

    references do
      reference :document_version, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      primary? true

      accept [
        :subject,
        :predicate,
        :rule_ref,
        :document_version_id,
        :question_set_hash,
        :candidate_set_ids,
        :expansion_steps,
        :profile,
        :call_shape
      ]

      # `status` is not accepted: an evaluation starts pending,
      # structurally.
    end

    update :mark_ok do
      accept []
      validate PendingTransition
      change set_attribute(:status, :ok)
      change atomic_update(:closed_at, expr(now()))
    end

    update :mark_failed do
      accept []
      validate PendingTransition
      change set_attribute(:status, :failed)
      change atomic_update(:closed_at, expr(now()))
    end

    read :for_version do
      argument :document_version_id, :uuid, allow_nil?: false
      filter expr(document_version_id == ^arg(:document_version_id))
      prepare build(sort: [:created_at])
    end
  end

  attributes do
    uuid_primary_key :id

    # The §7.4 composite subject term: the eventual fact's subject.
    attribute :subject, :map do
      allow_nil? false
      public? true

      constraints fields: [
                    type: [type: :string, allow_nil?: false],
                    id: [type: :string, allow_nil?: false]
                  ]
    end

    # The question id (`judgment:v0:…#judgments/<name>`) — the eventual
    # fact's predicate.
    attribute :predicate, :string, allow_nil?: false, public?: true

    # The DMN rule that queued the question, when there was one.
    attribute :rule_ref, :map do
      public? true

      constraints fields: [
                    bundle_hash: [type: :string],
                    rule_id: [type: :string],
                    predicate_id: [type: :string]
                  ]
    end

    # Law 6's field: the hash of the question set the loop ran.
    attribute :question_set_hash, :string, allow_nil?: false, public?: true

    # The persisted CandidateSets this loop cited: the initial retrieval
    # plus one per expansion step.
    attribute :candidate_set_ids, {:array, :uuid} do
      allow_nil? false
      public? true
      default []
    end

    attribute :expansion_steps, {:array, :map} do
      allow_nil? false
      public? true
      default []

      constraints items: [
                    fields: [
                      step: [type: :integer, allow_nil?: false],
                      candidate_set_id: [type: :uuid, allow_nil?: false],
                      observation_ids: [type: {:array, :uuid}, allow_nil?: false]
                    ]
                  ]
    end

    attribute :profile, :string, allow_nil?: false, public?: true

    attribute :call_shape, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:candidate_local, :whole_document]
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :ok, :failed]
    end

    attribute :closed_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end
  end

  relationships do
    belongs_to :document_version, AshEvidence.DocumentVersion do
      allow_nil? false
      public? true
    end
  end
end
