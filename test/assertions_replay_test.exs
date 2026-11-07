# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AssertionsReplayTest do
  @moduledoc """
  The fragment under AshEvents replay: a host that audits the assertion
  with AshEvents must get a byte-identical row back from the event log,
  with the same `created_at` (the fragment's `create_timestamp`
  restore-on-replay contract) and the same `record_hash` (the :record
  change is a pure function of the inputs).
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Test.{Fixtures, HostAssertion, HostEventLog}

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  test "replaying the event log rebuilds the row with the same created_at and record_hash" do
    id = Ash.UUID.generate()

    original =
      Ash.create!(
        HostAssertion,
        %{
          id: id,
          packet_id: Ash.UUID.generate(),
          evaluation_id: Ash.UUID.generate(),
          disposition: :supports,
          distribution: %{
            "supports" => "0.9",
            "contradicts" => "0.05",
            "insufficient" => "0.05",
            "not_applicable" => "0.0",
            "wrong_scope" => "0.0"
          },
          aggregation_rule_version: AshEvidence.Assertions.aggregation_rule_version(),
          observation_ids: [Ash.UUID.generate()],
          subject: Fixtures.subject(),
          predicate: Fixtures.predicate(),
          subject_state_digest: Fixtures.hash_of("state"),
          question_set_hash: Fixtures.hash_of("question-set")
        },
        action: :record,
        authorize?: false
      )

    assert %DateTime{} = original.created_at
    assert is_binary(original.record_hash)

    # The clear-records hook empties the table; the row exists again only
    # because the event is replayed.
    HostEventLog
    |> Ash.ActionInput.for_action(:replay, %{})
    |> Ash.run_action!()

    replayed = Ash.get!(HostAssertion, id, authorize?: false)

    assert DateTime.compare(replayed.created_at, original.created_at) == :eq
    assert replayed.record_hash == original.record_hash

    assert Map.drop(replayed, [:__meta__, :__metadata__]) ==
             Map.drop(original, [:__meta__, :__metadata__])
  end
end
