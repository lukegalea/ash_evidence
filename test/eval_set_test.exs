# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSetTest do
  @moduledoc """
  The eval-set contract: versioned and immutable (items never move,
  a published set is frozen, a correction is a new version), the draw
  recorded on the set and reconstructible from its seed, audit rows
  honoured verbatim and never drawn.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Domain
  alias AshEvidence.EvalSets.Draw
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(90)
    {:ok, version: version}
  end

  defp open_set(name \\ "synthetic-retrieval", seed \\ 1515) do
    Domain.open_eval_set!(
      name,
      1,
      "the AC-4 substrate",
      seed,
      %{"algorithm" => "ash_evidence/eval_sets/draw 1", "splits" => 3}
    )
  end

  defp item_spec(version, ordinal, overrides \\ %{}) do
    Map.merge(
      %{
        document_version_id: version.id,
        claim: "the equipment maintenance coverage period is 12 months",
        gold_atom_ids: [],
        expected_disposition: :supports,
        expected_hypothesis: :supports,
        source: "test",
        license: "CC0-1.0"
      },
      Map.put(overrides, :ordinal, ordinal)
    )
  end

  test "a set opens, accepts drawn items, publishes once, then freezes", %{version: version} do
    set = open_set()
    assert set.status == :open
    assert is_nil(set.published_at)

    items =
      AshEvidence.EvalSets.draw_and_add_items!(
        [item_spec(version, 1), item_spec(version, 2, %{split: :audit}), item_spec(version, 3)],
        set
      )

    assert Enum.map(items, & &1.ordinal) == [1, 2, 3]

    # The explicit audit split is honoured verbatim; the others drew.
    assert Enum.at(items, 1).split == :audit
    assert Enum.at(items, 0).split in Draw.drawn_splits()
    assert Enum.at(items, 2).split in Draw.drawn_splits()

    set = Domain.publish_eval_set!(set)
    assert set.status == :published
    assert %DateTime{} = set.published_at

    # Publishing is terminal.
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(set, %{}, action: :publish, authorize?: false)

    # And the set is frozen: no items after publish.
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               AshEvidence.EvalItem,
               Map.put(item_spec(version, 4), :eval_set_id, set.id),
               action: :add,
               authorize?: false
             )
  end

  test "a correction is a new version; the old set stands untouched", %{version: version} do
    v1 = open_set("retrieval-eval", 42)
    AshEvidence.EvalSets.draw_and_add_items!([item_spec(version, 1)], v1)
    Domain.publish_eval_set!(v1)

    v2 = Domain.open_eval_set!("retrieval-eval", 2, "the re-split", 42, %{})
    AshEvidence.EvalSets.draw_and_add_items!([item_spec(version, 1), item_spec(version, 2)], v2)

    assert length(Domain.items_for_set!(v1.id)) == 1
    assert length(Domain.items_for_set!(v2.id)) == 2
    assert Domain.get_eval_set_by_name_version!("retrieval-eval", 1).id == v1.id
    assert Domain.get_eval_set_by_name_version!("retrieval-eval", 2).id == v2.id

    # The identity is the pair: a third version-2 is a conflict.
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               AshEvidence.EvalSet,
               %{name: "retrieval-eval", version: 2, split_seed: 1},
               action: :open,
               authorize?: false
             )
  end

  test "items never move: there is no update action to move one with", %{version: version} do
    set = open_set()
    [item] = AshEvidence.EvalSets.draw_and_add_items!([item_spec(version, 1)], set)
    original_split = item.split

    # Structural: the resource defines no update action at all — a move
    # is not expressible, exactly as the discipline demands.
    assert_raise ArgumentError, ~r/No such update action/, fn ->
      Ash.update(item, %{split: :test}, action: :update, authorize?: false)
    end

    assert %{split: ^original_split} = Domain.get_eval_item!(item.id)
  end

  test "the draw is recorded on the set and reconstructible from the seed", %{version: version} do
    set = open_set("retrieval-eval", 2026)

    specs = for i <- 1..20, do: item_spec(version, i)
    items = AshEvidence.EvalSets.draw_and_add_items!(specs, set)

    # The recorded seed reproduces the assignment, standalone.
    replayed = Draw.assign(specs, set.split_seed)

    assert Enum.map(items, & &1.split) == Enum.map(replayed, & &1.split)
    assert set.split_seed == 2026
    assert set.split_provenance["algorithm"] == "ash_evidence/eval_sets/draw 1"
  end

  test "drawn splits never include audit, and every item lands somewhere" do
    specs = for i <- 1..300, do: %{claim: "c#{i}"}
    assigned = Draw.assign(specs, 7)

    assert length(assigned) == 300
    assert Enum.all?(assigned, &(&1.split in Draw.drawn_splits()))
    assert Enum.uniq(Enum.map(assigned, & &1.split)) |> length() == 3
  end

  test "explicit splits are honoured verbatim and do not advance the draw" do
    specs = [
      %{claim: "a", split: :audit},
      %{claim: "b"},
      %{claim: "c", split: :calibration},
      %{claim: "d"},
      %{claim: "e", split: :audit}
    ]

    first_run = Draw.assign(specs, 99)
    assert [:audit, s1, :calibration, s2, :audit] = Enum.map(first_run, & &1.split)

    # The two drawn items' assignment is independent of the explicit
    # rows around them (explicit rows never advance the draw): the same
    # seed over just the drawn specs reproduces their splits.
    only_drawn = Draw.assign([%{claim: "b"}, %{claim: "d"}], 99)
    assert Enum.map(only_drawn, & &1.split) == [s1, s2]
  end
end
