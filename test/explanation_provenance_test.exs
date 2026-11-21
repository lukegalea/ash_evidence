# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.ExplanationProvenanceTest do
  @moduledoc """
  The atoms an observation cited, as `ash_provenance` steps and gaps: resolved atoms are steps, and every id that does
  not resolve is a typed gap, never a silent drop. No atom text reaches the output.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Explanation
  alias AshEvidence.Test.Fixtures
  alias AshProvenance.{Address, Gap, Step}

  @moduletag :db

  @base "https://example.test/ae"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(91)
    run = Fixtures.start_run(version)
    atoms = Fixtures.seed_atoms(version, run, ["secret clause one", "secret clause two"])

    derived = Address.new!(base: @base, type: "observation", id: Ash.UUID.generate())
    {:ok, version: version, atoms: atoms, derived: derived}
  end

  test "a resolved atom is a was_derived_from step to the atom's address", %{
    atoms: [a, b],
    derived: derived
  } do
    %{steps: steps, gaps: gaps} = Explanation.provenance(derived, [a.id, b.id])

    assert gaps == []
    assert [%Step{relation: :was_derived_from} = first, %Step{}] = steps
    assert first.entity == derived
    assert first.antecedent == Address.new!(base: @base, type: "addressed_atom", id: a.id)
    assert first.granularity == :record
    assert %DateTime{} = first.at
  end

  test "no atom text reaches the output", %{atoms: [a, b], derived: derived} do
    out = Explanation.provenance(derived, [a.id, b.id, Ash.UUID.generate()])

    refute inspect(out) =~ "secret clause"
  end

  test "a repeated id is one step", %{atoms: [a, _], derived: derived} do
    assert %{steps: [_], gaps: []} = Explanation.provenance(derived, [a.id, a.id])
  end

  describe "an id that does not resolve" do
    test "is an erased gap, listed by id, when the row is gone", %{
      atoms: [a, b],
      derived: derived
    } do
      Ash.destroy!(b, authorize?: false)

      %{steps: steps, gaps: gaps} = Explanation.provenance(derived, [a.id, b.id])

      assert [%Step{relation: :was_derived_from}] = steps
      assert [%Gap{kind: :erased, of: ^derived, receipt: nil} = gap] = gaps
      assert gap.summary =~ b.id
    end

    test "carries the erasure receipt as the gap's receipt and a was_invalidated_by step", %{
      atoms: [a, _],
      derived: derived
    } do
      Ash.destroy!(a, authorize?: false)
      receipt = "shred_receipt:" <> Ash.UUID.generate()

      %{steps: [step], gaps: [gap]} =
        Explanation.provenance(derived, [a.id], receipts: %{a.id => receipt})

      assert %Step{relation: :was_invalidated_by, activity: ^receipt} = step
      assert step.entity == Address.new!(base: @base, type: "addressed_atom", id: a.id)
      assert %Gap{kind: :erased, receipt: ^receipt} = gap
    end

    test "is unreadable, with nothing else, when it still exists for the existence read", %{
      atoms: [a, _],
      derived: derived
    } do
      %{steps: [], gaps: [gap]} =
        Explanation.provenance(derived, [a.id], tenant: "another-tenant", existence_opts: [])

      assert gap == Gap.new!(kind: :unreadable, of: derived)
    end

    test "is erased, not unreadable, when no existence read is given", %{
      atoms: [a, _],
      derived: derived
    } do
      %{gaps: [%Gap{kind: :erased}]} =
        Explanation.provenance(derived, [a.id], tenant: "another-tenant")
    end

    test "that is not a UUID never named an atom: not_recorded", %{derived: derived} do
      assert %{steps: [], gaps: [%Gap{kind: :not_recorded, of: ^derived}]} =
               Explanation.provenance(derived, ["not-a-uuid"])
    end
  end

  test "no cited atoms is an empty answer", %{derived: derived} do
    assert %{steps: [], gaps: []} = Explanation.provenance(derived, [])
  end
end
