# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Assertions.Canonical do
  @moduledoc """
  Canonical JSON and the digest discipline the assertion's `record_hash`
  hangs off — the judgment-record RFC's §4.2/§4.3 rules, implemented
  in-package (no dependency on any ledger package):

    * keys sorted recursively, no whitespace between tokens;
    * atoms as strings, explicit `nil`, arrays in order;
    * every real number as the shortest decimal that round-trips the
      IEEE-754 double (`:erlang.float_to_binary(x, [:short])`) — never
      a display rounding;
    * digests are `"sha256:" <> 64 lower hex`.

  The same encoding that makes an assertion's hash verifiable after
  replay makes it verifiable after erasure: nothing hashed is
  payload-class.
  """

  @type json ::
          nil | boolean() | integer() | float() | String.t() | [json()] | %{String.t() => json()}

  @doc "The canonical JSON encoding."
  @spec encode(term()) :: String.t()
  def encode(value), do: value |> enc() |> IO.iodata_to_binary()

  @doc "`\"sha256:\" <> lower hex` over the canonical JSON."
  @spec digest(term()) :: String.t()
  def digest(value) do
    "sha256:" <> (:crypto.hash(:sha256, encode(value)) |> Base.encode16(case: :lower))
  end

  defp enc(nil), do: "null"
  defp enc(true), do: "true"
  defp enc(false), do: "false"

  defp enc(value) when is_atom(value), do: enc(Atom.to_string(value))

  # JSON string escaping is Jason's leaf job: correct, and a dependency
  # already on the package's graph.
  defp enc(value) when is_binary(value), do: Jason.encode!(value)

  defp enc(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp enc(value) when is_integer(value), do: Integer.to_string(value)

  defp enc(value) when is_list(value) do
    value
    |> Enum.map(&enc/1)
    |> Enum.intersperse(",")
    |> then(&[?[, &1, ?]])
    |> IO.iodata_to_binary()
  end

  defp enc(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> [enc(to_string(key)), ?:, enc(inner)] end)
    |> Enum.sort()
    |> Enum.intersperse(",")
    |> then(&[?{, &1, ?}])
    |> IO.iodata_to_binary()
  end
end
