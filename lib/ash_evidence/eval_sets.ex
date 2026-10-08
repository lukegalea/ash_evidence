# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSets do
  @moduledoc """
  The eval-set surface: versioned, split-drawn, CC0-dedicable eval sets
  over document-version corpora — the measurement substrate for the
  retrieval and adjudication seams (the eval-sets landing discipline).

  The flow:

      set =
        AshEvidence.Domain.open_eval_set!(
          "synthetic-retrieval",
          1,
          "the AC-4 false-supports substrate",
          1515,
          %{algorithm: "ash_evidence/eval_sets/draw 1", splits: 3}
        )

      specs
      |> AshEvidence.EvalSets.draw_and_add_items!(set)
      |> AshEvidence.Domain.publish_eval_set!()

  `draw_and_add_items!/2` runs the split draw (`AshEvidence.EvalSets.Draw`)
  from the set's recorded seed — explicit `:audit` splits honoured
  verbatim, never drawn — and adds the items in order (ordinals continue
  any existing ones). Publishing freezes the set: no items, no moves, no
  relabels — a correction is version+1.
  """

  @moduledoc since: "0.1.0"

  alias AshEvidence.Domain
  alias AshEvidence.EvalSets.Draw

  @doc """
  Run the split draw over the ordered specs and add them as items of
  `set` (which must be `:open`). Each spec is a map with
  `:document_version_id`, `:claim`, `:gold_atom_ids`,
  `:expected_disposition`, `:expected_hypothesis`, `:source`,
  `:license` and optionally `:split` (explicit — honoured verbatim,
  e.g. `:audit`). Ordinals continue from the set's existing items.

  The draw is deterministic in the set's `split_seed` and the spec
  order: re-adding the same specs to an identically-seeded set yields
  the same assignment (and a fresh set yields a duplicate set under a
  new version).
  """
  @spec draw_and_add_items!([map()], AshEvidence.EvalSet.t()) :: [AshEvidence.EvalItem.t()]
  def draw_and_add_items!(specs, %AshEvidence.EvalSet{} = set) when is_list(specs) do
    drawn = Draw.assign(specs, set.split_seed)
    base = set.id |> Domain.items_for_set!() |> length()

    drawn
    |> Enum.with_index(1 + base)
    |> Enum.map(fn {spec, ordinal} ->
      Domain.add_eval_item!(%{
        eval_set_id: set.id,
        document_version_id: Map.fetch!(spec, :document_version_id),
        ordinal: ordinal,
        claim: Map.fetch!(spec, :claim),
        gold_atom_ids: Map.get(spec, :gold_atom_ids, []),
        expected_disposition: Map.fetch!(spec, :expected_disposition),
        expected_hypothesis: Map.get(spec, :expected_hypothesis),
        source: Map.fetch!(spec, :source),
        license: Map.get(spec, :license, "CC0-1.0"),
        split: Map.fetch!(spec, :split)
      })
    end)
  end
end
