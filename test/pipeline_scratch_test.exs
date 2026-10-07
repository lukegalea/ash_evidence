# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.PipelineScratchTest do
  @moduledoc """
  The scratch end-to-end, mirroring the slice-0 flow with no instrument on
  the path:

      document bytes → DocumentVersion → ParseRun (:pending) →
      atoms seeded directly (the host-side seam) → ParseRun (:ok) →
      the version's atoms read back, seq-addressed.

  Offline by construction — this is slice-0's `skip_instruments` posture:
  the machinery is exercised, the instrument is not called (this package
  never calls one).
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Domain
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  test "version → run → atoms → closed run, read back through the domain" do
    # 1. The document version: bytes in, content hash pinned, no update
    #    action to mutate it later.
    version = Fixtures.ingest_document(7)
    assert version.sha256 == Fixtures.sha256(Fixtures.document_bytes(7))

    # 2. The parse run: started before any instrument work, pending.
    run = Fixtures.start_run(version, instrument: "synthetic-ocr-pass")
    assert run.status == :pending

    # 3. The host's OCR/LLM pass would happen HERE, outside the package.
    #    Its output lands as addressed atoms — seeded directly (the seam).
    lines = [
      "SYNTHETIC DOCUMENT",
      "SERIAL: SYNTH-DOC-7",
      "DATE: 2026-10-07"
    ]

    atoms = Fixtures.seed_atoms(version, run, lines)
    assert length(atoms) == 3

    # 4. The pass closed ok — once. Re-closing is refused.
    run = Domain.mark_parse_run_ok!(run)

    assert {:error, %Ash.Error.Invalid{}} =
             AshEvidence.ParseRun
             |> Ash.get!(run.id, authorize?: false)
             |> then(&Ash.update(&1, %{}, action: :mark_ok, authorize?: false))

    # 5. The version's atoms read back in address order; the run's view
    #    agrees. Ids are the packet currency — the text stays in the store.
    by_version = Domain.atoms_for_version!(version.id)
    assert Enum.map(by_version, & &1.text) == lines
    assert Enum.map(by_version, & &1.seq) == [1, 2, 3]

    assert by_version |> Enum.map(& &1.id) ==
             run.id |> Domain.atoms_for_run!() |> Enum.map(& &1.id)

    # 6. A failed pass over the same version is a separate, honest record.
    failed = Fixtures.start_run(version, instrument: "synthetic-extraction-pass")
    Domain.mark_parse_run_failed!(failed)

    assert %{status: :failed} = Ash.get!(AshEvidence.ParseRun, failed.id, authorize?: false)
    assert %{status: :ok} = Ash.get!(AshEvidence.ParseRun, run.id, authorize?: false)
  end
end
