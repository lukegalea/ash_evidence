# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

import Config

# The suite talks to a real PostgreSQL through the sandboxed package repo
# (see lib/ash_evidence/repo.ex and test/test_helper.exs). `SKIP_DB=1`
# excludes the `:db`-tagged tests for runs without a database.
if System.get_env("SKIP_DB") do
  config :ash_evidence, :db_tests_enabled?, false
else
  config :ash_evidence, :db_tests_enabled?, true
end

# The suite's own database, created and migrated by the test helper on the
# fly — a fresh clone needs no setup task. The devenv's Postgres exports
# PGHOST/PGPORT and DB_USER/DB_PASSWORD (same env pattern as
# ash_judgments/ash_agent_tools, so the devenv-wrapped invocation works
# unchanged).
config :ash_evidence, AshEvidence.Repo,
  database: "ash_evidence_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  queue_target: 1000,
  types: AshEvidence.PostgrexTypes

# Ash loads relationships in spawned Tasks by default; those processes do
# not own the sandbox connection and hit DBConnection.OwnershipError
# intermittently. The standard fix, and what `mix igniter.install
# ash_postgres` writes.
config :ash, disable_async?: true

# The package's domain ships with `validate_config_inclusion?: false` (a
# library-shipped domain belongs in the HOST's ash_domains) — nothing to
# silence per environment.

config :logger, level: :warning
