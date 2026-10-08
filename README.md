# AshEvidence

**The evidence pipeline substrate for Ash: immutable document versions, instrument
parse runs, and the addressed atoms a pass produces.**

A document enters the pipeline as an immutable, content-hashed version. An instrument
pass over that version is a *run row* that starts `:pending` and closes once — `:ok`
or `:failed`. What the pass produced lands as *addressed atoms*: text spans at a
sequence within the version, carrying the atom ids they cite and their page geometry.
Atom **ids** are the only thing downstream packets carry; text and bbox resolve from
the store.

On top of that substrate, **retrieval** finds candidates for a claim: hybrid (lexical
full-text over the atoms' own text + vector cosine over host-supplied embeddings),
run under competing hypotheses (`:supports` / `:contradicts`, `:exception` opt-in) so
adjudication receives contrastive candidate sets, not a flat list. The host embeds —
the package records and scores; it never calls a model. Each retrieval can persist a
`CandidateSet`: the hashes, index versions and ranked ids that prove what was
searched.

## The contract

**This package records; it never calls an instrument.** There is no HTTP client, no
model id, no endpoint, no key literal, no Req in this codebase. OCR/LLM wiring lives
with the host; `AshEvidence.ParseRun` is the seam where it plugs in — start the run,
do the pass outside, close the run. It also never narrows citations (the
`source_ids`-narrowing discipline belongs to the instrument client — this package
stores the narrowed result) and never decides anything (no thresholds, no policy, no
verdicts).

## The resources

| Resource | Contract |
|---|---|
| `AshEvidence.DocumentVersion` | The immutable bytes of one document + SHA-256. **No update action exists** — a new rendition is a new version. Content-addressed (`unique_content` on the hash); `bytes` is not public surface. |
| `AshEvidence.ParseRun` | One instrument pass over a version. Directed, terminal lifecycle: `:pending → :ok` / `:pending → :failed`; the close actions take **no inputs** and a closed run cannot be re-closed. A version may carry many runs (OCR pass, extraction pass, re-parse). `instrument` + `config` pin what the pass was. |
| `AshEvidence.AddressedAtom` | A text span at `seq` within its version (`unique_seq_per_version`), produced by a run, with `source_ids` (the other atoms it derives from) and optional `bbox` (`{x0, y0, x1, y2}`, pixels). Sorted `for_version` / `for_run` reads. Its `text` carries the lexical retrieval leg (`to_tsvector`, GIN-indexed). |
| `AshEvidence.AtomRepresentation` | The **replaceable projection** of one atom — what the vector leg scores. One per atom (`unique_atom`); `representation` is the text the host chose to project, `embedding` the vector its model produced (`embedding_model` + `embedding_model_version` recorded). Re-projecting voids the stale embedding. The column is a dimensionless pgvector `vector`: dimensionality is the host model's business; exact cosine scan keeps retrieval deterministic, and a host wanting ANN adds an `hnsw` index host-side. |
| `AshEvidence.CandidateSet` | The durable proof of ONE retrieval: claim + query text **hashes** (never the text itself), lexical config, embedding model + version, k, and the ranked id-shaped candidates. Immutable by action shape; cascades away with its version. |

Domain surface (`AshEvidence.Domain`): `ingest_document/3`,
`start_parse_run/2-3`, `mark_parse_run_ok/1`, `mark_parse_run_failed/1`,
`ingest_atom/4-5`, `atoms_for_version/1`, `atoms_for_run/1`,
`project_atom/3`, `record_embedding/4`, `representations_for_version/1`,
`record_candidate_set/1`, `get_candidate_set/1`.

Retrieval surface (`AshEvidence.retrieve/3`, `retrieve!/3` — the engine is
`AshEvidence.Retrieval`):

```elixir
{:ok, result} =
  AshEvidence.retrieve(version, "the certificate expires on 2026-05-28",
    hypotheses: [:supports, :contradicts, :exception],
    vector: claim_embedding,              # the host's embedder ran outside
    embedding_model: "host-embedder",
    k: 10,
    persist?: true                        # record the CandidateSet proof
  )

result.by_hypothesis.contradicts   # contrastive set, fused-ranked
result.candidates                  # merged ranked list; each candidate
                                   # carries score, hypotheses, per-leg ranks
```

## Provenance

The shapes are ported from the slice-0 private pipeline
(`ash_enterprise` VPM proof-of-concept, `AshEnterprise.Evidence`):

- `Blob` → `DocumentVersion` (bytes + sha256, immutable by action shape) — deltas:
  slice-0's `subject_ref` and zone data-class/residency machinery are host posture,
  not pipeline; content addressing replaces subject-scoped uniqueness.
- `TextAtom` → `AddressedAtom` (seq + text, `unique_seq_per_version`, sorted read) —
  deltas: atoms hang off a run, and carry `source_ids` + `bbox`.
- `Observation` → partially `ParseRun` (enum status, named no-input transitions,
  honest failure) — deltas: the envelope's digest-only machinery (`state_digest`,
  `record_hash`, `raw` + tombstoning) and the shadow/calibration mode gate are NOT
  here; they land with the tickets that need them.
