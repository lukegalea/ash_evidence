# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.RepoPrefixTest do
  @moduledoc """
  The schema the evidence tables live in is the host's: `default_prefix:`
  under the repo config, `"public"` when unset, and nothing in the shipped
  migrations names a schema literally. A host that names one gets every
  table, foreign key and migration version there, and reads and writes it
  there.
  """
  # async: false — flips the repo's application environment, which the
  # migrator and `AshEvidence.Repo.config/0` read.
  use ExUnit.Case, async: false

  alias AshEvidence.Domain
  alias AshEvidence.Test.Fixtures

  @migrations "priv/repo/migrations"
  @schema "host_owned"

  setup do
    config = Application.get_env(:ash_evidence, AshEvidence.Repo, [])
    on_exit(fn -> Application.put_env(:ash_evidence, AshEvidence.Repo, config) end)
    %{config: config}
  end

  test "the schema is public unless the host names one", %{config: config} do
    Application.put_env(:ash_evidence, AshEvidence.Repo, Keyword.delete(config, :default_prefix))
    assert AshEvidence.Repo.default_prefix() == "public"
    assert AshEvidence.Repo.config()[:default_prefix] == "public"

    Application.put_env(
      :ash_evidence,
      AshEvidence.Repo,
      Keyword.put(config, :default_prefix, "host")
    )

    assert AshEvidence.Repo.default_prefix() == "host"
    # `AshPostgres.Repo.init/2` writes default_prefix/0's answer into the
    # runtime config, so the configured schema survives it.
    assert AshEvidence.Repo.config()[:default_prefix] == "host"
  end

  test "no shipped migration names a schema: foreign keys resolve with prefix()" do
    literal =
      for file <- Path.wildcard(Path.join(@migrations, "*.exs")),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          line =~ ~r/prefix: "|"public"\./,
          do: "#{Path.basename(file)}:#{number}: #{String.trim(line)}"

    assert literal == []
  end

  @tag :db
  test "a host schema holds the tables, their foreign keys and history, and the data",
       %{config: config} do
    scratch = Keyword.put(AshEvidence.Repo.config(), :database, "#{config[:database]}_prefix")
    adapter = AshEvidence.Repo.__adapter__()
    _ = adapter.storage_down(scratch)
    :ok = adapter.storage_up(scratch)
    on_exit(fn -> adapter.storage_down(scratch) end)

    Application.put_env(
      :ash_evidence,
      AshEvidence.Repo,
      Keyword.merge(config, default_prefix: @schema, migration_default_prefix: @schema)
    )

    {:ok, repo} =
      AshEvidence.Repo.start_link(
        name: nil,
        database: scratch[:database],
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: [search_path: "#{@schema},public"],
        log: false
      )

    previous = AshEvidence.Repo.put_dynamic_repo(repo)

    try do
      AshEvidence.Repo.query!(~s(CREATE SCHEMA "#{@schema}"))

      assert [_ | _] =
               Ecto.Migrator.run(AshEvidence.Repo, @migrations, :up,
                 all: true,
                 dynamic_repo: repo,
                 log: false
               )

      assert [[0]] = query(outside_sql())

      tables = for [table] <- query(tables_sql()), do: table
      assert "schema_migrations" in tables
      assert Enum.all?(~w(document_versions parse_runs addressed_atoms), &(&1 in tables))

      assert [[0]] = query(crossing_sql())

      version = Fixtures.ingest_document(1)
      run = Fixtures.start_run(version)
      [atom] = Fixtures.seed_atoms(version, run, ["held in the host's schema"])

      assert Domain.get_document_version!(version.id).id == version.id

      assert [[1]] =
               AshEvidence.Repo.query!(
                 ~s|SELECT count(*) FROM "#{@schema}".addressed_atoms WHERE id = $1|,
                 [Ecto.UUID.dump!(atom.id)]
               ).rows
    after
      AshEvidence.Repo.put_dynamic_repo(previous)
      Supervisor.stop(repo)
    end
  end

  defp query(sql), do: AshEvidence.Repo.query!(sql, [@schema]).rows

  defp outside_sql,
    do:
      "SELECT count(*)::int FROM pg_tables " <>
        "WHERE schemaname NOT IN ($1, 'pg_catalog', 'information_schema')"

  defp tables_sql, do: "SELECT tablename::text FROM pg_tables WHERE schemaname = $1 ORDER BY 1"

  # Foreign keys from the host schema into any other schema.
  defp crossing_sql do
    """
    SELECT count(*)::int FROM pg_constraint c
      JOIN pg_class r ON r.oid = c.confrelid JOIN pg_namespace rn ON rn.oid = r.relnamespace
      JOIN pg_namespace n ON n.oid = c.connamespace
     WHERE c.contype = 'f' AND n.nspname = $1 AND rn.nspname <> $1
    """
  end
end
