# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalItem do
  @moduledoc """
  One eval pair: a corpus document version, the claim evaluated against
  it, the expected outcome, and the split the item belongs to.

  The item is the measurement unit of the eval-set discipline:

    * `document_version_id` — the corpus document the claim is evaluated
      against (a version's atoms are the ground-truth spans);
    * `claim` — the assertion text;
    * `gold_atom_ids` — the atoms that CARRY the truth (empty exactly
      when the document is silent on the claim — the
      `:insufficient` substrate);
    * `expected_disposition` — the frozen evidence vocabulary value a
      correct adjudication of the gold span yields;
    * `expected_hypothesis` — which retrieval framing the gold atoms
      must surface under (`:supports`/`:contradicts`/`:exception`; nil
      when there is no gold span);
    * `source` + `license` — per-item provenance (the synthetic corpus
      dedicates every item CC0-1.0);
    * `split` — `:optimise`/`:calibration`/`:test` (drawn, the draw
      recorded on the set) or `:audit` — which is NEVER drawn: audit
      rows arrive from production with their own explicit split,
      honoured verbatim.

  Items are immutable and never move between splits — there is no
  update action; a correction is a new eval-set version. Items are
  added only while their set is `:open`.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshEvidence.EvalSets.Changes.RequireOpenSet

  postgres do
    table "eval_items"
    repo AshEvidence.Repo

    references do
      reference :document_version, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :add do
      primary? true

      accept [
        :eval_set_id,
        :document_version_id,
        :ordinal,
        :claim,
        :gold_atom_ids,
        :expected_disposition,
        :expected_hypothesis,
        :source,
        :license,
        :split
      ]

      change RequireOpenSet
    end

    read :for_set do
      argument :eval_set_id, :uuid, allow_nil?: false
      filter expr(eval_set_id == ^arg(:eval_set_id))
      prepare build(sort: [:ordinal])
    end
  end

  attributes do
    uuid_primary_key :id

    # The item's address within its set — the ordinal the draw ran in
    # (reconstructible: same seed, same ordinals, same splits).
    attribute :ordinal, :integer, allow_nil?: false, public?: true

    attribute :claim, :string, allow_nil?: false, public?: true

    attribute :gold_atom_ids, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :expected_disposition, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:supports, :contradicts, :insufficient, :not_applicable, :wrong_scope]
    end

    attribute :expected_hypothesis, :atom do
      public? true
      constraints one_of: [:supports, :contradicts, :exception]
    end

    attribute :source, :string, allow_nil?: false, public?: true

    attribute :license, :string do
      allow_nil? false
      public? true
      default "CC0-1.0"
    end

    attribute :split, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:optimise, :calibration, :test, :audit]
    end

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end
  end

  relationships do
    belongs_to :eval_set, AshEvidence.EvalSet do
      allow_nil? false
      public? true
    end

    belongs_to :document_version, AshEvidence.DocumentVersion do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_ordinal_per_set, [:eval_set_id, :ordinal]
  end
end
