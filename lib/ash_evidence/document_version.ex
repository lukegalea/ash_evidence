# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.DocumentVersion do
  @moduledoc """
  One immutable document version: the bytes of a document and the SHA-256
  content hash that pins them.

  Immutability is structural, not conventional: the resource defines **no
  update action at all** — the only writes are `ingest` and (for erasure)
  `destroy`. A new rendition of a document is a NEW version row, never a
  mutation; every run and atom hangs off the version it actually saw.

  Ported from the slice-0 blob (`AshEnterprise.Evidence.Blob`): bytes,
  content hash, immutable-by-action-shape. Deltas: slice-0 carried
  `subject_ref` and the zone's data-class/residency machinery — host
  posture, not pipeline; the standalone package content-addresses instead
  (`unique_content` on the hash), so re-ingesting the same bytes is the
  same version row.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "document_versions"
    repo AshEvidence.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :ingest do
      primary? true
      accept [:kind, :bytes, :sha256]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :string, allow_nil?: false, public?: true

    # Evidence class: the bytes themselves are not public surface. Atom ids
    # are the packet currency, not document content.
    attribute :bytes, :binary, allow_nil?: false, public?: false

    # Lowercase hex SHA-256 of `bytes`, computed by the caller (the slice-0
    # discipline: the pipeline hashes, the store records).
    attribute :sha256, :string, allow_nil?: false, public?: true

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end
  end

  identities do
    # Content addressing: the same bytes are the same version, wherever
    # they came from. Idempotent re-ingest is an identity conflict, not a
    # second row.
    identity :unique_content, [:sha256]
  end
end
