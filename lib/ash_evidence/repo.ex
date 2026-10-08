# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Repo do
  @moduledoc """
  The PostgreSQL repo behind the evidence resources.

  The resources are package-owned and name this repo; the credentials are
  host configuration (`config :ash_evidence, AshEvidence.Repo, ...`), as is
  the database itself — a host points the package at its own database, in
  its own residency zone. The `priv` path for migrations is also host
  config; the package's own suite uses `priv/test_repo` (see
  `config/config.exs`).

  `btree_gist` is the Phase 0 (PostgreSQL 18) temporal-readiness floor
  (the ash_judgments posture): the later temporal surfaces build exclusion
  constraints over range types, and every non-GiST-native column in such a
  constraint needs this extension. `vector` is pgvector: the
  `AtomRepresentation.embedding` column and the cosine distance operator
  the retrieval vector leg scores with. The repo's `types` config points
  at the package's PostgrexTypes module (see
  `AshPostgres.Extensions.Vector` for the shape) — the binary
  encode/decode for vector values.
  """

  use AshPostgres.Repo, otp_app: :ash_evidence, warn_on_missing_ash_functions?: false

  def installed_extensions, do: ["uuid-ossp", "citext", "ash-functions", "btree_gist", "vector"]

  # Phase 0 pins the declared floor to the server the programme develops
  # against (PostgreSQL 18; the ash_enterprise devenv provides 18.4). This is
  # ash_postgres' feature-gating declaration, not a runtime server check.
  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}
end
