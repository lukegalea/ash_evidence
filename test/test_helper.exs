# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

# The resources are the package itself; make sure the domain and resources
# are loaded before any test runs.
[
  AshEvidence.Domain,
  AshEvidence.DocumentVersion,
  AshEvidence.ParseRun,
  AshEvidence.AddressedAtom,
  AshEvidence.AtomRepresentation,
  AshEvidence.CandidateSet,
  AshEvidence.EvidenceEvaluation,
  AshEvidence.Packet,
  AshEvidence.EvalSet,
  AshEvidence.EvalItem,
  AshEvidence.Test.HostDomain,
  AshEvidence.Test.HostAssertion
]
|> Enum.each(&Code.ensure_loaded!/1)

# The database is created and migrated here, once per test run, so a fresh
# clone needs no setup task; `SKIP_DB=1` excludes the `:db` tests for runs
# without a database. Migrations run outside the sandbox (:auto), and the
# pool is switched to manual ownership afterwards. (Same shape as
# ash_judgments' test_helper.exs.)
#
# Order matters: storage_up runs BEFORE the repo starts. The sandbox pool
# opens its connections eagerly at start_link, so starting first on a fresh
# environment sprays a wall of `FATAL 3D000 database ... does not exist`
# errors before the create lands.
db_tests? =
  if Application.get_env(:ash_evidence, :db_tests_enabled?, true) do
    case AshEvidence.Repo.__adapter__().storage_up(AshEvidence.Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
    end

    {:ok, _} = AshEvidence.Repo.start_link()

    Ecto.Adapters.SQL.Sandbox.mode(AshEvidence.Repo, :auto)
    Ecto.Migrator.run(AshEvidence.Repo, "priv/test_repo/migrations", :up, all: true)
    Ecto.Adapters.SQL.Sandbox.mode(AshEvidence.Repo, :manual)
    true
  else
    false
  end

ExUnit.start()

ExUnit.configure(exclude: if(db_tests?, do: [], else: [:db]))

unless db_tests? do
  IO.puts("note: SKIP_DB — excluding the database tests (:db tag)")
end
