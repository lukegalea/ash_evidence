# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Preparations.VersionInTenant do
  @moduledoc """
  When a read carries a `tenant:`, keep only rows whose document version
  exists under that tenant (the version's attribute-tenant filter applies
  through the `exists`). With no tenant the read is unchanged.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(%{tenant: nil} = query, _opts, _context), do: query

  def prepare(query, _opts, _context),
    do: Ash.Query.filter(query, exists(document_version, true))
end
