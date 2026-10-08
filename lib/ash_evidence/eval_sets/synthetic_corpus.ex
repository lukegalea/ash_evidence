# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.EvalSets.SyntheticCorpus do
  @moduledoc """
  The synthetic CC0 eval corpus: fabricated clinic-service documents and
  the (document, claim, expected-outcome) items AC-4 measures.

  ## Licence

  Every document and item this generator produces is **dedicated to the
  public domain under CC0-1.0** (`license/0`): the content is fabricated
  from synthetic vocabulary ("SYNTH CLINIC GROUP", "SYNTH VENDOR",
  numbered agreement references") — no real document, no copyrighted
  text, no customer data. The dedication rides every item's `license`
  metadata; see `docs/eval-corpus.md`.

  ## Determinism

  Fixed seed (default `default_seed/0`), ONE `:rand` stream consumed in
  one build pass, no wall-clock, no unique-integers: regeneration is
  byte-stable — the same seed produces byte-identical document bytes
  (and therefore the same content hashes on ingest) and identical items
  (property-tested).

  ## Composition (default: 500 items ≥ 480)

    * **`:supports` (250)** — the document states the claim's
      proposition; the gold span carries it. Includes 30
      *near-duplicate document pairs* (same proposition and value,
      fresh serial/date/signature — the corpus's duplicate-document
      substrate).
    * **`:contradicts` (125)** — the gold span states the claimed value
      and NEGATES it ("... is never granted ..."): the span a correct
      adjudication reads as a contradiction. These documents are the
      false-supports trap: the claimed value IS present, phrased as a
      denial.
    * **`:insufficient` (125)** — the proposition's value appears
      NOWHERE in the document (silent documents — the other half of
      the false-supports substrate: retrieval must surface nothing,
      because there is nothing true to surface).
    * **12 of the 500 arrive with an explicit `:audit` split** (never
      drawn — honoured verbatim per the discipline).

  Within every document, non-gold spans are *distractors*: agreement
  phrasing from OTHER propositions — shared register, never the claim's
  stem or value — so lexical retrieval must rank the gold span first on
  matched-term counts, and a silent document matches nothing at all.
  """

  @default_seed 1515
  @license "CC0-1.0"
  @source "ash_evidence/synthetic-corpus/1"

  @counts %{supports: 250, contradicts: 125, insufficient: 125}
  @audit_within %{supports: 6, contradicts: 3, insufficient: 3}
  @near_duplicate_pairs 30

  # The proposition bank: each proposition has a content stem (all
  # non-stopwords) and a value set. Claim/support/contradict phrasings
  # are built so the gold spans carry the claim's FULL stem plus the
  # distinctive value — and the contradict phrasing adds a negation cue
  # (the :contradicts framing's contrast terms).
  @propositions [
    %{
      stem: "equipment maintenance coverage period",
      values: ["6 months", "12 months", "24 months"]
    },
    %{stem: "fleet replacement discount", values: ["5 percent", "10 percent", "15 percent"]},
    %{stem: "emergency repair response time", values: ["4 hours", "8 hours", "24 hours"]},
    %{
      stem: "onsite sterilization training allowance",
      values: ["2 sessions per year", "4 sessions per year", "6 sessions per year"]
    },
    %{
      stem: "service records audit allowance",
      values: ["1 audit per year", "2 audits per year", "4 audits per year"]
    }
  ]

  defstruct [:seed, :documents, :items]

  @type document :: %{
          required(:serial) => String.t(),
          required(:bytes) => String.t(),
          required(:spans) => [String.t()]
        }

  @type item :: %{
          required(:ordinal) => pos_integer(),
          required(:document_serial) => String.t(),
          required(:claim) => String.t(),
          required(:gold_span_index) => non_neg_integer() | nil,
          required(:expected_disposition) => atom(),
          required(:expected_hypothesis) => atom() | nil,
          required(:source) => String.t(),
          required(:license) => String.t(),
          required(:split) => atom() | nil
        }

  @doc "The default corpus seed (fixed — regeneration is byte-stable)."
  def default_seed, do: @default_seed

  @doc "The licence every generated document and item carries."
  def license, do: @license

  @doc "The per-item provenance source string."
  def source, do: @source

  @doc "The planned composition (kind => count)."
  def counts, do: @counts

  @doc """
  Generate the corpus. Deterministic in `seed`; the default seed is the
  shipped corpus.
  """
  @spec generate(integer()) :: %__MODULE__{
          seed: integer(),
          documents: [document()],
          items: [item()]
        }
  def generate(seed \\ @default_seed) when is_integer(seed) do
    :rand.seed(:exsss, {seed, 0, 0})

    {documents, items} =
      item_specs()
      |> Enum.with_index(1)
      |> Enum.map(fn {spec, ordinal} -> build({spec, ordinal}, ordinal) end)
      |> Enum.unzip()

    %__MODULE__{seed: seed, documents: documents, items: items}
  end

  ## The item plan: fixed composition, deterministic audit placement,
  ## deterministic near-duplicate pairing (a pair = primary then twin;
  ## the twin inherits the primary's proposition and value verbatim).

  defp item_specs do
    kind_specs(:supports, @counts.supports, @audit_within.supports) ++
      kind_specs(:contradicts, @counts.contradicts, @audit_within.contradicts) ++
      kind_specs(:insufficient, @counts.insufficient, @audit_within.insufficient)
  end

  defp kind_specs(:supports = kind, count, audit_count) do
    # Pairing layout: items (audit_count+1)..(audit_count+60) are the
    # 30 pairs; audits never join a pair.
    first = audit_count + 1
    last = first + 2 * @near_duplicate_pairs - 1

    {specs, _pairs} =
      Enum.map_reduce(1..count, %{}, fn i, pairs ->
        audit? = i <= audit_count
        in_pair_range? = i >= first and i <= last

        cond do
          audit? or not in_pair_range? ->
            proposition = Enum.random(@propositions)

            {%{
               kind: kind,
               proposition: proposition,
               value: Enum.random(proposition.values),
               near_duplicate?: false,
               audit?: audit?
             }, pairs}

          rem(i - first, 2) == 0 ->
            # The pair's primary: draw and remember for the twin.
            proposition = Enum.random(@propositions)
            value = Enum.random(proposition.values)

            {%{
               kind: kind,
               proposition: proposition,
               value: value,
               near_duplicate?: false,
               audit?: false
             }, Map.put(pairs, pair_number(i, first), %{proposition: proposition, value: value})}

          true ->
            # The twin: inherits the primary's proposition and value.
            inherited = Map.fetch!(pairs, pair_number(i, first))

            {%{
               kind: kind,
               proposition: inherited.proposition,
               value: inherited.value,
               near_duplicate?: true,
               audit?: false
             }, pairs}
        end
      end)

    specs
  end

  defp kind_specs(kind, count, audit_count) do
    Enum.map(1..count, fn i ->
      audit? = i <= audit_count
      proposition = Enum.random(@propositions)

      %{
        kind: kind,
        proposition: proposition,
        value: Enum.random(proposition.values),
        near_duplicate?: false,
        audit?: audit?
      }
    end)
  end

  defp pair_number(i, first), do: div(i - first, 2)

  ## Building one document + item from a spec — the ONLY place the RNG
  ## advances per item, in a fixed order.

  @spec build({map(), pos_integer()}, pos_integer()) :: {document(), item()}
  defp build({spec, _index_in_list}, ordinal) do
    value = spec.value || Enum.random(spec.proposition.values)
    {distractor_a, distractor_b} = distractors(spec.proposition)
    serial = serial(ordinal)
    signature = "signed for the parties by SYNTH SIGNATORY #{:rand.uniform(999)}"
    date = synthetic_date()

    proposition_span =
      case spec.kind do
        :supports -> support_span(spec.proposition, value)
        :contradicts -> contradict_span(spec.proposition, value)
        :insufficient -> nil
      end

    spans =
      [
        "SERVICE AND MAINTENANCE AGREEMENT (SYNTHETIC SAMPLE)",
        "agreement reference: SYNTH-AG-#{serial}",
        "parties: SYNTH CLINIC GROUP and SYNTH VENDOR #{:rand.uniform(99)}",
        "effective date: #{date} (synthetic calendar)"
      ]
      |> append_proposition_span(proposition_span)
      |> Kernel.++([
        distractor_a,
        distractor_b,
        "this synthetic agreement exists only to exercise retrieval machinery",
        signature
      ])

    document = %{serial: serial, spans: spans, bytes: Enum.join(spans, "\n")}

    item = %{
      ordinal: ordinal,
      document_serial: serial,
      claim: claim(spec.proposition, value),
      gold_span_index: if(proposition_span, do: 4, else: nil),
      expected_disposition: spec.kind,
      expected_hypothesis: expected_hypothesis(spec.kind),
      source: @source,
      license: @license,
      split: if(spec.audit?, do: :audit, else: nil),
      near_duplicate?: spec.near_duplicate?
    }

    {document, item}
  end

  defp append_proposition_span(spans, nil), do: spans
  defp append_proposition_span(spans, span), do: spans ++ [span]

  defp claim(proposition, value), do: "the #{proposition.stem} is #{value}"

  defp support_span(proposition, value),
    do: "the #{proposition.stem} is #{value} for this agreement"

  defp contradict_span(proposition, value),
    do: "the #{value} #{proposition.stem} is never granted without a loaned-unit endorsement"

  # Two distractor spans from OTHER propositions: shared agreement
  # register, never the claim's stem or value. Deterministic draws.
  defp distractors(proposition) do
    others = Enum.reject(@propositions, &(&1.stem == proposition.stem))
    [first, second | _] = Enum.shuffle(others)

    {
      "the #{first.stem} schedule is reviewed annually by the vendor",
      "changes to the #{second.stem} require written notice from the clinic group"
    }
  end

  defp expected_hypothesis(:insufficient), do: nil
  defp expected_hypothesis(:contradicts), do: :contradicts
  defp expected_hypothesis(:supports), do: :supports

  defp serial(ordinal), do: String.pad_leading(Integer.to_string(ordinal), 5, "0")

  defp synthetic_date do
    year = 2024 + :rand.uniform(3)
    month = String.pad_leading(Integer.to_string(:rand.uniform(12)), 2, "0")
    day = String.pad_leading(Integer.to_string(:rand.uniform(28)), 2, "0")
    "#{year}-#{month}-#{day}"
  end
end
