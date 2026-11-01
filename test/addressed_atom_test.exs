# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AddressedAtomTest do
  @moduledoc """
  The AddressedAtom contract: seq-addressed within its version, produced
  by a run, of a declared kind, citing other atoms by id, on a page with
  normalised geometry when the instrument measured one.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.{AddressedAtom, AtomGeometry, Domain}
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  require Ash.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(1)
    run = Fixtures.start_run(version)
    {:ok, version: version, run: run}
  end

  test "an atom is addressed by seq within its version", %{version: version, run: run} do
    atom = Fixtures.seed_atoms(version, run, ["first", "second"]) |> hd()

    assert atom.seq == 1
    assert atom.document_version_id == version.id
    assert atom.parse_run_id == run.id
    assert atom.source_ids == []
    assert atom.kind == :line
    assert is_nil(atom.page)
    assert is_nil(atom.geometry)
    assert %DateTime{} = atom.created_at
  end

  test "seq is unique per version", %{version: version, run: run} do
    Fixtures.seed_atoms(version, run, ["one"])

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               AddressedAtom,
               %{
                 document_version_id: version.id,
                 parse_run_id: run.id,
                 seq: 1,
                 text: "again",
                 kind: :line
               },
               action: :ingest,
               authorize?: false
             )
  end

  test "the same seq is fine on a different version" do
    v1 = Fixtures.ingest_document(2)
    v2 = Fixtures.ingest_document(3)
    r1 = Fixtures.start_run(v1)
    r2 = Fixtures.start_run(v2)

    Fixtures.seed_atoms(v1, r1, ["shared seq"])
    Fixtures.seed_atoms(v2, r2, ["shared seq"])

    assert length(Domain.atoms_for_version!(v1.id)) == 1
    assert length(Domain.atoms_for_version!(v2.id)) == 1
  end

  test "for_version reads a version's atoms in seq order, not insertion order",
       %{version: version, run: run} do
    # Insert deliberately out of seq order.
    Ash.create!(Fixtures.atom_changeset(version, run, 3, "gamma"),
      action: :ingest,
      authorize?: false
    )

    Ash.create!(Fixtures.atom_changeset(version, run, 1, "alpha"),
      action: :ingest,
      authorize?: false
    )

    Ash.create!(Fixtures.atom_changeset(version, run, 2, "beta"),
      action: :ingest,
      authorize?: false
    )

    assert ["alpha", "beta", "gamma"] ==
             version.id |> Domain.atoms_for_version!() |> Enum.map(& &1.text)
  end

  test "for_run reads one run's atoms", %{version: version, run: run} do
    Fixtures.seed_atoms(version, run, ["a", "b"])

    # A second run over the same version continues the version's address
    # space (seq is unique per VERSION, not per run).
    other_run = Fixtures.start_run(version)

    Ash.create!(Fixtures.atom_changeset(version, other_run, 10, "c"),
      action: :ingest,
      authorize?: false
    )

    assert length(Domain.atoms_for_run!(run.id)) == 2
    assert [%{text: "c"}] = Domain.atoms_for_run!(other_run.id)
  end

  test "source_ids cite other atoms of the version", %{version: version, run: run} do
    [ocr_a, ocr_b] = Fixtures.seed_atoms(version, run, ["policy no", "2026-05-28"])

    derived =
      Ash.create!(
        AddressedAtom,
        %{
          document_version_id: version.id,
          parse_run_id: run.id,
          seq: 3,
          text: "expiry: 2026-05-28",
          kind: :region,
          source_ids: [ocr_a.id, ocr_b.id]
        },
        action: :ingest,
        authorize?: false
      )

    assert derived.source_ids == [ocr_a.id, ocr_b.id]
  end

  describe "kind" do
    test "round-trips each layout unit", %{version: version, run: run} do
      for {kind, seq} <- Enum.with_index([:word, :line, :cell, :region], 1) do
        atom = ingest!(version, run, %{seq: seq, kind: kind})
        assert Ash.get!(AddressedAtom, atom.id, authorize?: false).kind == kind
      end
    end

    test "is required", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{}} = ingest(version, run, %{kind: nil})
    end

    test "outside the enum is refused", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{}} = ingest(version, run, %{kind: :paragraph})
    end
  end

  describe "page" do
    test "round-trips", %{version: version, run: run} do
      atom = ingest!(version, run, %{page: 3})
      assert Ash.get!(AddressedAtom, atom.id, authorize?: false).page == 3
    end

    test "is 1-based", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{}} = ingest(version, run, %{page: 0})
    end

    test "is required once the atom has geometry", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               ingest(version, run, %{geometry: geometry()})

      assert Exception.message(error) =~ "an atom with geometry must name its page"
    end
  end

  describe "geometry" do
    test "round-trips as the typed value", %{version: version, run: run} do
      atom =
        ingest!(version, run, %{
          page: 2,
          geometry: geometry(%{unit: :px, rotation_applied: 90.0})
        })

      stored = Ash.get!(AddressedAtom, atom.id, authorize?: false)

      assert %AtomGeometry{
               page_w: 612.0,
               page_h: 792.0,
               unit: :px,
               rotation_applied: 90.0,
               bbox: %{x0: 0.1, y0: 0.2, x1: 0.5, y1: 0.25}
             } = stored.geometry
    end

    test "accepts a box on the page's edges", %{version: version, run: run} do
      box = %{x0: 0.0, y0: 0.0, x1: 1.0, y1: 1.0}
      atom = ingest!(version, run, %{page: 1, geometry: geometry(%{bbox: box})})
      assert atom.geometry.bbox == box
    end

    test "accepts a zero-area box", %{version: version, run: run} do
      box = %{x0: 0.4, y0: 0.4, x1: 0.4, y1: 0.4}
      assert {:ok, _} = ingest(version, run, %{page: 1, geometry: geometry(%{bbox: box})})
    end

    for {name, box, reason} <- [
          {"a coordinate below 0", %{x0: -0.01, y0: 0.2, x1: 0.5, y1: 0.25}, "x0"},
          {"a coordinate above 1", %{x0: 0.1, y0: 0.2, x1: 0.5, y1: 1.01}, "y1"},
          {"x0 past x1", %{x0: 0.6, y0: 0.2, x1: 0.5, y1: 0.25}, "x0 must not exceed x1"},
          {"y0 past y1", %{x0: 0.1, y0: 0.3, x1: 0.5, y1: 0.25}, "y0 must not exceed y1"},
          {"the old y2 key", %{x0: 0.1, y0: 0.2, x1: 0.5, y2: 0.25}, "y1"}
        ] do
      test "refuses #{name}", %{version: version, run: run} do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 ingest(version, run, %{
                   page: 1,
                   geometry: geometry(%{bbox: unquote(Macro.escape(box))})
                 })

        assert Exception.message(error) =~ unquote(reason)
      end
    end

    test "refuses a unit other than pt or px", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{}} =
               ingest(version, run, %{page: 1, geometry: geometry(%{unit: :mm})})
    end

    test "refuses a non-positive page size", %{version: version, run: run} do
      assert {:error, %Ash.Error.Invalid{}} =
               ingest(version, run, %{page: 1, geometry: geometry(%{page_w: 0.0})})
    end
  end

  test "a line atom resolves to its words through source_ids", %{version: version, run: run} do
    words =
      for {text, seq} <- Enum.with_index(["net", "thirty", "days"], 1) do
        ingest!(version, run, %{seq: seq, text: text, kind: :word, page: 1})
      end

    line =
      ingest!(version, run, %{
        seq: 4,
        text: "net thirty days",
        kind: :line,
        page: 1,
        source_ids: Enum.map(words, & &1.id)
      })

    resolved =
      AddressedAtom
      |> Ash.Query.filter(id in ^line.source_ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, &1})

    assert Enum.map(line.source_ids, &resolved[&1].text) == ["net", "thirty", "days"]
    assert Enum.all?(Map.values(resolved), &(&1.kind == :word))
  end

  defp geometry(overrides \\ %{}) do
    Map.merge(
      %{
        page_w: 612.0,
        page_h: 792.0,
        unit: :pt,
        rotation_applied: 0.0,
        bbox: %{x0: 0.1, y0: 0.2, x1: 0.5, y1: 0.25}
      },
      overrides
    )
  end

  defp ingest(version, run, attrs),
    do:
      Ash.create(AddressedAtom, atom_input(version, run, attrs),
        action: :ingest,
        authorize?: false
      )

  defp ingest!(version, run, attrs),
    do:
      Ash.create!(AddressedAtom, atom_input(version, run, attrs),
        action: :ingest,
        authorize?: false
      )

  defp atom_input(version, run, attrs) do
    Map.merge(
      %{
        document_version_id: version.id,
        parse_run_id: run.id,
        seq: 1,
        text: "a span",
        kind: :word
      },
      attrs
    )
  end
end
