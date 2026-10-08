# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.CandidateSet do
  @moduledoc """
  The durable record of ONE retrieval: what was searched, against which
  indexes, and what came back — the proof a packet can cite.

  Created by `AshEvidence.retrieve/3` with `persist?: true`. Immutable by
  action shape (no update action): a re-run is a new candidate set, never
  a mutation — the same posture as `DocumentVersion`.

  What makes it proof:

    * `claim_hash` / `query_hashes` — SHA-256 of the claim and of each
      framing's query text. Hashes, not text: the claim may quote
      document content, and the record must be safe to keep (and to
      show) without re-introducing it.
    * `lexical_config` — the Postgres text-search configuration the
      lexical leg ran under (the lexical "index version").
    * `embedding_model` / `embedding_model_version` — the vector leg's
      "index version": which embedder the scored vectors came from.
    * `k` and `hypotheses` — the shape of the search that was run.
    * `candidates` — the ranked result as id-shaped data (atom id, seq,
      scores, ranks, hypothesis labels). No text, ever.

  Candidates cascade away with their document version (erasure
  linkage); a `destroy` exists for direct host-driven erasure.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "candidate_sets"
    repo AshEvidence.Repo

    references do
      reference :document_version, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      primary? true

      accept [
        :document_version_id,
        :claim_hash,
        :query_hashes,
        :k,
        :lexical_config,
        :embedding_model,
        :embedding_model_version,
        :hypotheses,
        :candidates
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :claim_hash, :string, allow_nil?: false, public?: true

    attribute :query_hashes, :map do
      public? true
      default %{}
    end

    attribute :k, :integer, allow_nil?: false, public?: true

    attribute :lexical_config, :string do
      allow_nil? false
      public? true
      default "english"
    end

    attribute :embedding_model, :string, public?: true
    attribute :embedding_model_version, :string, public?: true

    attribute :hypotheses, {:array, :atom} do
      allow_nil? false
      public? true
      default []
      constraints one_of: [:supports, :contradicts, :exception]
    end

    attribute :candidates, {:array, :map} do
      allow_nil? false
      public? true
      default []
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
