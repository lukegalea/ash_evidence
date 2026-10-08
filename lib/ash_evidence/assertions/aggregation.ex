# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Assertions.Aggregation do
  @moduledoc """
  The versioned composition rule: per-candidate evidence distributions
  in, one assertion-shaped aggregate out.

  **Mechanism in code, versioned; thresholds stay in DMN.** This module
  composes; it never decides thresholds — bands are earned elsewhere.
  The version constant rides every assertion
  (`aggregation_rule_version`): recalibrating the rule is a new version
  and re-earns everything downstream (the question-lineage discipline).
  Version 1 is deliberately crude; the version constant is what makes
  that safe to admit.

  ## Version 1

    * **Marginals composed as marginals** (the C15 discipline): the
      composed distribution is the mixture MEAN of the constituent
      observation distributions — `mass(d) = Σᵢ pᵢ(d) / n`. The
      observations are answers about DIFFERENT candidate atoms over the
      same predicate; they are not independent samples of one joint, so
      nothing is ever multiplied as if it were.
    * **Contradiction dominates — a fixed invariant, not a knob.** If
      any constituent observation records a contradicts mass of one
      half or more, the aggregate disposition is `:contradicts` — never
      `:supports`, whatever the composed masses say. Retrieval that
      only looks for support manufactures false supports; composition
      that averaged a credible contradiction away would finish the job.
      (The shadow posture's line: `contradicts` never auto-admits a
      failing fact, at any probability.)
    * Otherwise the disposition is the composed argmax, ties broken in
      the frozen vocabulary's order — deterministic.
    * `:wrong_scope` flows through as the fifth disposition exactly
      like the others: present where a question declared it, absent
      (as a `"0"` mass) otherwise.
    * **The distribution travels as decimal strings** (§4.3) — the DMN
      bridge reads decimals, and floats never cross a record boundary.

  Inputs are the per-observation evidence outcomes as recorded on the
  ledger: `%{value: atom_or_string, probabilities: %{disposition_string
  => number in 0..1}}`. Anything outside the frozen vocabulary or the
  unit interval REJECTS — the rule composes recorded evidence, it does
  not repair broken replies.
  """

  @rule_version "1"

  # The frozen vocabulary, in tie-break order — the aggregate value
  # lives in the same vocabulary as the observations it composes.
  @dispositions [:supports, :contradicts, :insufficient, :not_applicable, :wrong_scope]

  # The fixed dominance bound: a contradicts mass at or above one half
  # on any constituent observation dominates the aggregate. Not
  # configurable — a configurable dominance is a threshold, and
  # thresholds stay in DMN.
  @dominance_bound 0.5

  @typedoc "One recorded evidence outcome, as the ledger holds it"
  @type observation :: %{
          required(:value) => atom() | String.t(),
          required(:probabilities) => %{String.t() => number()}
        }

  @typedoc "The composed aggregate the assertion records"
  @type aggregate :: %{
          disposition: atom(),
          distribution: %{String.t() => String.t()},
          rule_version: String.t()
        }

  @doc "The rule version this module composes with."
  @spec version() :: String.t()
  def version, do: @rule_version

  @doc "The frozen disposition vocabulary, in tie-break order."
  @spec dispositions() :: [atom()]
  def dispositions, do: @dispositions

  @doc """
  Compose the constituent evidence observations into the aggregate the
  assertion records: disposition, distribution (decimal strings over
  the full frozen vocabulary), and the rule version that composed them.
  """
  @spec aggregate([observation()]) :: {:ok, aggregate()} | {:error, term()}
  def aggregate([]), do: {:error, :no_observations}

  def aggregate(observations) when is_list(observations) do
    with {:ok, cast} <- cast_observations(observations) do
      masses = compose(cast)

      distribution =
        Map.new(masses, fn {disposition, mass} ->
          {Atom.to_string(disposition), decimal_string(mass)}
        end)

      {:ok,
       %{
         disposition: disposition(cast, masses),
         distribution: distribution,
         rule_version: @rule_version
       }}
    end
  end

  def aggregate(other), do: {:error, {:not_a_list, other}}

  ## Casting — reject, never repair

  defp cast_observations(observations) do
    Enum.reduce_while(observations, {:ok, []}, fn observation, {:ok, acc} ->
      case cast_observation(observation) do
        {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, cast} -> {:ok, Enum.reverse(cast)}
      error -> error
    end
  end

  defp cast_observation(%{} = observation) do
    with {:ok, value} <- cast_value(observation[:value]),
         {:ok, probabilities} <- cast_probabilities(observation[:probabilities]) do
      {:ok, %{value: value, probabilities: probabilities}}
    end
  end

  defp cast_observation(other), do: {:error, {:bad_observation, other}}

  defp cast_value(value) when is_atom(value) and value in @dispositions, do: {:ok, value}
  defp cast_value(value) when is_binary(value), do: cast_value(disposition_atom(value))

  defp cast_value(value) do
    {:error,
     {:bad_value, value,
      "the value must be one of the frozen dispositions #{inspect(@dispositions)}"}}
  end

  defp disposition_atom(string) do
    # Fixed allow-list — no atom is created from caller input.
    Enum.find(@dispositions, fn disposition -> Atom.to_string(disposition) == string end)
  end

  defp cast_probabilities(probabilities) when is_map(probabilities) do
    Enum.reduce_while(probabilities, {:ok, %{}}, &cast_probability/2)
  end

  defp cast_probabilities(probabilities) do
    {:error, {:bad_probabilities, probabilities}}
  end

  defp cast_probability({disposition, mass}, {:ok, acc}) when is_binary(disposition) do
    with {:ok, atom} <- known_disposition(disposition),
         :ok <- unit_interval_check(disposition, mass) do
      {:cont, {:ok, Map.put(acc, atom, mass / 1)}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp cast_probability({disposition, _mass}, {:ok, _acc}) do
    {:halt, {:error, {:bad_probability_key, disposition}}}
  end

  defp known_disposition(disposition) do
    case disposition_atom(disposition) do
      nil -> {:error, {:bad_probability_key, disposition}}
      atom -> {:ok, atom}
    end
  end

  defp unit_interval_check(disposition, mass) do
    if unit_interval?(mass), do: :ok, else: {:error, {:bad_probability, disposition, mass}}
  end

  defp unit_interval?(mass), do: is_number(mass) and mass >= 0 and mass <= 1

  ## Composition

  # The mixture mean over the frozen vocabulary: marginals composed as
  # marginals. Missing keys contribute zero.
  @spec compose([observation()]) :: %{atom() => float()}
  defp compose(observations) do
    n = length(observations)

    Map.new(@dispositions, fn disposition ->
      total =
        Enum.reduce(observations, 0.0, fn observation, sum ->
          sum + (observation.probabilities[disposition] || 0.0)
        end)

      {disposition, total / n}
    end)
  end

  defp decimal_string(mass), do: :erlang.float_to_binary(mass / 1, [:short])

  ## The disposition pick

  # The fixed invariant first: a credible contradiction on any
  # constituent observation dominates — the aggregate is :contradicts,
  # never :supports (or anything else), whatever the composed masses
  # say. Otherwise the composed argmax, ties in vocabulary order.
  @spec disposition([observation()], %{atom() => float()}) :: atom()
  defp disposition(observations, masses) do
    if credible_contradiction?(observations) do
      :contradicts
    else
      masses
      |> Enum.max_by(fn {disposition, mass} -> {mass, tie_break(disposition)} end)
      |> elem(0)
    end
  end

  defp credible_contradiction?(observations) do
    Enum.any?(observations, fn observation ->
      (observation.probabilities[:contradicts] || 0.0) >= @dominance_bound
    end)
  end

  # Ties break in the frozen vocabulary's order: Enum.max_by keeps the
  # FIRST maximum, so rank earlier dispositions higher.
  defp tie_break(disposition) do
    length(@dispositions) - Enum.find_index(@dispositions, &(&1 == disposition))
  end
end
