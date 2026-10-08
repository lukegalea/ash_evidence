# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Validations.ObservationJoin do
  @moduledoc """
  The packet's `candidate_observations` field is a JOIN to the judgment
  ledger — `atom_id → %{observation_id, question_hash}` — and nothing
  else. This validation rejects any inner shape that is not exactly the
  id+hash pair, so a copied answer has no key to hide under: the packet
  references ledger rows, it never records what they said.

  The inner keys may arrive atom- or string-keyed (Ash params vs stored
  JSON); both normalise to the string-keyed check.
  """

  use Ash.Resource.Validation

  @join_keys MapSet.new(["observation_id", "question_hash"])

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :candidate_observations) do
      observations when is_map(observations) ->
        observations
        |> Enum.reduce_while(:ok, &check_join/2)
        |> validation_result()

      nil ->
        :ok

      _other ->
        {:error, field: :candidate_observations, message: "candidate_observations must be a map"}
    end
  end

  defp check_join({atom_id, join}, :ok) when is_binary(atom_id) and is_map(join) do
    case join_shape(join) do
      :ok -> {:cont, :ok}
      {:error, message} -> {:halt, {:error, field: :candidate_observations, message: message}}
    end
  end

  defp check_join(_other, _acc) do
    {:halt,
     {:error,
      field: :candidate_observations,
      message: "candidate_observations maps atom ids (strings) to observation joins"}}
  end

  defp validation_result(:ok), do: :ok
  defp validation_result({:error, error}), do: {:error, error}

  defp join_shape(join) do
    normalised = Map.new(join, fn {key, value} -> {to_string(key), value} end)
    keys = normalised |> Map.keys() |> MapSet.new()

    cond do
      not MapSet.equal?(keys, @join_keys) ->
        {:error,
         "an observation join is exactly %{observation_id, question_hash} — the packet " <>
           "references ledger rows and never copies their answers"}

      not is_binary(normalised["observation_id"]) ->
        {:error, "observation_id must be the ledger row's id (a string)"}

      not is_binary(normalised["question_hash"]) ->
        {:error, "question_hash must be the question's hash (a string)"}

      true ->
        :ok
    end
  end
end
