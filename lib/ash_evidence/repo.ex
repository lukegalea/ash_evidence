# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Repo do
  @moduledoc """
  The default repo of the evidence resources, and the owner of their
  migrations.

  The resources use `AshEvidence.repo/0`, which answers this module unless
  the host sets `config :ash_evidence, :repo, MyApp.Repo`. Migrations always
  ship under this repo: a host that uses its own repo keeps this one
  configured against the same database (and in `ecto_repos`) so the
  migrations run; it need not start it at runtime. The credentials are
  host configuration (`config :ash_evidence, AshEvidence.Repo, ...`), as is
  the database itself — a host points the package at its own database, in
  its own residency zone. The `priv` path for migrations is also host
  config; hosts set `priv: "priv/repo"`, which holds only the package's
  migrations. `priv/test_repo` holds the suite's test-host tables and is run by
  the test helper alongside it (see `config/config.exs`).

  `btree_gist` is the Phase 0 (PostgreSQL 18) temporal-readiness floor
  (the ash_judgments posture): the later temporal surfaces build exclusion
  constraints over range types, and every non-GiST-native column in such a
  constraint needs this extension. `vector` is pgvector: the
  `AtomRepresentation.embedding` column and the cosine distance operator
  the retrieval vector leg scores with. The repo's `types` config points
  at the package's PostgrexTypes module (see
  `AshPostgres.Extensions.Vector` for the shape) — the binary
  encode/decode for vector values.

  The schema is host configuration too: `default_prefix:` under the repo's
  config names the schema the evidence tables live in, `"public"` when unset
  (`default_prefix/0`). A host that keeps its own tables in a schema of its
  own (sharing a database with another system's `public`, say) sets it, and
  `migration_default_prefix:` to the same schema, and puts that schema first
  on the repo's `search_path` (`parameters: [search_path: "evidence,public"]`).
  The tables and the migration history then land there, and reads and writes
  find them there: the resources name no schema, so their queries resolve
  through the search path, and the migrations resolve their foreign keys
  with `prefix()`, never a literal schema.
  """

  use AshPostgres.Repo, otp_app: :ash_evidence, warn_on_missing_ash_functions?: false

  @doc """
  The schema the evidence tables are read from and written to: the repo
  config's `default_prefix:` (`config :ash_evidence, AshEvidence.Repo,
  default_prefix: "evidence"`), or `"public"`. Read at runtime, from the
  application environment, because the `init/2` that `use AshPostgres.Repo`
  defines overwrites any `default_prefix` in the repo config with this
  callback's answer.
  """
  def default_prefix do
    :ash_evidence |> Application.get_env(__MODULE__, []) |> Keyword.get(:default_prefix, "public")
  end

  def installed_extensions, do: ["uuid-ossp", "citext", "ash-functions", "btree_gist", "vector"]

  # Phase 0 pins the declared floor to the server the programme develops
  # against (PostgreSQL 18; the ash_enterprise devenv provides 18.4). This is
  # ash_postgres' feature-gating declaration, not a runtime server check.
  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}
end
