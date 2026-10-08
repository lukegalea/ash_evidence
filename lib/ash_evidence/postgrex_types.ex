# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

# The Postgrex type extensions the package's repo needs — currently
# `AshPostgres.Extensions.Vector`, the binary encoder/decoder for the
# pgvector `vector` type behind `AtomRepresentation.embedding`.
#
# `Postgrex.Types.define/3` generates (and defines) the module itself, so
# this call stands at the file's top level, outside any module — the
# shape the ash_postgres docs prescribe.
#
# The repo config points at this module (`config :ash_evidence,
# AshEvidence.Repo, types: AshEvidence.PostgrexTypes`); a host that
# defines its own Postgrex types module appends
# `AshPostgres.Extensions.Vector` to its list the same way.
Postgrex.Types.define(
  AshEvidence.PostgrexTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
