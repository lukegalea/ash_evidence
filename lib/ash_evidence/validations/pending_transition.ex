# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Validations.PendingTransition do
  @moduledoc """
  A parse run's status moves out of `:pending` exactly once.

  `:ok` and `:failed` are terminal: a closed run cannot be re-closed (as
  `:ok` after `:failed`, or at all). This is the run-lifecycle core of the
  seam: an instrument pass happens once, and the record of how it ended
  cannot be rewritten afterwards.

  Implements both the eager check (read the persisted status off
  `changeset.data`) and the atomic form, so the update actions that use it
  keep their default `require_atomic? true`.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case changeset.data && changeset.data.status do
      :pending -> :ok
      other -> {:error, field: :status, message: "parse run is no longer pending (#{other})"}
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:status], expr(status != :pending),
     expr(
       error(^InvalidAttribute, %{
         field: :status,
         value: ^atomic_ref(:status),
         message: "parse run is no longer pending"
       })
     )}
  end
end
