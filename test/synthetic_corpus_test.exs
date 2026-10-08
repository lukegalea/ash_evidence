# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.SyntheticCorpusTest do
  @moduledoc """
  The synthetic CC0 corpus's own contract: byte-stable regeneration,
  the planned composition (N ≥ 480), clearly-synthetic content, the CC0
  dedication on every item, and the separability invariants AC-4's
  measurement rests on (the claim's distinctive value occurs in gold
  spans only; contradicting gold spans carry a negation cue; silent
  documents carry neither).
  """

  use ExUnit.Case, async: true

  alias AshEvidence.EvalSets.SyntheticCorpus

  @corpus SyntheticCorpus.generate()

  test "regeneration is byte-stable (fixed seed)" do
    assert SyntheticCorpus.generate() == @corpus
    assert SyntheticCorpus.generate(SyntheticCorpus.default_seed()) == @corpus

    # Document bytes are byte-identical across runs — and therefore
    # content-address to the same versions on ingest.
    bytes_a = @corpus.documents |> Enum.map(& &1.bytes)
    bytes_b = SyntheticCorpus.generate() |> Map.get(:documents) |> Enum.map(& &1.bytes)
    assert bytes_a == bytes_b
  end

  test "a different seed produces a different corpus" do
    refute SyntheticCorpus.generate(@corpus.seed + 1) == @corpus
  end

  test "N >= 480 with the planned composition" do
    assert length(@corpus.items) >= 480
    assert length(@corpus.documents) == length(@corpus.items)

    by_kind = Enum.frequencies(Enum.map(@corpus.items, & &1.expected_disposition))
    assert by_kind == SyntheticCorpus.counts()
    assert Enum.sum(Map.values(by_kind)) == length(@corpus.items)
  end

  test "30 near-duplicate document pairs: same claim, distinct documents" do
    supports = Enum.filter(@corpus.items, &(&1.expected_disposition == :supports))
    twins = Enum.filter(supports, & &1.near_duplicate?)

    # 30 pairs -> 30 twins; each twin's claim is shared with exactly one
    # other item (its primary).
    assert length(twins) == 30

    for twin <- twins do
      primary = Enum.find(supports, &(&1.claim == twin.claim and not &1.near_duplicate?))
      assert primary, "twin item #{twin.ordinal} has no primary"

      twin_doc = doc_by_serial(twin.document_serial)
      primary_doc = doc_by_serial(primary.document_serial)

      # Distinct documents that are near-identical: same SPAN COUNT and
      # the same proposition span, different identity lines.
      assert twin_doc.serial != primary_doc.serial
      assert length(twin_doc.spans) == length(primary_doc.spans)
      assert Enum.at(twin_doc.spans, 4) == Enum.at(primary_doc.spans, 4)
      assert Enum.at(twin_doc.spans, 1) != Enum.at(primary_doc.spans, 1)
      assert Enum.at(twin_doc.spans, 3) != Enum.at(primary_doc.spans, 3)
    end
  end

  test "12 audit items arrive with their explicit split, never drawn" do
    audits = Enum.filter(@corpus.items, &(&1.split == :audit))
    assert length(audits) == 12
  end

  test "every item carries the CC0 dedication and provenance" do
    assert Enum.all?(@corpus.items, &(&1.license == "CC0-1.0"))
    assert Enum.all?(@corpus.items, &(&1.source == SyntheticCorpus.source()))
    assert SyntheticCorpus.license() == "CC0-1.0"
  end

  test "the content is clearly synthetic" do
    for document <- @corpus.documents do
      assert String.contains?(document.bytes, "SYNTH CLINIC GROUP")
      assert String.contains?(document.bytes, "SYNTHETIC SAMPLE")
      # The no-real-content guard: the synthetic marker rides every doc.
      assert String.contains?(document.bytes, "synthetic")
    end
  end

  test "separability: the claim's distinctive value occurs in gold spans only" do
    for item <- @corpus.items do
      document = doc_by_serial(item.document_serial)
      [_, value] = claim_stem_and_value(item.claim)

      case item.expected_disposition do
        :insufficient ->
          # Silent documents: the proposition's value appears NOWHERE —
          # retrieval must surface nothing for the claim.
          refute String.contains?(document.bytes, value),
                 "silent doc #{item.document_serial} leaks the claim's value"

        kind when kind in [:supports, :contradicts] ->
          gold_span = Enum.at(document.spans, item.gold_span_index)
          assert String.contains?(gold_span, value)

          # The gold span carries the claim's FULL stem (the lexical
          # AND must reach it), and the gold span is the doc's ONLY
          # span carrying the value.
          [stem, _] = claim_stem_and_value(item.claim)

          assert Enum.all?(String.split(stem, " "), &String.contains?(gold_span, &1)),
                 "gold span of #{item.document_serial} misses part of the claim stem"

          assert Enum.count(document.spans, &String.contains?(&1, value)) == 1

          if kind == :contradicts do
            # The contradict framing's contrast cues (never AND without)
            # must both reach the gold span.
            assert String.contains?(gold_span, "never")
            assert String.contains?(gold_span, "without")
          end
      end
    end
  end

  defp doc_by_serial(serial), do: Enum.find(@corpus.documents, &(&1.serial == serial))

  defp claim_stem_and_value(claim) do
    case String.split(claim, " is ", parts: 2) do
      ["the " <> stem, value] -> [stem, value]
      _ -> raise "unexpected claim shape: #{claim}"
    end
  end
end
