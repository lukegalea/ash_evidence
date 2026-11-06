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

  ## Tenants

  The resource is multitenant by attribute with `global? true`: the
  `tenant` attribute holds the host's tenant as `Ash.ToTenant` gives it
  (a string), and is `nil` for untenanted use. With a tenant, reads see only
  that tenant's versions and writes are stamped with it. **With no tenant, a
  read is unscoped and sees every tenant's versions.** A host that tenants
  passes the tenant on every version read and write; the package has no
  authorizer, and isolation is the host's.

  Only `DocumentVersion` carries the tenant column; its children (runs,
  atoms, representations, candidate sets, evaluations, eval items) are
  keyed by version id. A call that passes `tenant:` is scoped through the
  version: creates and updates validate that the version exists under that
  tenant (`AshEvidence.Validations.VersionInTenant`), reads keep only rows
  whose version is in that tenant (`AshEvidence.Preparations.VersionInTenant`),
  and `retrieve/3` takes `tenant:` too. With no tenant nothing is scoped.
  Packets and eval sets are reached through their evaluation or set and are
  not scoped by tenant themselves.

  Content addressing is per tenant: the same bytes in the same tenant are
  the same version (`unique_content` is `(tenant, sha256)`, nulls not
  distinct, so untenanted re-ingest is one row too), and the same bytes in
  two tenants are two rows.

  ## Erasure

  `AshEvidence.Domain.destroy_document_version/1-2` (takes the version id; pass
  `tenant:`) reads the version under the tenant, then deletes it; the database cascade removes its parse runs, atoms,
  representations, candidate sets, evaluations, packets and eval items.
  Erase host documents only, never corpus versions: eval items that cite a
  version go with it.

  Ported from the slice-0 blob (`AshEnterprise.Evidence.Blob`): bytes,
  content hash, immutable-by-action-shape. Deltas: slice-0 carried
  `subject_ref` and the zone's data-class/residency machinery — host
  posture, not pipeline; the standalone package content-addresses instead.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "document_versions"
    repo fn _resource, _type -> AshEvidence.repo() end
  end

  multitenancy do
    strategy :attribute
    attribute :tenant
    global? true
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
    # The host's tenant as `Ash.ToTenant` gives it. Nil for untenanted use.
    attribute :tenant, :string, public?: true

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
    # Content addressing, per tenant: the same bytes in the same tenant are
    # the same version. Idempotent re-ingest is an identity conflict, not a
    # second row. `nils_distinct?: false` keeps untenanted (tenant NULL)
    # re-ingest one row too.
    identity :unique_content, [:sha256], nils_distinct?: false
  end
end
