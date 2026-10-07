# Usage rules

Rules for working with `ash_evidence`, maintained for
[`usage_rules`](https://hex.pm/packages/usage_rules) sync. The package
contract below is binding on every change — in this repository and in
consumers.

## What the package is

The evidence pipeline substrate: immutable document versions (`AshEvidence.DocumentVersion`),
instrument parse runs (`AshEvidence.ParseRun`), and the addressed atoms a pass
produced (`AshEvidence.AddressedAtom`).

## What it never does — do not make it

- **Never call an instrument from this package.** No HTTP client, no Req, no
  model id, no endpoint, no key literal — in source, config or fixtures. The
  host starts a `ParseRun`, does its OCR/LLM work outside, and closes the run.
- **Never narrow citations here.** `AddressedAtom.source_ids` records what the
  instrument client already enum-narrowed to the packet's atom ids. A
  validation here cannot repair an unfiltered reply.
- **Never mutate the record.** No update action on `DocumentVersion` (new
  rendition ⇒ new version); run transitions are terminal (`:pending → :ok` /
  `:pending → :failed`, once); a correction is a new record.
- **Never let text leak into packets.** Atom ids are the packet currency;
  `text`/`bytes`/`bbox` resolve from the store and are payload class
  (`bytes` and `text` are not public surface).
- **Never decide anything.** No thresholds, no policy, no verdicts derived
  from atoms.

## Working with the resources

- Call through the domain code interfaces (`AshEvidence.Domain.ingest_document/3`,
  `start_parse_run/2-3`, `mark_parse_run_ok/1`, `mark_parse_run_failed/1`,
  `ingest_atom/4-5`, `atoms_for_version/1`, `atoms_for_run/1`).
- Compute the SHA-256 at the call site and pass it to `ingest_document` — the
  store records hashes, it does not fabricate them.
- A failed instrument pass is a first-class outcome: close the run `:failed`
  and record honestly; do not leave runs pending or retry them invisibly.
- Point `AshEvidence.Repo` at the host's own database (residency is the
  host's concern); PostgreSQL 18 is the declared floor.
