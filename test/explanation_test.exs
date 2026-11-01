# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.ExplanationTest do
  @moduledoc """
  The explanation data function (§2.4): recorded fields + cited atom
  content resolved at display time, never stored; unresolved ids degrade
  honestly.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Explanation
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(82)
    run = Fixtures.start_run(version)

    atoms =
      Fixtures.seed_atoms(version, run, [
        "the expiry clause with coordinates",
        "the limiting clause beside it"
      ])

    {:ok, version: version, run: run, atoms: atoms}
  end

  test "sources resolve to seq, text, kind, page and geometry at display time", %{
    version: version,
    run: run,
    atoms: [a, b]
  } do
    geometry = %{
      page_w: 612.0,
      page_h: 792.0,
      unit: :pt,
      rotation_applied: 0.0,
      bbox: %{x0: 0.1, y0: 0.2, x1: 0.3, y1: 0.4}
    }

    boxed =
      Ash.create!(
        Fixtures.atom_changeset(version, run, 3, "the boxed clause", %{
          kind: :region,
          page: 2,
          geometry: geometry
        }),
        action: :ingest,
        authorize?: false
      )

    items =
      Explanation.for_observations([
        %{
          observation_id: Ash.UUID.generate(),
          disposition: "supports",
          probability: "0.97",
          question_version: 3,
          model_digest: "sha256:" <> String.duplicate("a", 64),
          source_ids: [a.id, boxed.id, b.id]
        }
      ])

    assert [_] = items
    item = hd(items)
    assert %Explanation.Item{} = item
    assert item.disposition == "supports"
    assert item.probability == "0.97"
    assert item.question_version == 3
    assert length(item.sources) == 3
    assert item.unresolved_source_ids == []

    by_id = Map.new(item.sources, &{&1.atom_id, &1})
    assert by_id[a.id].seq == 1
    assert by_id[a.id].text == "the expiry clause with coordinates"
    assert by_id[a.id].kind == :line
    assert by_id[a.id].page == nil
    assert by_id[a.id].geometry == nil
    assert by_id[boxed.id].kind == :region
    assert by_id[boxed.id].page == 2

    assert %AshEvidence.AtomGeometry{unit: :pt, bbox: %{x0: 0.1, y0: 0.2, x1: 0.3, y1: 0.4}} =
             by_id[boxed.id].geometry

    assert by_id[b.id].seq == 2
  end

  test "unresolvable ids come back unresolved, never silently dropped", %{atoms: [a | _]} do
    dangling_uuid = Ash.UUID.generate()

    items =
      Explanation.for_observations([
        %{
          observation_id: Ash.UUID.generate(),
          disposition: "contradicts",
          probability: "0.8",
          question_version: 1,
          model_digest: nil,
          source_ids: [a.id, dangling_uuid, "not-even-a-uuid"]
        }
      ])

    item = hd(items)
    assert length(item.sources) == 1
    assert hd(item.sources).atom_id == a.id
    assert Enum.sort(item.unresolved_source_ids) == Enum.sort([dangling_uuid, "not-even-a-uuid"])
  end

  test "empty source lists resolve to empty items" do
    items = Explanation.for_observations([%{observation_id: Ash.UUID.generate(), source_ids: []}])

    assert [%Explanation.Item{sources: [], unresolved_source_ids: []}] = items
  end
end
