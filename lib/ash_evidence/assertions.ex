# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Assertions do
  @moduledoc """
  The assertion surface: the aggregate evidence verdict one packet's
  adjudication produced — the admission's provenance.

  The assertion itself is a **host-composable fragment**
  (`AshEvidence.Assertions.Fragment`): the host defines the persisted
  resource on its own platform base so the host's AshEvents audit,
  tenancy and policies apply — the same shape as the judgment ledger's
  observation fragment. The package never defines the persisted
  assertion resource, and never depends on an events framework to give
  it audit: the fragment pattern IS how hosts get it.

  Envelope-class by construction (RFC retention posture): every field is
  an id, a digest, a frozen-vocabulary atom or a decimal string. The
  assertion survives document erasure — packet, evaluation and candidate
  sets cascade away; it reads afterwards as references to things that no
  longer resolve, and `record_hash` still verifies, because nothing
  hashed was ever payload-class.
  """

  @moduledoc since: "0.1.0"

  alias AshEvidence.Assertions.Canonical

  # The frozen disposition vocabulary (§5.5, the evidence-outcome
  # algebra) — the aggregate value lives in the same vocabulary as the
  # observations it composes. `:wrong_scope` rides along: where a
  # question declared it, it flows through aggregation as the fifth
  # disposition like any other.
  @dispositions [:supports, :contradicts, :insufficient, :not_applicable, :wrong_scope]

  @record_version "1"

  @doc "The frozen disposition vocabulary, in tie-break order."
  @spec dispositions() :: [atom()]
  def dispositions, do: @dispositions

  @doc "The assertion record's schema version, major only."
  @spec record_version() :: String.t()
  def record_version, do: @record_version

  @doc "The aggregation rule version this package composes with."
  @spec aggregation_rule_version() :: String.t()
  def aggregation_rule_version, do: AshEvidence.Assertions.Aggregation.version()

  @doc """
  The assertion's `record_hash` (§4.5 discipline): the digest of the
  record's own canonical JSON, minus `record_hash` itself and minus the
  one database-generated field (`created_at`). Everything on an
  assertion is envelope-class, so there are no payload exclusions — a
  row whose document was erased still verifies.

  Accepts atom- or string-keyed attrs; nil fields are omitted (the
  digest of nothing is nothing, never the digest of `null`).
  """
  @spec record_hash(map()) :: String.t()
  def record_hash(attrs) when is_map(attrs) do
    excluded = MapSet.new(["record_hash", "created_at"])

    attrs
    |> Enum.reject(fn {key, value} -> is_nil(value) or to_string(key) in excluded end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Canonical.digest()
  end
end
