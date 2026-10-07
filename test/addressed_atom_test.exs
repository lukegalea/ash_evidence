# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AddressedAtomTest do
  @moduledoc """
  The AddressedAtom contract: seq-addressed within its version, produced
  by a run, citing other atoms by id, bbox when the instrument saw one.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.{AddressedAtom, Domain}
  alias AshEvidence.Test.Fixtures

  @moduletag :db

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
    assert is_nil(atom.bbox)
    assert %DateTime{} = atom.created_at
  end

  test "seq is unique per version", %{version: version, run: run} do
    Fixtures.seed_atoms(version, run, ["one"])

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               AddressedAtom,
               %{document_version_id: version.id, parse_run_id: run.id, seq: 1, text: "again"},
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
          source_ids: [ocr_a.id, ocr_b.id]
        },
        action: :ingest,
        authorize?: false
      )

    assert derived.source_ids == [ocr_a.id, ocr_b.id]
  end

  test "bbox is stored as the declared geometry map", %{version: version, run: run} do
    bbox = %{x0: 10.0, y0: 20.0, x1: 210.5, y2: 40.25}

    atom =
      Ash.create!(
        AddressedAtom,
        %{
          document_version_id: version.id,
          parse_run_id: run.id,
          seq: 1,
          text: "boxed span",
          bbox: bbox
        },
        action: :ingest,
        authorize?: false
      )

    assert atom.bbox == bbox
  end
end
