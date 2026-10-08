# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Validations.PendingTransition do
  @moduledoc """
  A record's status leaves its starting state exactly once.

  ParseRun: `:pending` moves to `:ok`/`:failed` once — a closed run
  cannot be re-closed, and the record of how a pass ended cannot be
  rewritten. EvalSet: `:open` moves to `:published` once — a published
  eval set is frozen, and a correction is a new set version.

  The starting state is an option (`from:`, default `:pending`); the
  field is always `status`. Implements both the eager check (read the
  persisted status off `changeset.data`) and the atomic form, so the
  update actions that use it keep their default `require_atomic? true`.
  """

  use Ash.Resource.Validation

  import Ash.Expr

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    from = Keyword.get(opts, :from, :pending)

    case changeset.data && changeset.data.status do
      ^from ->
        :ok

      other ->
        {:error, field: :status, message: "status has already left #{from} (#{other})"}
    end
  end

  @impl true
  def atomic(_changeset, opts, _context) do
    # Pin through expression forms (the ash-core builtin pattern —
    # attribute_does_not_equal): a bare `^var` parses as a reference.
    opts = Keyword.put_new(opts, :from, :pending)

    {:atomic, [:status], expr(status != ^opts[:from]),
     expr(
       error(^InvalidAttribute, %{
         field: :status,
         value: ^atomic_ref(:status),
         message: ^"status has already left #{opts[:from]}"
       })
     )}
  end
end
