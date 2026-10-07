# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description """
  The evidence pipeline substrate for Ash: immutable document versions,
  instrument parse runs, and the addressed atoms a run produces. This
  package records; it never calls an instrument — OCR/LLM wiring lives with
  the host, and the run row is the seam where it plugs in.
  """

  def project do
    [
      app: :ash_evidence,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      package: package(),
      source_url: "https://github.com/lukegalea/ash_evidence",
      docs: docs(),

      # Non-gating in CI (same posture as ash_judgments, ADR 0007: Dialyzer
      # against Spark-generated shapes produces findings nobody has canonical
      # guidance for; the 1.18+ type checker in `mix compile
      # --warnings-as-errors` is this repository's real static-analysis gate).
      dialyzer: [plt_add_apps: [:mix]]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # No supervision tree: the package owns no processes. The resources ride
  # the host's (or the test helper's) start of `AshEvidence.Repo`; if a
  # process ever becomes genuinely necessary it gets a named child_spec here
  # with a comment saying why.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core: the resources this package ships and their Postgres data
      # layer. Deliberately the WHOLE dependency story — no req, no req_llm,
      # no ash_ai: this package never calls an instrument (the README's
      # "never does" is binding), so the transport stack stays out.
      {:ash, "~> 3.33"},
      {:ash_postgres, "~> 2.13"},
      {:spark, "~> 2.2"},

      # Canonical-JSON helpers for Ash on Postgres. Declared explicitly
      # rather than riding transitively on ash.
      {:jason, "~> 1.4"},

      # Dev-and-test-only: the laws judge (`mix ash_agent.laws`) and the Ash
      # introspection mandate in AGENTS.md ride on ash_agent_tools.
      # runtime: false and the hex package `files:` keep it out of
      # consumers' graphs either way.
      {:ash_agent_tools,
       github: "lukegalea/ash_agent_tools", only: [:dev, :test], runtime: false},

      # Dev hygiene: static analysis (credo with the ash_credo plugin), type
      # checking, docs.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ash_credo, "~> 0.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/lukegalea/ash_evidence",
        "Usage rules" => "https://github.com/lukegalea/ash_evidence/blob/HEAD/usage-rules.md"
      },
      files: ~w(lib mix.exs README.md LICENSE LICENSES usage-rules.md docs .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        [
          "README.md",
          "usage-rules.md"
        ] ++ extra_docs()
    ]
  end

  # EXTRA_DOCS=AGENTS.md mix docs routes standalone agent docs through the
  # extras pipeline so broken refs warn like any other doc. The value is a
  # single Path.wildcard glob; CI sets it (the ex_doc#2272 pattern, same as
  # ash_judgments and ash_agent_tools).
  defp extra_docs do
    if glob = System.get_env("EXTRA_DOCS"), do: Path.wildcard(glob), else: []
  end

  defp aliases do
    [
      # The house pre-commit gate, mirroring ash_judgments'. The iron-laws
      # judge and the docs validation run last and set their own MIX_ENV=dev
      # internally, because ash_agent_tools and ex_doc are dev-only deps.
      # See scripts/iron-laws.sh and scripts/extra-docs.sh.
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "cmd scripts/iron-laws.sh",
        "test",
        "cmd scripts/extra-docs.sh"
      ]
    ]
  end
end
