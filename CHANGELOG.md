# Changelog

## 0.2.0

### Breaking

- `DocumentVersion` is multitenant by attribute (`tenant`, a string; `global? true`).
  Untenanted use is unchanged, but **an untenanted read sees every tenant's
  versions**: a host that tenants passes the tenant on every version read and write.
- `unique_content` is per tenant: identical bytes in two tenants are two versions.
  The identity keeps its name and its upsert shape; its index is `(tenant, sha256)`
  with nulls not distinct, so untenanted re-ingest of the same bytes is still one row.
  Existing rows get `tenant = NULL`: a tenanted read cannot see them, and a tenanted
  ingest of the same bytes creates a new row. A host that starts passing a tenant
  backfills `tenant` or resets that data. A host with no tenanted resources needs
  nothing. A host whose tenanted resources hold a `belongs_to :document_version` is
  tenanting: Ash passes the parent's tenant into the relationship load, which hides
  every NULL-tenant version. It must ingest with the same tenant in the same release
  (`to_tenant`) and backfill or reset existing rows.
  The migration's `down` fails if two tenants already hold the same bytes.
- Deleting a version, or a parse run, now cascades to its parse runs and atoms.
  Before, a parsed version could not be deleted. No migration path is needed; it is
  the fix. Deleting a version also deletes the eval items that cite it, so erase host
  documents only, never corpus versions.

- Child calls (runs, atoms, representations, candidate sets, evaluations, eval items,
  `retrieve/3`) that pass `tenant:` are scoped through their version: a write to a
  version outside that tenant is a validation error and reads filter by it. Without
  `tenant:` nothing changes. Packets and eval sets are not scoped themselves.

### Added

- `config :ash_evidence, :repo, MyApp.Repo` and `AshEvidence.repo/0`: all resources
  and `AshEvidence.Retrieval` use the host's repo, so a host can write a version and
  its own records in one transaction. The default is `AshEvidence.Repo`. The host
  repo needs the `vector` extension, Postgrex `types:` including
  `AshPostgres.Extensions.Vector`, PostgreSQL 18, `"ash-functions"` in
  `installed_extensions/0`, and a `default_prefix/0` naming the schema the evidence
  migrations ran into. Migrations still ship under
  `AshEvidence.Repo`, which the host keeps configured against the same database.
- `AshEvidence.Domain.destroy_document_version/1-2` (takes the version id).

### Also since 0.1.0

These landed on `main` without a version bump; hosts pinned before them cross them now.

- `AddressedAtom` has `kind`, `page` and `geometry`, and `ingest_atom` takes `kind`
  as its fifth argument. `bbox` is removed. The migration adds `kind NOT NULL` with no
  default, so it fails on a database that already holds atoms.
- `default_prefix` and `prefix()` in the migrations.
