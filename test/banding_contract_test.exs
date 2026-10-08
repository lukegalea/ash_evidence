# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.BandingContractTest do
  @moduledoc """
  The assertion→banding handoff (design note §2.3), as a contract test
  against the band-table's DOCUMENTED input shape (ash_judgments'
  `Bridge.Dmn.inputs/2` evidence flattening + `Banding.Fragment`'s
  `:record` requirements — no cross-repo dependency):

  The host's banding step reads an adjudicated assertion and flattens
  it to the DMN inputs:

      <key>__p_<disposition>   decimal string per frozen disposition
                               (wrong_scope where the answer carries it)
      <key>__confidence        decimal string
      <key>__present           "true" — explicit, never an absent key
      <key>__observation_id    the ledger row this aggregate composes
      family / risk_tier / jurisdiction

  evaluates the band table (band `:admit | :review | :omit`;
  `matched_rule_ids` EMPTY IS A REFUSAL, ADR 0041), and writes the
  banding with `observation_ids` = the assertion's ledger rows.

  The stub table here encodes the documented threshold semantics —
  DEC-AUTONOMY's shadow line: a contradicting mass at ANY probability
  never auto-admits. The point under test is the SHAPE: an assertion
  as the orchestrator writes it must band without translation loss.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Assertions
  alias AshEvidence.Test.{Fixtures, HostAssertion}

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  @key "eval_synth"
  @disposition_keys ~w(supports contradicts insufficient not_applicable wrong_scope)

  test "an adjudicated assertion flattens to the band-table input contract and bands" do
    assertion = record_assertion(:supports, %{"supports" => "0.97", "insufficient" => "0.03"})

    inputs = flatten_for_banding(assertion)

    # The contract shape: every disposition's decimal-string input,
    # present, confidence, the observation pointer, the context keys.
    for disposition <- @disposition_keys do
      value = inputs["#{@key}__p_#{disposition}"]

      assert decimal_string?(value),
             "#{disposition} input must be a decimal string in 0..1, got: #{inspect(value)}"
    end

    assert inputs["#{@key}__p_supports"] == "0.97"
    assert inputs["#{@key}__p_contradicts"] == "0.0"
    assert inputs["#{@key}__present"] == "true"
    assert inputs["#{@key}__observation_id"] == hd(assertion.observation_ids)
    assert inputs["#{@key}__confidence"] == "0.95"
    assert inputs["family"] == "synthetic"
    assert inputs["risk_tier"] == "standard"
    assert inputs["jurisdiction"] == "SYNTH"

    # The band table consumes the decimal strings and bands.
    %{band: band, matched_rule_ids: rules} = band(inputs)

    assert band == :admit
    # matched_rule_ids EMPTY is a refusal, never a result (ADR 0041).
    assert "synth.auto-admit.v1" in rules

    # The banding record's documented shape, as Banding.Fragment's
    # :record would take it: the assertion's ledger rows ride along.
    banding = %{
      observation_ids: assertion.observation_ids,
      band: band,
      matched_rule_ids: rules,
      band_table: %{
        "definition_key" => "synthetic-evidence-bands",
        "definition_version" => "1",
        "content_hash" => Fixtures.hash_of("synthetic-evidence-bands"),
        "definition_id" => "synthetic-evidence-bands"
      },
      decision_evaluation_id: Ash.UUID.generate(),
      inputs: inputs,
      mode: :eval
    }

    assert banding.observation_ids == assertion.observation_ids
    assert banding.band in [:admit, :review, :omit]
  end

  test "a contradicted assertion never auto-admits — the composition invariant flows through" do
    # supports@0.97 composed WITH a credible contradicts@0.8: the
    # aggregation's fixed invariant already made the disposition
    # :contradicts (AC-3); the distribution carries both masses.
    assertion =
      record_assertion(:contradicts, %{
        "supports" => "0.485",
        "contradicts" => "0.4",
        "insufficient" => "0.115"
      })

    %{band: band} = band(flatten_for_banding(assertion))

    # DEC-AUTONOMY's shadow posture: contradicting mass at ANY
    # probability blocks the auto-admit band.
    assert band == :review
  end

  ## The host-side banding step, as the contracts describe it.

  defp flatten_for_banding(assertion) do
    probabilities =
      Map.new(@disposition_keys, fn disposition ->
        {"#{@key}__p_#{disposition}", Map.get(assertion.distribution, disposition, "0.0")}
      end)

    Map.merge(probabilities, %{
      "#{@key}__present" => "true",
      "#{@key}__observation_id" => hd(assertion.observation_ids),
      "#{@key}__confidence" => "0.95",
      "family" => "synthetic",
      "risk_tier" => "standard",
      "jurisdiction" => "SYNTH"
    })
  end

  defp band(inputs) do
    p_supports = decimal(inputs["#{@key}__p_supports"])
    p_contradicts = decimal(inputs["#{@key}__p_contradicts"])

    cond do
      # The shadow line: contradicting mass at any probability never
      # auto-admits (DEC-AUTONOMY).
      p_contradicts > 0.0 ->
        %{band: :review, matched_rule_ids: ["synth.contradiction-dominates.v1"]}

      p_supports >= 0.9 ->
        %{band: :admit, matched_rule_ids: ["synth.auto-admit.v1"]}

      true ->
        %{band: :review, matched_rule_ids: ["synth.manual-review.v1"]}
    end
  end

  ## The assertion, exactly as the orchestrator writes it (the test
  ## host's fragment record).

  defp record_assertion(disposition, distribution) do
    Ash.create!(
      HostAssertion,
      %{
        id: Ash.UUID.generate(),
        packet_id: Ash.UUID.generate(),
        evaluation_id: Ash.UUID.generate(),
        disposition: disposition,
        distribution:
          Map.merge(%{"not_applicable" => "0.0", "wrong_scope" => "0.0"}, distribution),
        aggregation_rule_version: Assertions.aggregation_rule_version(),
        observation_ids: [Ash.UUID.generate()],
        subject: Fixtures.subject("banding"),
        predicate: Fixtures.predicate(),
        subject_state_digest: Fixtures.hash_of("state"),
        question_set_hash: Fixtures.hash_of("question-set")
      },
      action: :record,
      authorize?: false
    )
  end

  defp decimal_string?(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed >= 0.0 and parsed <= 1.0
      _ -> false
    end
  end

  defp decimal_string?(_), do: false

  defp decimal(value) when is_binary(value) do
    {parsed, ""} = Float.parse(value)
    parsed
  end
end
