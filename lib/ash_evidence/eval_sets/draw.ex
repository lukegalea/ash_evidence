# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSets.Draw do
  @moduledoc """
  The split draw: `:optimise` / `:calibration` / `:test` assigned
  randomly from the set's recorded seed; `:audit` never drawn.

  Discipline (the eval-sets landing rules):

    * **Split before labelling** — the draw runs over the item specs
      before expected outcomes are attached downstream; this function
      only sees split-neutral specs.
    * **Audit rows arrive with their own explicit split and are
      honoured verbatim** — they do not participate in the draw and do
      not advance it.
    * **Reconstructibility** — the RNG is seeded per set seed and
      advances ONLY on drawn items: replaying the same specs in the
      same order with the same seed yields the same assignment, so the
      recorded `split_seed` on the set reproduces every split.
    * **No moving** — the draw assigns at item creation; items never
      change split afterwards (there is no update action to do it
      with). A re-split is a new eval-set version.
  """

  @drawn_splits [:optimise, :calibration, :test]

  @doc "The splits the draw assigns from."
  @spec drawn_splits() :: [atom()]
  def drawn_splits, do: @drawn_splits

  @doc """
  Assign splits to ordered item specs. A spec with an explicit `:split`
  keeps it verbatim; the rest draw uniformly from the three drawn
  splits, seeded by `seed` and advancing only per drawn item. Returns
  the specs (in order) with `:split` filled.
  """
  @spec assign([map()], integer()) :: [map()]
  def assign(specs, seed) when is_list(specs) and is_integer(seed) do
    :rand.seed(:exsss, seed_terms(seed))

    Enum.map(specs, fn spec ->
      case spec[:split] do
        nil ->
          draw_index = :rand.uniform(length(@drawn_splits)) - 1
          Map.put(spec, :split, Enum.at(@drawn_splits, draw_index))

        explicit ->
          Map.put(spec, :split, explicit)
      end
    end)
  end

  defp seed_terms(seed), do: {seed, 0, 0}
end
