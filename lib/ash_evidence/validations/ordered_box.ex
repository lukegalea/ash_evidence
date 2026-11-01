# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Validations.OrderedBox do
  @moduledoc """
  A box's first corner is its top-left: `x0 <= x1` and `y0 <= y1`.

  The `[0, 1]` range of each coordinate is the attribute's own constraint
  (`AshEvidence.AtomGeometry`); this validation adds the ordering the
  constraint cannot express.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :bbox) do
      %{x0: x0, x1: x1} when x0 > x1 ->
        {:error, field: :bbox, message: "x0 must not exceed x1"}

      %{y0: y0, y1: y1} when y0 > y1 ->
        {:error, field: :bbox, message: "y0 must not exceed y1"}

      _ ->
        :ok
    end
  end
end
