# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSets.Changes.RequireOpenSet do
  @moduledoc false
  # Items are added only while their eval set is :open — a published set
  # is frozen (the set's :publish is the one terminal transition). The
  # check reads the parent row inside the create's transaction.
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      set_id = Ash.Changeset.get_attribute(changeset, :eval_set_id)

      case Ash.get(AshEvidence.EvalSet, set_id) do
        {:ok, %{status: :open}} ->
          changeset

        {:ok, %{status: published}} ->
          Ash.Changeset.add_error(changeset,
            field: :eval_set_id,
            message:
              "eval set is #{published} — items are frozen; a correction is a new set version"
          )

        {:error, _} ->
          Ash.Changeset.add_error(changeset,
            field: :eval_set_id,
            message: "eval set not found"
          )
      end
    end)
  end
end
