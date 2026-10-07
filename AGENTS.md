# AGENTS.md

Guidance for AI agents working in this repository.

## Agent Tooling Mandate (opinionated)

This repo ships read-only Ash introspection tooling (`ash_agent_tools`, dev-only dep).
**Every agent session — you, reading this — must consult it BEFORE grepping source.**

- Before calling any Ash action or writing a changeset/query call: run
  `mix ash_agent.validate <Resource> <action> '<json-params>'` — it casts against the
  real contract and reports required/optional/unknown inputs with per-path errors.
- Before asking "what fields/actions/relationships does X have" or grepping a resource:
  `mix ash_agent.describe <Resource> [<action>]` (types, constraints, source locations).
- To find a symbol across the codebase: `mix ash_agent.search <term> [--kind K]`
  before ripgrep. Grep is the fallback, not the default.
- The deterministic iron-laws judge: `mix ash_agent.laws FILE [FILE...]` or
  `git diff main | mix ash_agent.laws - --diff` — it is wired into `mix precommit` and
  CI; treat a non-clean report as work the diff isn't done with.

Facts: stdout is pure JSON (parse it; don't eyeball); first invocation pays mix-boot
(~15s) — batch your questions. If a tool can't answer what you need, fall back to grep.

## Project guidelines

- Use `mix precommit` when you are done with all changes and fix any pending issues
  (compile warnings-as-errors, unlock check, format, iron-laws judge, tests, docs
  validation).
- The package contract ("what it never does") is in the README and `usage-rules.md`;
  it is binding on every change: **no instrument calls** (no HTTP client, no model id,
  no endpoint, no key literal, no Req — OCR/LLM wiring lives with the host;
  `ParseRun` records the seam), no citation narrowing, no decisions.
- **Immutability is the product.** `DocumentVersion` must never grow an update action;
  run transitions stay terminal (`:ok`/`:failed` cannot reopen); new facts about a
  document are new records, never mutations.
- **Atom ids are the packet currency.** `text` and `bbox` are payload class — resolve
  them from the store; downstream surfaces carry ids (`source_ids` is the narrow set
  the instrument client already filtered).
- Fixtures are synthetic. No customer data, contract terms, pricing, or private schema
  detail ever enters this repository.
- Every source file carries its SPDX header; prose/dotfiles are annotated in REUSE.toml.
  `reuse lint` is a CI gate — keep it clean.
- No novelty claims in prose; no product or customer names.

## Tests

- Run: `mix test`. The suite needs a PostgreSQL (env vars `DB_USER`, `DB_PASSWORD`,
  `DB_HOST`/`PGHOST`, `PGPORT`; the test helper creates and migrates its own
  `ash_evidence_test` database on the fly). `SKIP_DB=1 mix test` excludes the
  `:db`-tagged tests.
- On the development host, use the `ash_enterprise` devenv (Postgres 18 + toolchain):

  ```bash
  cd /home/lukegalea/ash_enterprise && devenv shell -- \
    bash -c 'cd /home/lukegalea/ast-forks/ash_evidence && mix test'
  ```

- Schema changes go through `mix ash.codegen <name>` (migrations land in
  `priv/test_repo/migrations`; the test helper applies them). CI checks
  `mix ash.codegen --check` stays clean via the test job's green run on fresh
  migrations — never hand-edit a generated migration's diff shape.
- The iron-laws judge and docs validation are dev-env steps (`ash_agent_tools` and
  `ex_doc` are dev-only): `MIX_ENV=dev mix deps.get` once, then `scripts/iron-laws.sh`
  and `scripts/extra-docs.sh` work standalone.
