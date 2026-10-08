# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSet do
  @moduledoc """
  One versioned eval set: an immutable collection of eval items over a
  corpus of document versions — the labelled ground truth retrieval and
  adjudication are measured against (the eval-sets landing discipline).

  Immutability is structural and staged:

    * an `:open` set accepts items (`AshEvidence.EvalItem`);
    * `:publish` is a no-input, terminal transition (`:open →
      :published`, once — the ParseRun close pattern) — a published set
      is frozen;
    * **items never mutate and never move between splits** — moving a
      row between splits is prohibited; a re-split (or any correction)
      is a NEW set version (`unique_name_version`), the old one stands
      untouched.

  The draw is recorded ON the set: `split_seed` and `split_provenance`
  pin how `:optimise`/`:calibration`/`:test` were assigned, so any
  split assignment is reconstructible (`AshEvidence.EvalSets.Draw`).
  `:audit` items are never drawn — they arrive with their own explicit
  split, honoured verbatim. Split membership lives HERE, never on the
  `AddressedAtom`/`ParseRun` records a set exercises.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshEvidence.Validations.PendingTransition

  postgres do
    table "eval_sets"
    repo AshEvidence.Repo
  end

  actions do
    defaults [:read]

    create :open do
      primary? true
      accept [:name, :version, :description, :split_seed, :split_provenance]

      # `status` is not accepted: a set starts open, structurally.
    end

    update :publish do
      description """
      Freezes the set: no items may be added afterwards, and no item
      ever moves. A correction — new items, a re-split, relabelling —
      is a NEW set version.
      """

      accept []
      validate {PendingTransition, from: :open}
      change set_attribute(:status, :published)
      change atomic_update(:published_at, expr(now()))
    end

    read :by_name_version do
      get? true

      argument :name, :string, allow_nil?: false
      argument :version, :integer, allow_nil?: false

      filter expr(name == ^arg(:name) and version == ^arg(:version))
    end
  end

  attributes do
    uuid_primary_key :id

    # The set family's key (`"synthetic-retrieval"`, ...) — the version
    # makes the row: a re-split or relabel is version+1, never a
    # mutation of this one.
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, public?: true

    attribute :description, :string, public?: true

    # The recorded draw: the seed the split assignment ran with (the
    # splits.json discipline — seed and provenance beside the items).
    attribute :split_seed, :integer, allow_nil?: false, public?: true

    attribute :split_provenance, :map do
      allow_nil? false
      public? true
      default %{}
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :open
      constraints one_of: [:open, :published]
    end

    attribute :published_at, :utc_datetime_usec do
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
    has_many :items, AshEvidence.EvalItem do
      public? true
      sort :ordinal
    end
  end

  identities do
    identity :unique_name_version, [:name, :version]
  end
end
