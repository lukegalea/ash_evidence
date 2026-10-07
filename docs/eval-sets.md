# Eval sets (seam note — later ticket)

This is a place-holder seam, not shipped code: the eval-set format and the
§6 split discipline are a later ticket. This note records where they land
and the proven format they port.

## The proven format (clinic-demo)

The clinic-demo's eval-set machinery (`lib/clinic_demo/eval_sets/`) is the
shape to port:

- **Four splits**: `optimise`, `calibration`, `test` — drawn randomly —
  plus `audit`, which is *never drawn*: audit rows arrive from production
  and carry their own explicit `split` field, honoured verbatim.
- **Split before labelling**, where possible, so no split's items leak into
  another split's labelling.
- **Moving a row between splits is prohibited.** A re-split is a NEW
  eval-set version; the old one stands untouched.
- **The draw is recorded beside the items** (`splits.json`), with its seed
  and provenance, so any split assignment is reconstructible.

## Where it lands here

- A versioned eval-set resource keyed against the `AshEvidence.DocumentVersion`s
  it exercises (a version's atoms give retrieval and packets their
  ground-truth spans).
- Split assignment as immutable, recorded data — the same immutability
  posture as `DocumentVersion`: a correction is a new eval-set version.
- The consumers are the retrieval ticket (AST-50) and the packets ticket
  (AST-51); the calibration lane (the clinic-demo's §6) consumes the same
  rows for band-table evidence.

Until that ticket lands, do not grow `AddressedAtom`/`ParseRun` to carry
eval-set state — split membership belongs to the eval set, never to the
evidence record it exercises.
