# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.RetrievalContractTest do
  @moduledoc """
  The retrieval seam's input contract, without a database: deterministic
  framing queries, the shape of the caller's options, and the errors a
  misuse gets. These run even under `SKIP_DB=1`.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Retrieval

  describe "framing_queries/3" do
    test "defaults are deterministic: supports is the claim, verbatim" do
      queries = Retrieval.framing_queries("the premium is due", [:supports])
      assert queries == %{supports: "the premium is due"}
    end

    test "default contrast framings AND the claim with fixed cues" do
      queries = Retrieval.framing_queries("the premium is due", [:contradicts, :exception])

      assert queries.contradicts == "the premium is due never without"
      assert queries.exception == "the premium is due except unless"
    end

    test "the same claim produces the same queries, every time" do
      a = Retrieval.framing_queries("a claim", [:supports, :contradicts, :exception])
      b = Retrieval.framing_queries("a claim", [:supports, :contradicts, :exception])
      assert a == b
    end

    test "overrides are used verbatim — the model-written counter-hypothesis seam" do
      queries =
        Retrieval.framing_queries("a claim", [:supports, :contradicts],
          contradicts: "the opposite of a claim, phrased properly"
        )

      assert queries.contradicts == "the opposite of a claim, phrased properly"
      assert queries.supports == "a claim"
    end

    test "a non-string override is rejected" do
      assert_raise ArgumentError, ~r/must be a string/, fn ->
        Retrieval.framing_queries("a claim", [:supports], supports: 42)
      end
    end

    test "a non-string claim is rejected" do
      assert_raise ArgumentError, ~r/claim must be a string/, fn ->
        Retrieval.framing_queries(42, [:supports])
      end
    end
  end

  describe "retrieve/3 input validation (no database touched)" do
    @version_id "b28f2c1e-0000-4000-8000-000000000001"

    test "unknown hypotheses are rejected" do
      assert_raise ArgumentError, ~r/non-empty subset/, fn ->
        AshEvidence.retrieve!(@version_id, "a claim", hypotheses: [:supports, :refutes])
      end
    end

    test "an empty hypothesis list is rejected" do
      assert_raise ArgumentError, ~r/non-empty subset/, fn ->
        AshEvidence.retrieve!(@version_id, "a claim", hypotheses: [])
      end
    end

    test "a non-positive k is rejected" do
      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        AshEvidence.retrieve!(@version_id, "a claim", k: 0)
      end
    end

    test "a malformed vector is rejected" do
      assert_raise ArgumentError, ~r/vector must be a list of numbers/, fn ->
        AshEvidence.retrieve!(@version_id, "a claim", vector: 3)
      end
    end

    test "a vector for an unrequested framing is rejected" do
      assert_raise ArgumentError, ~r/not among the requested hypotheses/, fn ->
        AshEvidence.retrieve!(@version_id, "a claim", vector: [exception: [1.0, 0.0]])
      end
    end

    test "a malformed version reference is rejected" do
      assert_raise ArgumentError, ~r/not a document version/, fn ->
        AshEvidence.retrieve!("not-a-uuid", "a claim")
      end
    end
  end

  describe "framings/0" do
    test "the known framings, in contract order" do
      assert Retrieval.framings() == [:supports, :contradicts, :exception]
    end
  end
end
