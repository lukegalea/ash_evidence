# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Changes.CheckOutcome do
  @moduledoc """
  Closes a `ParseRun` at creation from a check's outcome: `passed?: true`
  writes `:ok`, `passed?: false` writes `:failed`.

  Only a literal `true` is a pass. The argument is a non-nil boolean, so a
  missing outcome, or one the caller has as `:errored` or `:unmeasured`,
  is refused before anything is written rather than coerced either way;
  the clause below is the second line, not the first.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    status =
      case Ash.Changeset.get_argument(changeset, :passed?) do
        true -> :ok
        _not_a_pass -> :failed
      end

    Ash.Changeset.force_change_attribute(changeset, :status, status)
  end
end
