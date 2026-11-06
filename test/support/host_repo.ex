# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Test.HostRepo do
  @moduledoc """
  Stands in for a host's own repo: the same database as `AshEvidence.Repo`
  with its own sandbox pool, and no migrations of its own (the tables are
  the package's, created through `AshEvidence.Repo`). It is what a host
  sets as `config :ash_evidence, :repo`.
  """

  use AshPostgres.Repo, otp_app: :ash_evidence, warn_on_missing_ash_functions?: false

  def default_prefix, do: "public"

  def installed_extensions, do: ["uuid-ossp", "citext", "ash-functions", "btree_gist", "vector"]

  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}
end