- The rungs' discipline (`source_ids` narrowed per call, cited-atoms-only verify
  states, 1,024-token states) stays with the host's instrument client — by contract.

## Seams: what the later tickets hang off

- **AST-50 (retrieval)** — built on this base: the lexical leg scores the
  atoms' text (`addressed_atoms_text_fts_index`, the expression must
  match the engine's query verbatim); the vector leg scores
  `AtomRepresentation` embeddings the host recorded. Deterministic by
  construction (fixed framing queries, deterministic SQL ordering,
  reciprocal-rank fusion, exact scan). `queries:` overrides are the seam
  for model-written counter-hypothesis queries; `CandidateSet` is the
  proof a packet cites. Out of scope here: reranking with a model, the
  brute-force sweep, adjudication.
- **AST-51 (packets)** carries **atom ids only**. The packet builder reads id, seq
  and text here; anything a packet must not carry (document bytes, text beyond the
  cited set) stays unexposed on these resources — and a persisted
  `CandidateSet` proves what the packet's candidates were searched against.
- **The observation envelope** (digest-only state, `record_hash`, payload
  tombstoning, shadow/calibration mode gate) is the proven slice-0 shape to port when
  run outcomes need tamper-evidence — `ParseRun` deliberately did not grow it in this
  ticket.
- **Eval sets** (later): the clinic-demo format — items with `optimise` /
  `calibration` / `test` splits, split-before-labelling, immutable splits, the draw
  recorded beside the items (`splits.json`), audit split drawn from production only —
  lands as its own resource/docs pair here, versioned against the document versions
  it exercises. See `docs/eval-sets.md`.

## Installation

```elixir
def deps do
  [
    {:ash_evidence, github: "lukegalea/ash_evidence"}
  ]
end
```

The resources are package-owned and name `AshEvidence.Repo`; the host owns the
database — point the repo at it (`config :ash_evidence, AshEvidence.Repo, ...`,
including `priv:` for migrations and `types:` for the pgvector encode/decode) and
add `AshEvidence.Domain` to your `config :ash, ash_domains`. PostgreSQL 18 is the
declared floor (`min_pg_version/0`); `btree_gist`, `uuid-ossp`, `citext`,
`ash-functions` and `vector` (pgvector) are the installed extensions.

## Development

Any PostgreSQL 18 works. The suite reads the usual env vars (`DB_USER`, `DB_PASSWORD`,
`DB_HOST` falling back to `PGHOST`, `PGPORT`), creates and migrates its own
`ash_evidence_test` database on the fly, and runs DB tests under the `:db` tag —
`SKIP_DB=1 mix test` excludes them for runs without a database.

On the programme's development host, the `ash_enterprise` devenv provides Postgres
18.4 and the Elixir toolchain, so the suite runs as:

```bash
cd /home/lukegalea/ash_enterprise && devenv shell -- \
  bash -c 'cd /home/lukegalea/ast-forks/ash_evidence && mix test'
```

The house pre-commit gate is `mix precommit` (compile with warnings as errors, unlock
check, format, the iron-laws judge, tests, docs validation).

## Licence

MIT — see [LICENSE](LICENSES/MIT.txt). REUSE-compliant from day one: every source file
carries its SPDX header, everything else is annotated in [REUSE.toml](REUSE.toml).
