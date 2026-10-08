# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AssertionsTest do
  @moduledoc """
  The assertion as the test host composes it: the fragment on a host
  base, the inputs-only :record create with its one pure derived field,
  the decimal-string distribution, and the frozen vocabulary.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.Assertions
  alias AshEvidence.Test.{Fixtures, HostAssertion}

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  defp assertion_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: Ash.UUID.generate(),
        packet_id: Ash.UUID.generate(),
        evaluation_id: Ash.UUID.generate(),
        disposition: :contradicts,
        distribution: %{
          "supports" => "0.485",
          "contradicts" => "0.4",
          "insufficient" => "0.115",
          "not_applicable" => "0.0",
          "wrong_scope" => "0.0"
        },
        aggregation_rule_version: Assertions.aggregation_rule_version(),
        observation_ids: [Ash.UUID.generate(), Ash.UUID.generate()],
        subject: Fixtures.subject(),
        predicate: Fixtures.predicate(),
        subject_state_digest: Fixtures.hash_of("state"),
        question_set_hash: Fixtures.hash_of("question-set")
      },
      overrides
    )
  end

  test "the host records an assertion through the fragment" do
    attrs = assertion_attrs()
    assertion = Ash.create!(HostAssertion, attrs, action: :record, authorize?: false)

    assert assertion.disposition == :contradicts
    assert assertion.distribution["supports"] == "0.485"
    assert assertion.aggregation_rule_version == "1"
    assert assertion.record_version == "1"
    assert assertion.subject == Fixtures.subject()
    assert %DateTime{} = assertion.created_at
    assert is_binary(assertion.record_hash)
  end

  test "record_hash is a pure function of the inputs — identical inputs, identical hash" do
    attrs = assertion_attrs()

    a = Ash.create!(HostAssertion, attrs, action: :record, authorize?: false)

    # The caller-supplied id is the idempotency key: re-recording the
    # SAME assertion is refused (one row per assertion), exactly like an
    # observation re-record.
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(HostAssertion, attrs, action: :record, authorize?: false)

    # And the hash is reproducible from the inputs alone, byte for byte.
    recomputed =
      Assertions.record_hash(%{
        id: attrs.id,
        record_version: Assertions.record_version(),
        packet_id: attrs.packet_id,
        evaluation_id: attrs.evaluation_id,
        disposition: attrs.disposition,
        distribution: attrs.distribution,
        aggregation_rule_version: attrs.aggregation_rule_version,
        observation_ids: attrs.observation_ids,
        subject: attrs.subject,
        predicate: attrs.predicate,
        subject_state_digest: attrs.subject_state_digest,
        question_set_hash: attrs.question_set_hash
      })

    assert recomputed == a.record_hash

    # A different id is a different record, honestly hashed.
    c = Ash.create!(HostAssertion, assertion_attrs(), action: :record, authorize?: false)
    refute c.record_hash == a.record_hash
  end

  test "record_hash verifies against the stored record (§4.5 recomputation)" do
    assertion = Ash.create!(HostAssertion, assertion_attrs(), action: :record, authorize?: false)

    recomputed =
      Assertions.record_hash(%{
        id: assertion.id,
        record_version: assertion.record_version,
        packet_id: assertion.packet_id,
        evaluation_id: assertion.evaluation_id,
        disposition: assertion.disposition,
        distribution: assertion.distribution,
        aggregation_rule_version: assertion.aggregation_rule_version,
        observation_ids: assertion.observation_ids,
        subject: assertion.subject,
        predicate: assertion.predicate,
        subject_state_digest: assertion.subject_state_digest,
        question_set_hash: assertion.question_set_hash
      })

    assert recomputed == assertion.record_hash
  end

  test "the disposition is the frozen vocabulary — nothing else casts" do
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               HostAssertion,
               assertion_attrs(%{disposition: :refutes}),
               action: :record,
               authorize?: false
             )
  end

  test "the vocabulary is the frozen four plus wrong_scope" do
    assert Assertions.dispositions() == [
             :supports,
             :contradicts,
             :insufficient,
             :not_applicable,
             :wrong_scope
           ]
  end

  test "nil references are omitted from the hash, not hashed as nulls" do
    with_refs = Ash.create!(HostAssertion, assertion_attrs(), action: :record, authorize?: false)

    without_refs =
      Ash.create!(
        HostAssertion,
        assertion_attrs(%{packet_id: nil, evaluation_id: nil}),
        action: :record,
        authorize?: false
      )

    # Both rows verify by recomputation — including the one with no refs.
    for assertion <- [with_refs, without_refs] do
      recomputed =
        Assertions.record_hash(%{
          id: assertion.id,
          record_version: assertion.record_version,
          packet_id: assertion.packet_id,
          evaluation_id: assertion.evaluation_id,
          disposition: assertion.disposition,
          distribution: assertion.distribution,
          aggregation_rule_version: assertion.aggregation_rule_version,
          observation_ids: assertion.observation_ids,
          subject: assertion.subject,
          predicate: assertion.predicate,
          subject_state_digest: assertion.subject_state_digest,
          question_set_hash: assertion.question_set_hash
        })

      assert recomputed == assertion.record_hash
    end
  end
end
