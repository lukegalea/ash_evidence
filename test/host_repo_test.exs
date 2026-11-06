# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.HostRepoTest do
  @moduledoc """
  The repo seam: `config :ash_evidence, :repo` points the resources and
  retrieval at the host's repo, so a version and the host's own records
  share one transaction.
  """

  # async: false — flips application environment the resources read on
  # every query.
  use ExUnit.Case, async: false

  alias AshEvidence.Test.{Fixtures, HostRepo}
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :db

  setup do
    Sandbox.checkout(AshEvidence.Repo)
    Sandbox.checkout(HostRepo)

    previous = Application.fetch_env(:ash_evidence, :repo)

    on_exit(fn ->
      case previous do
        {:ok, repo} -> Application.put_env(:ash_evidence, :repo, repo)
        :error -> Application.delete_env(:ash_evidence, :repo)
      end
    end)

    Application.delete_env(:ash_evidence, :repo)
    :ok
  end

  test "the repo defaults to AshEvidence.Repo" do
    assert AshEvidence.repo() == AshEvidence.Repo
  end

  test "versions, runs, atoms and retrieval run on the host's repo, in its transaction" do
    Application.put_env(:ash_evidence, :repo, HostRepo)
    assert AshEvidence.repo() == HostRepo

    result =
      HostRepo.transaction(fn ->
        version = Fixtures.ingest_document(200)
        run = Fixtures.start_run(version)
        Fixtures.seed_atoms(version, run, ["the certificate coverage expires on 2026-05-28"])

        # Retrieval's raw SQL must use the seam too, or it would not see
        # the atoms this open transaction wrote.
        retrieval = AshEvidence.retrieve!(version, "the certificate coverage expires")
        assert [_ | _] = retrieval.candidates

        # A different repo's connection does not see the uncommitted row.
        assert %{rows: [[0]]} =
                 AshEvidence.Repo.query!(
                   "SELECT count(*) FROM document_versions WHERE id = $1",
                   [Ecto.UUID.dump!(version.id)]
                 )

        HostRepo.rollback(version.id)
      end)

    assert {:error, version_id} = result

    assert {:error, _} = AshEvidence.Domain.get_document_version(version_id)
  end
end
