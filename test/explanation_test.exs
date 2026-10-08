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

  test "sources resolve to seq, text and bbox at display time", %{
    version: version,
    run: run,
    atoms: [a, b]
  } do
    bbox = %{x0: 1.0, y0: 2.0, x1: 3.0, y2: 4.0}

    boxed =
      Ash.create!(
        Fixtures.atom_changeset(version, run, 3, "the boxed clause", %{bbox: bbox}),
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
    assert by_id[a.id].bbox == nil
    assert by_id[boxed.id].bbox == bbox
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
