# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AtomRepresentation do
  @moduledoc """
  The replaceable retrieval projection of one addressed atom — the row the
  vector leg of retrieval scores against.

  **The projection, never the atom.** Retrieval indexes a representation
  of an atom, not the authoritative atom: the authoritative `text` stays
  on `AshEvidence.AddressedAtom` (and stays payload class); this resource
  carries what the host chose to project (`representation`) plus the
  embedding computed from it. Re-projecting an atom rewrites the
  representation and VOIDS the stale embedding — a vector is meaningful
  only against the representation it was embedded from.

  **The host embeds; this package records.** There is no embedding model
  here — the same posture as `ParseRun` (the host does its model work
  outside the package and records the outcome). `record_embedding` takes
  the vector the host's embedder produced, and `embedding_model` /
  `embedding_model_version` pin which model produced it — so a host can
  tell whether two embeddings are even comparable (cosine across models
  is meaningless) and re-embed wholesale when it changes models. Retrieval
  scopes the vector leg with `embedding_model` for exactly that reason.

  The `embedding` column is a dimensionless pgvector `vector`: the
  dimensionality is the host model's business, not the package schema's.
  Exact cosine scan is deterministic (a property retrieval relies on); a
  host that needs ANN at scale adds an `hnsw` index on this column
  host-side, pinned to its model's dimensions — the retrieval query is
  unchanged by that.

  Lexical retrieval does NOT use this resource — it scores the atoms'
  own text (`to_tsvector` over `addressed_atoms.text`, GIN-indexed).
  This row exists for the vector leg alone.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "atom_representations"
    repo AshEvidence.Repo

    references do
      # Erasure linkage: representations are projections of content and die
      # with it (the version, or the atom they project).
      reference :addressed_atom, on_delete: :delete
      reference :document_version, on_delete: :delete
    end

    custom_indexes do
      # The version-scoped vector leg filters on this; the unique-atom
      # identity only indexes the atom side.
      index [:document_version_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :project do
      primary? true
      accept [:addressed_atom_id, :document_version_id, :representation]

      # Replaceable projection: re-projecting is an upsert that rewrites
      # the representation and voids whatever embedding the previous
      # representation carried.
      upsert? true
      upsert_identity :unique_atom
      upsert_fields [:representation, :embedding, :embedding_model, :embedding_model_version]

      change set_attribute(:embedding, nil)
      change set_attribute(:embedding_model, nil)
      change set_attribute(:embedding_model_version, nil)
    end

    update :record_embedding do
      accept [:embedding, :embedding_model, :embedding_model_version]
    end

    read :for_version do
      argument :document_version_id, :uuid, allow_nil?: false
      filter expr(document_version_id == ^arg(:document_version_id))
      prepare build(sort: [:id])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :representation, :string, allow_nil?: false, public?: true

    # Payload class, like the atom's text: ids are the packet currency,
    # vectors resolve from the store and are never loaded by default.
    attribute :embedding, :vector do
      public? false
      select_by_default? false
    end

    attribute :embedding_model, :string, public?: true
    attribute :embedding_model_version, :string, public?: true

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end

    update_timestamp :updated_at
  end

  relationships do
    belongs_to :addressed_atom, AshEvidence.AddressedAtom do
      allow_nil? false
      public? true
    end

    belongs_to :document_version, AshEvidence.DocumentVersion do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_atom, [:addressed_atom_id]
  end
end
