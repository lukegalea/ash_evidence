# Eval sets (landed — AST-153)

The eval-set layer: versioned, split-drawn sets of labelled items over
document-version corpora — the measurement substrate for the retrieval
and adjudication seams. This note's original discipline (below) is now
enforced by code.

## The resources

| Resource | Contract |
|---|---|
| `AshEvidence.EvalSet` | One versioned set (`unique_name_version`). `:open` accepts items; `:publish` is the one no-input terminal transition — a published set is frozen. The draw is recorded ON the set (`split_seed` + `split_provenance`), so any split assignment is reconstructible. |
| `AshEvidence.EvalItem` | One (document version, claim, expected outcome) pair: `gold_atom_ids` (empty exactly when the document is silent), `expected_disposition` (the frozen vocabulary), `expected_hypothesis` (the framing the gold must surface under), `source` + `license` provenance, and the `split`. Immutable, no update action — **moving a row between splits is not expressible**; a correction is a new set version. Items are added only while the set is `:open`. |

`AshEvidence.EvalSets.draw_and_add_items!/2` runs the split draw
(`AshEvidence.EvalSets.Draw`: `:optimise`/`:calibration`/`:test` from the
set's seed, advancing only on drawn items) and adds the specs in order;
`:audit` rows arrive with their own explicit split and are honoured
verbatim — audit is never drawn.

## The synthetic CC0 corpus

`AshEvidence.EvalSets.SyntheticCorpus.generate/1` produces 500 items
(the AC-4 substrate): 250 `:supports` (including 30 near-duplicate
document pairs), 125 `:contradicts` (the claimed value present, phrased
as a denial), 125 `:insufficient` (silent documents), 12 explicit
`:audit` rows. **Every document and item is dedicated to the public
domain under CC0-1.0** (`SyntheticCorpus.license/0` rides every item):
the content is fabricated from synthetic vocabulary ("SYNTH CLINIC
GROUP", "SYNTH VENDOR", numbered agreement references) — no real
document, no copyrighted text, no customer data. Regeneration is
byte-stable (fixed seed, one `:rand` stream, one build pass).

The measured AC-4 result over this corpus lives in
`test/ac4_false_supports_test.exs` (false-supports rate ≤ 1% with
gold-at-1 coverage reported).

## The original discipline (binding, now enforced)

- **Four splits**: `optimise`, `calibration`, `test` — drawn randomly —
  plus `audit`, which is *never drawn*: audit rows arrive from production
  and carry their own explicit `split` field, honoured verbatim.
- **Split before labelling**, where possible, so no split's items leak into
  another split's labelling.
- **Moving a row between splits is prohibited.** A re-split is a NEW
  eval-set version; the old one stands untouched.
- **The draw is recorded beside the items** — seed and provenance on the
  set — so any split assignment is reconstructible.
- Split membership never grows onto `AddressedAtom`/`ParseRun` — it
  lives on the eval set, never on the evidence record it exercises.
- Labelled material stays in-region and private (DEC-MOAT); the SHIPPED
  corpus is synthetic CC0 by construction.
