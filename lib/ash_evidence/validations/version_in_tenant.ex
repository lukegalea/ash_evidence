# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Validations.VersionInTenant do
  @moduledoc """
  When a write carries a `tenant:`, the document version it hangs off must
  exist under that tenant.

  `DocumentVersion` is the only tenanted resource; its children (runs,
  atoms, representations, candidate sets, evaluations, eval items) are
  keyed by `document_version_id`. Without this check a tenant-B caller
  could write evidence into tenant A's version by id. With no tenant on the
  changeset the check does nothing, so untenanted callers are unchanged.

  Updates are checked against the version the persisted record points at.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(%{tenant: nil}, _opts, _context), do: :ok

  def validate(changeset, _opts, _context) do
    version_id = Ash.Changeset.get_attribute(changeset, :document_version_id)

    if is_nil(version_id) or
         version_exists?(version_id, changeset.tenant) do
      :ok
    else
      {:error,
       InvalidAttribute.exception(
         field: :document_version_id,
         message: "does not exist in this tenant"
       )}
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: validate(changeset, opts, context)

  defp version_exists?(version_id, tenant) do
    AshEvidence.DocumentVersion
    |> Ash.Query.filter(id == ^version_id)
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end
end
