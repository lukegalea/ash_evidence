# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence do
  @moduledoc """
  The evidence pipeline substrate for Ash.

  A document's life in the pipeline is three records:

    * `AshEvidence.DocumentVersion` — the immutable bytes of one document,
      content-hashed. Immutability is structural: there is no update
      action to call.
    * `AshEvidence.ParseRun` — one instrument pass over a version. The row
      is the *seam*: the host starts it (`:pending`), does its OCR/LLM work
      OUTSIDE this package, and closes it (`:ok` / `:failed`). A run
      neither hides nor implies an instrument call — recording is this
      package's whole job.
    * `AshEvidence.AddressedAtom` — one addressed atom a run produced:
      a text span at a sequence within its version, with the `source_ids`
      it cites and its `bbox`. **Atom ids are the only thing downstream
      packets carry** (the packet discipline) — text and bbox resolve from
      the store.

  ## What this package never does

  - **It never calls an instrument.** No HTTP client, no model id, no
    endpoint, no key literal, no Req — OCR/LLM wiring lives with the host;
    `ParseRun` records that a pass happened and how it ended.
  - **It never narrows citations.** The `source_ids`-narrowing discipline
    (a reply cannot cite an atom outside the packet) belongs to the
    instrument client; this package stores the narrowed result.
  - **It never decides anything.** No thresholds, no policy, no verdicts
    derived from atoms — retrieval and packets (the consumers) read;
    hosts decide.

  ## Retrieval

  `retrieve/3` (and `retrieve!/3`) is the retrieval seam: hybrid lexical +
  vector search over one version's atoms, run under competing hypotheses
  (`:supports` / `:contradicts`, optionally `:exception`), returning
  ranked candidates with scores and hypothesis labels. The host embeds —
  pass the claim's embedding via `:vector` and it is scored against the
  version's `AtomRepresentation` projections; without it, lexical-only.
  See `AshEvidence.Retrieval`.

  See the README for the seams the later tickets hang off and
  `usage-rules.md` for the rules that sync into a consumer's AGENTS.md.
  """

  alias AshEvidence.Retrieval

  @doc """
  Retrieve candidates for `claim` over `version`'s addressed atoms —
  hybrid (lexical + vector when an embedding is supplied), dual-hypothesis
  (`:supports` / `:contradicts` by default, `:exception` opt-in). See
  `AshEvidence.Retrieval.retrieve/3` for the options.
  """
  def retrieve(version_or_id, claim, opts \\ []),
    do: Retrieval.retrieve(version_or_id, claim, opts)

  @doc "Raising `retrieve/3`."
  def retrieve!(version_or_id, claim, opts \\ []),
    do: Retrieval.retrieve!(version_or_id, claim, opts)
end
