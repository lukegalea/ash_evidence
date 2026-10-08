# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

# The package holds no thresholds, policy or instrument settings in config
# (that is a hard "never does" of the package contract — it never calls an
# instrument, so there is nothing to configure). The only configuration is
# the repo: package-owned module, host-owned credentials, and the suite's
# settings.
import Config

config :ash_evidence, ecto_repos: [AshEvidence.Repo]

# This package's own app config: the domain it ships (so `mix ash.codegen`
# discovers its resources). Hosts list the domain under THEIR app's
# `ash_domains`; the domain itself ships `validate_config_inclusion?: false`
# so a host that calls the code interfaces without registering it stays
# warning-free.
config :ash_evidence, ash_domains: [AshEvidence.Domain]

# With ash_postgres on the graph, Ash requires an explicit string length
# count (it is what SQL data layers count) — enforced at COMPILE time by
# the resource transformer, so this lives in the all-envs config. Codepoints
# is the recommended setting.
config :ash, default_string_length_count: :codepoints

# Defaults so `mix ash.codegen` / `mix ash.migrate` work against the
# devenv's Postgres with no extra setup; hosts (and the test env, below)
# override per environment. `priv` is pinned so codegen, migrate and the
# test helper all agree on where the migrations live. `types` carries the
# pgvector encode/decode (`AshEvidence.PostgrexTypes`) — hosts defining
# their own Postgrex types module append `AshPostgres.Extensions.Vector`
# to theirs.
config :ash_evidence, AshEvidence.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST") || System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  priv: "priv/test_repo",
  types: AshEvidence.PostgrexTypes

if config_env() == :test do
  import_config "test.exs"
end
