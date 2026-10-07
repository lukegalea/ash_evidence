# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.DocumentVersionTest do
  @moduledoc """
  The DocumentVersion contract: content-addressed, structurally immutable,
  bytes off the public surface.
  """

  use ExUnit.Case, async: true

  alias AshEvidence.DocumentVersion
  alias AshEvidence.Test.Fixtures

  @moduletag :db

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(AshEvidence.Repo)
    :ok
  end

  describe "ingest" do
    test "a version is content-addressed and readable back" do
      bytes = Fixtures.document_bytes(1)

      version =
        Ash.create!(
          DocumentVersion,
          %{kind: "image/png", bytes: bytes, sha256: Fixtures.sha256(bytes)},
          action: :ingest,
          authorize?: false
        )

      assert version.kind == "image/png"
      assert version.sha256 == Fixtures.sha256(bytes)
      assert version.bytes == bytes
      assert %DateTime{} = version.created_at
    end

    test "re-ingesting the same bytes is an identity conflict, not a second row" do
      bytes = Fixtures.document_bytes(2)
      attrs = %{kind: "image/png", bytes: bytes, sha256: Fixtures.sha256(bytes)}

      Ash.create!(DocumentVersion, attrs, action: :ingest, authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(DocumentVersion, attrs, action: :ingest, authorize?: false)
    end

    test "different bytes are different versions, even under one kind" do
      one = Fixtures.ingest_document(3)
      two = Fixtures.ingest_document(4)

      assert one.id != two.id
      assert one.sha256 != two.sha256
    end
  end

  describe "immutability" do
    test "there is no update action to call" do
      action_names =
        DocumentVersion
        |> Ash.Resource.Info.actions()
        |> Enum.map(& &1.name)

      refute :update in action_names
      assert Enum.all?(action_names, &(&1 in [:read, :destroy, :ingest]))
    end

    test "created_at is not writable — the store stamps it" do
      bytes = Fixtures.document_bytes(5)

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 DocumentVersion,
                 %{
                   kind: "image/png",
                   bytes: bytes,
                   sha256: Fixtures.sha256(bytes),
                   created_at: ~U[2000-01-01 00:00:00Z]
                 },
                 action: :ingest,
                 authorize?: false
               )
    end
  end
end
