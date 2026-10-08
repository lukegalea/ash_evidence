# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Ac4FalseSupportsTest do
  @moduledoc """
  AC-4, measured over the synthetic CC0 corpus: retrieval that surfaces
  a span which does NOT carry the claim's truth — the manufactured
  support — must stay at or below 1% of the items.

  The metric, per item, over the item's OWN document version (the eval
  seam is version-scoped):

    * `:supports` items — the `:supports` framing's rank-1 candidate
      must BE the gold atom; anything else at rank 1 is a manufactured
      support (retrieval pointed adjudication at a span that does not
      carry the truth).
    * `:contradicts` items — same rule: the gold contradicting span
      (the claimed value, phrased as a denial) must outrank every
      non-gold span under `:supports`; a distractor at rank 1 is a
      manufactured support.
    * `:insufficient` items — the document is silent; the `:supports`
      framing must surface NOTHING. Any candidate is a manufactured
      support (there is nothing true to surface).

  Coverage is reported alongside (gold-at-1 per kind, the provisional
  thresholds of the design note: ≥ 0.95 supports, ≥ 0.90 contradicts).
  """

  use ExUnit.Case, async: true

  alias AshEvidence.{AddressedAtom, DocumentVersion, Domain, EvalSets, ParseRun, Retrieval}
  alias AshEvidence.EvalSets.SyntheticCorpus

  @moduletag :db
  @moduletag :ac4

  @k 3
  @false_supports_max 0.01
  @supports_gold_at_1_min 0.95
  @contradicts_gold_at_1_min 0.90

  test "AC-4: the retrieval layer's false-supports rate over the corpus is <= 1%" do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)

    corpus = SyntheticCorpus.generate()
    {versions_by_sha, _runs_by_version, atoms_by_doc} = seed_corpus(corpus)

    # --- The eval set: the corpus lands under the landing discipline.
    set =
      Domain.open_eval_set!(
        "synthetic-retrieval",
        1,
        "the AC-4 false-supports substrate (synthetic CC0 corpus)",
        SyntheticCorpus.default_seed(),
        %{
          "algorithm" => "ash_evidence/eval_sets/draw 1",
          "drawn_splits" => 3,
          "generator" => SyntheticCorpus.source(),
          "license" => SyntheticCorpus.license()
        }
      )

    specs =
      Enum.map(corpus.items, fn item ->
        document = Enum.find(corpus.documents, &(&1.serial == item.document_serial))
        version = Map.fetch!(versions_by_sha, sha(document.bytes))
        doc_atoms = Map.fetch!(atoms_by_doc, version.id)

        gold_atom_ids =
          case item.gold_span_index do
            nil -> []
            index -> [Map.fetch!(doc_atoms, index + 1)]
          end

        %{
          document_version_id: version.id,
          claim: item.claim,
          gold_atom_ids: gold_atom_ids,
          expected_disposition: item.expected_disposition,
          expected_hypothesis: item.expected_hypothesis,
          source: item.source,
          license: item.license,
          split: item.split
        }
      end)

    items = EvalSets.draw_and_add_items!(specs, set)
    assert length(items) == length(corpus.items)
    Domain.publish_eval_set!(set)

    # --- The measurement: run the retrieval layer over every item.
    versions_by_id = Map.new(Map.values(versions_by_sha), &{&1.id, &1})

    metrics =
      Enum.reduce(items, %{fs: %{}, g1: %{}, n: %{}}, fn item, acc ->
        # The persisted item carries its own document reference and its
        # own gold atoms — the measurement reads the eval set, not the
        # generator.
        version = Map.fetch!(versions_by_id, item.document_version_id)
        gold_atom_id = item.gold_atom_ids |> List.first()

        result =
          Retrieval.retrieve!(version, item.claim, hypotheses: [:supports, :contradicts], k: @k)

        supports_rank1 =
          case result.by_hypothesis.supports do
            [first | _] -> first.atom_id
            [] -> nil
          end

        acc = bump(acc, :n, item.expected_disposition)

        acc =
          cond do
            item.expected_disposition == :insufficient ->
              # Silent document: any surfaced support is manufactured.
              if supports_rank1, do: bump(acc, :fs, :insufficient), else: acc

            supports_rank1 && supports_rank1 != gold_atom_id ->
              # A non-gold span at rank 1 under :supports.
              bump(acc, :fs, item.expected_disposition)

            true ->
              acc
          end

        # Coverage: gold at rank 1 under the item's expected framing.
        expected = item.expected_hypothesis

        if expected && gold_atom_id do
          framed_rank1 =
            case Map.fetch!(result.by_hypothesis, expected) do
              [first | _] -> first.atom_id
              [] -> nil
            end

          if framed_rank1 == gold_atom_id do
            bump(acc, :g1, expected)
          else
            acc
          end
        else
          acc
        end
      end)

    totals = metrics.n

    non_supports_total = Map.get(totals, :contradicts, 0) + Map.get(totals, :insufficient, 0)

    false_supports_count =
      Map.get(metrics.fs, :contradicts, 0) + Map.get(metrics.fs, :insufficient, 0)

    false_supports_rate = false_supports_count / non_supports_total

    supports_g1 = rate(Map.get(metrics.g1, :supports, 0), totals[:supports])

    contradicts_g1 = rate(Map.get(metrics.g1, :contradicts, 0), totals[:contradicts])

    IO.puts("""
    AC-4 (AST-153) — synthetic CC0 corpus, seed #{SyntheticCorpus.default_seed()}
      items: #{length(items)} (supports #{totals[:supports]}, contradicts #{totals[:contradicts]}, insufficient #{totals[:insufficient]})
      false supports: #{false_supports_count}/#{non_supports_total} non-supports items = #{Float.round(false_supports_rate * 100, 3)}% (max 1.0%)
      coverage (gold at rank 1 under the expected framing):
        supports:    #{Map.get(metrics.g1, :supports, 0)}/#{totals[:supports]} = #{Float.round((supports_g1 || 0.0) * 100, 3)}% (min 95.0%)
        contradicts: #{Map.get(metrics.g1, :contradicts, 0)}/#{totals[:contradicts]} = #{Float.round((contradicts_g1 || 0.0) * 100, 3)}% (min 90.0%)
    """)

    assert false_supports_rate <= @false_supports_max,
           "false-supports rate #{false_supports_rate} exceeds 1%: #{inspect(metrics.fs)}"

    assert supports_g1 >= @supports_gold_at_1_min,
           "supports gold-at-1 coverage #{supports_g1} below 0.95"

    assert contradicts_g1 >= @contradicts_gold_at_1_min,
           "contradicts gold-at-1 coverage #{contradicts_g1} below 0.90"
  end

  ## Corpus seeding — bulk, matched by content hash / seq (never by
  ## result order).

  defp seed_corpus(corpus) do
    versions =
      bulk!(
        DocumentVersion,
        :ingest,
        Enum.map(corpus.documents, fn doc ->
          %{kind: "text/plain", bytes: doc.bytes, sha256: sha(doc.bytes)}
        end)
      )

    versions_by_sha = Map.new(versions, &{&1.sha256, &1})

    runs =
      bulk!(
        ParseRun,
        :start,
        Enum.map(corpus.documents, fn doc ->
          %{
            document_version_id: versions_by_sha[sha(doc.bytes)].id,
            instrument: "synthetic-corpus-ingest"
          }
        end)
      )

    runs_by_version = Map.new(runs, &{&1.document_version_id, &1})

    atoms =
      bulk!(
        AddressedAtom,
        :ingest,
        for(
          doc <- corpus.documents,
          {span, index} <- Enum.with_index(doc.spans, 1),
          do: %{
            document_version_id: versions_by_sha[sha(doc.bytes)].id,
            parse_run_id: runs_by_version[versions_by_sha[sha(doc.bytes)].id].id,
            seq: index,
            text: span
          }
        )
      )

    atoms_by_doc =
      atoms
      |> Enum.group_by(& &1.document_version_id)
      |> Map.new(fn {version_id, records} ->
        {version_id, Map.new(records, &{&1.seq, &1.id})}
      end)

    {versions_by_sha, runs_by_version, atoms_by_doc}
  end

  defp bulk!(resource, action, inputs) do
    result =
      Ash.bulk_create(inputs, resource, action, return_records?: true, return_errors?: true)

    assert result.status == :success,
           "bulk #{action} failed: #{inspect(result.errors, limit: 5)}"

    result.records
  end

  defp bump(acc, :fs, kind), do: %{acc | fs: Map.update(acc.fs, kind, 1, &(&1 + 1))}

  defp bump(acc, :n, kind), do: %{acc | n: Map.update(acc.n, kind, 1, &(&1 + 1))}

  defp bump(acc, :g1, kind), do: %{acc | g1: Map.update(acc.g1, kind, 1, &(&1 + 1))}

  defp rate(_hits, 0), do: nil
  defp rate(hits, total) when is_integer(total), do: hits / total

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
