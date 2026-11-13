# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.WithoutPgvectorTest do
  @moduledoc """
  The migrations run on a server that does not ship pgvector. A host that
  shares a database whose image has no `vector` extension can still migrate:
  the extension and `atom_representations.embedding` are skipped, and
  retrieval is lexical-only.

  The suite's server has pgvector, so the test hides it: a view named
  `pg_available_extensions` without `vector`, in a schema that comes before
  `pg_catalog` on the connection's search path, is what the migration's
  unqualified lookup finds.
  """
  # async: false — creates and drops a scratch database, and points the repo
  # at it through put_dynamic_repo for the duration.
  use ExUnit.Case, async: false

  alias AshEvidence.Test.Fixtures

  @migrations "priv/repo/migrations"

  @moduletag :db

  test "the migrations skip the extension and the embedding column, and lexical retrieval works" do
    config = AshEvidence.Repo.config()
    scratch = Keyword.put(config, :database, "#{config[:database]}_no_pgvector")
    adapter = AshEvidence.Repo.__adapter__()
    _ = adapter.storage_down(scratch)
    :ok = adapter.storage_up(scratch)
    on_exit(fn -> adapter.storage_down(scratch) end)

    {:ok, setup} =
      Postgrex.start_link(Keyword.take(scratch, ~w(hostname port username password database)a))

    Postgrex.query!(setup, "CREATE SCHEMA no_pgvector", [])

    Postgrex.query!(
      setup,
      "CREATE VIEW no_pgvector.pg_available_extensions AS " <>
        "SELECT * FROM pg_catalog.pg_available_extensions WHERE name <> 'vector'",
      []
    )

    GenServer.stop(setup)

    {:ok, repo} =
      AshEvidence.Repo.start_link(
        name: nil,
        database: scratch[:database],
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: [search_path: "public,no_pgvector,pg_catalog"],
        log: false
      )

    previous = AshEvidence.Repo.put_dynamic_repo(repo)

    try do
      assert [_ | _] =
               Ecto.Migrator.run(AshEvidence.Repo, @migrations, :up,
                 all: true,
                 dynamic_repo: repo,
                 log: false
               )

      assert rows("SELECT count(*)::int FROM pg_extension WHERE extname = 'vector'") == [[0]]

      columns =
        for [column] <-
              rows(
                "SELECT column_name::text FROM information_schema.columns " <>
                  "WHERE table_schema = 'public' AND table_name = 'atom_representations'"
              ),
            do: column

      assert "representation" in columns
      refute "embedding" in columns

      version = Fixtures.ingest_document(1)
      run = Fixtures.start_run(version)
      [atom] = Fixtures.seed_atoms(version, run, ["the certificate expires on 2026-05-28"])

      result = AshEvidence.retrieve!(version, "the certificate expires on 2026-05-28")
      assert [%{atom_id: atom_id} | _] = result.by_hypothesis.supports
      assert atom_id == atom.id
      assert result.legs == [:lexical]
    after
      AshEvidence.Repo.put_dynamic_repo(previous)
      Supervisor.stop(repo)
    end
  end

  test "with pgvector available, the extension and the embedding column are there" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    assert rows("SELECT count(*)::int FROM pg_extension WHERE extname = 'vector'") == [[1]]

    assert rows(
             "SELECT data_type::text FROM information_schema.columns " <>
               "WHERE table_name = 'atom_representations' AND column_name = 'embedding'"
           ) == [["USER-DEFINED"]]
  end

  defp rows(sql), do: AshEvidence.Repo.query!(sql).rows
end
