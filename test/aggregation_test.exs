# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Assertions.AggregationTest do
  @moduledoc """
  The aggregation rule's contract (§2.6): versioned, deterministic,
  contradiction-dominates as a FIXED invariant, wrong_scope as the fifth
  disposition, marginals composed as marginals. Pure — no database.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Assertions.Aggregation
  alias AshEvidence.Test.Fixtures

  describe "the version constant" do
    test "the rule is versioned, and the version rides every aggregate" do
      assert Aggregation.version() == "1"

      {:ok, aggregate} =
        Aggregation.aggregate([Fixtures.observation(:supports, %{"supports" => 0.9})])

      assert aggregate.rule_version == Aggregation.version()
      assert aggregate.rule_version == AshEvidence.Assertions.aggregation_rule_version()
    end
  end

  describe "AC-3 — contradiction dominates (fixed invariant)" do
    test "supports@0.97 plus a credible contradicts@0.8 is NOT supports" do
      observations = [
        Fixtures.observation(:supports, %{"supports" => 0.97, "insufficient" => 0.03}),
        Fixtures.observation(:contradicts, %{"contradicts" => 0.8, "insufficient" => 0.2})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)

      # The composed masses still say supports 0.485 vs contradicts 0.4 —
      # the argmax WOULD be supports. The invariant overrides the argmax.
      assert aggregate.distribution["supports"] == "0.485"
      assert aggregate.distribution["contradicts"] == "0.4"
      assert aggregate.disposition == :contradicts
      refute aggregate.disposition == :supports
    end

    test "the bound itself dominates: contradicts at exactly one half" do
      observations = [
        Fixtures.observation(:supports, %{"supports" => 0.9}),
        Fixtures.observation(:contradicts, %{"contradicts" => 0.5})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)
      assert aggregate.disposition == :contradicts
    end

    test "a NON-credible contradiction does not dominate — argmax rules" do
      observations = [
        Fixtures.observation(:supports, %{"supports" => 0.9, "insufficient" => 0.1}),
        Fixtures.observation(:contradicts, %{"contradicts" => 0.3, "insufficient" => 0.7})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)

      assert aggregate.distribution["supports"] == "0.45"
      assert aggregate.disposition == :supports
    end
  end

  describe "the wrong_scope arm" do
    test "wrong_scope flows through as the fifth disposition" do
      observations = [
        Fixtures.observation("wrong_scope", %{"wrong_scope" => 0.9, "insufficient" => 0.1}),
        Fixtures.observation(:insufficient, %{"insufficient" => 0.4})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)

      assert aggregate.disposition == :wrong_scope
      assert aggregate.distribution["wrong_scope"] == "0.45"
      assert aggregate.distribution["insufficient"] == "0.25"
    end

    test "an undeclared wrong_scope is an explicit zero mass, never missing" do
      {:ok, aggregate} =
        Aggregation.aggregate([Fixtures.observation(:supports, %{"supports" => 1.0})])

      assert aggregate.distribution["wrong_scope"] == "0.0"

      assert MapSet.new(Map.keys(aggregate.distribution)) ==
               MapSet.new(Enum.map(Aggregation.dispositions(), &Atom.to_string/1))
    end
  end

  describe "marginals composed as marginals (C15)" do
    test "the composed mass is the MEAN, never a product of pseudo-joints" do
      observations = [
        Fixtures.observation(:supports, %{"supports" => 0.6}),
        Fixtures.observation(:supports, %{"supports" => 0.6})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)

      # A naive independence product would say 0.36.
      assert aggregate.distribution["supports"] == "0.6"
      assert aggregate.disposition == :supports
    end
  end

  describe "determinism and the pick" do
    test "identical observations aggregate identically" do
      observations = [
        Fixtures.observation(:supports, %{"supports" => 0.6, "insufficient" => 0.4}),
        Fixtures.observation(:insufficient, %{"insufficient" => 0.5, "supports" => 0.5})
      ]

      {:ok, a} = Aggregation.aggregate(observations)
      {:ok, b} = Aggregation.aggregate(observations)
      assert a == b
    end

    test "a full tie breaks in the frozen vocabulary's order" do
      observations = [
        Fixtures.observation(:insufficient, %{}),
        Fixtures.observation(:not_applicable, %{})
      ]

      {:ok, aggregate} = Aggregation.aggregate(observations)
      assert aggregate.disposition == :supports
    end

    test "string values cast against the frozen vocabulary" do
      {:ok, aggregate} =
        Aggregation.aggregate([Fixtures.observation("contradicts", %{"contradicts" => 1.0})])

      assert aggregate.disposition == :contradicts
    end
  end

  describe "reject, never repair" do
    test "no observations is an error, never an empty aggregate" do
      assert {:error, :no_observations} = Aggregation.aggregate([])
    end

    test "a value outside the frozen vocabulary rejects" do
      assert {:error, {:bad_value, _, _}} =
               Aggregation.aggregate([Fixtures.observation(:refutes, %{})])
    end

    test "a probability key outside the frozen vocabulary rejects" do
      assert {:error, {:bad_probability_key, "not_a_disposition"}} =
               Aggregation.aggregate([
                 Fixtures.observation(:supports, %{"not_a_disposition" => 0.5})
               ])
    end

    test "a mass outside the unit interval rejects" do
      assert {:error, {:bad_probability, "supports", 1.5}} =
               Aggregation.aggregate([Fixtures.observation(:supports, %{"supports" => 1.5})])
    end
  end
end
