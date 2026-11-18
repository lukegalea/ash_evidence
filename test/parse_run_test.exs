# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.ParseRunTest do
  @moduledoc """
  The ParseRun contract: starts pending, closes once (`:ok` / `:failed`
  are terminal), no-input transitions, and the version it hangs off.
  """

  use ExUnit.Case, async: true

  require Ash.Query

  alias AshEvidence.{Domain, ParseRun}
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    version = Fixtures.ingest_document(1)
    {:ok, version: version}
  end

  describe "start" do
    test "a run starts pending", %{version: version} do
      run = Fixtures.start_run(version)

      assert run.status == :pending
      assert run.instrument == "synthetic-test-instrument"
      assert run.config == %{}
      assert run.document_version_id == version.id
      assert %DateTime{} = run.created_at
    end

    test "status is not an input — a run cannot start pre-closed", %{version: version} do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 ParseRun,
                 %{document_version_id: version.id, instrument: "x", status: :ok},
                 action: :start,
                 authorize?: false
               )
    end

    test "a version may carry many runs (re-parse is a new pass)", %{version: version} do
      first = Fixtures.start_run(version, instrument: "pass-one")
      second = Fixtures.start_run(version, instrument: "pass-two")

      assert first.id != second.id
      assert second.document_version_id == version.id
    end

    test "the version reference is required" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 ParseRun,
                 %{instrument: "x"},
                 action: :start,
                 authorize?: false
               )
    end
  end

  describe "close" do
    test "mark_ok closes a pending run", %{version: version} do
      run = Fixtures.start_run(version)

      assert {:ok, closed} = Ash.update(run, %{}, action: :mark_ok, authorize?: false)
      assert closed.status == :ok
    end

    test "mark_failed closes a pending run", %{version: version} do
      run = Fixtures.start_run(version)

      assert {:ok, closed} = Ash.update(run, %{}, action: :mark_failed, authorize?: false)
      assert closed.status == :failed
    end

    test "a closed run cannot be re-closed — ok then failed is refused", %{version: version} do
      run = Fixtures.start_run(version)
      {:ok, run} = Ash.update(run, %{}, action: :mark_failed, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(run, %{}, action: :mark_ok, authorize?: false)
    end

    test "a closed run cannot be re-closed — ok twice is refused", %{version: version} do
      run = Fixtures.start_run(version)
      {:ok, run} = Ash.update(run, %{}, action: :mark_ok, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(run, %{}, action: :mark_ok, authorize?: false)
    end

    test "the close actions accept no inputs — status is never caller-supplied",
         %{version: version} do
      Fixtures.start_run(version)

      for action <- [:mark_ok, :mark_failed] do
        action_def = Ash.Resource.Info.action(ParseRun, action)
        assert action_def.accept == []
      end
    end
  end

  describe "record_check" do
    defp runs_for(version) do
      ParseRun
      |> Ash.Query.filter(document_version_id == ^version.id)
      |> Ash.read!(authorize?: false)
    end

    test "a passed check is one run, already closed :ok", %{version: version} do
      config = %{"checked" => 3, "problems" => []}

      assert {:ok, run} = Domain.record_check(version.id, "synthetic-check", config, true)

      assert run.status == :ok
      assert run.instrument == "synthetic-check"
      assert run.config == config
      assert run.document_version_id == version.id
      assert [%{id: id, status: :ok}] = runs_for(version)
      assert id == run.id
    end

    test "a failed check is one run, already closed :failed", %{version: version} do
      assert {:ok, run} =
               Domain.record_check(version.id, "synthetic-check", %{"problems" => ["x"]}, false)

      assert run.status == :failed
      assert [%{status: :failed}] = runs_for(version)
    end

    test "an errored or unmeasured check is never recorded as passed", %{version: version} do
      # The outcomes a caller might hold for a check that did not pass cleanly: none is a
      # boolean, so none is coerced into a pass, and nothing is written for any of them.
      for outcome <- [nil, :errored, :unmeasured, "unmeasured", %{}, "maybe"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Domain.record_check(version.id, "synthetic-check", %{}, outcome)
      end

      assert runs_for(version) == []

      # Recorded honestly instead, it is a failure.
      assert {:ok, %{status: :failed}} =
               Domain.record_check(
                 version.id,
                 "synthetic-check",
                 %{"outcome" => "unmeasured"},
                 false
               )

      refute Enum.any?(runs_for(version), &(&1.status == :ok))
    end

    test "status is not an input", %{version: version} do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 ParseRun,
                 %{
                   document_version_id: version.id,
                   instrument: "x",
                   status: :ok,
                   passed?: false
                 },
                 action: :record_check,
                 authorize?: false
               )

      assert runs_for(version) == []
    end

    test "a recorded check is terminal", %{version: version} do
      {:ok, failed} = Domain.record_check(version.id, "synthetic-check", %{}, false)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(failed, %{}, action: :mark_ok, authorize?: false)

      {:ok, passed} = Domain.record_check(version.id, "synthetic-check", %{}, true)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(passed, %{}, action: :mark_failed, authorize?: false)
    end

    test "the version reference is required" do
      assert {:error, %Ash.Error.Invalid{}} =
               Domain.record_check(nil, "synthetic-check", %{}, true)
    end
  end
end
