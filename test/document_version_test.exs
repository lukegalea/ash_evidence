# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.DocumentVersionTest do
  @moduledoc """
  The DocumentVersion contract: content-addressed, structurally immutable,
  bytes off the public surface.
  """

  use ExUnit.Case, async: true

  require Ash.Query

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

  describe "tenants" do
    defp ingest(bytes, tenant) do
      opts = [action: :ingest, authorize?: false] ++ if(tenant, do: [tenant: tenant], else: [])

      Ash.create(
        DocumentVersion,
        %{kind: "image/png", bytes: bytes, sha256: Fixtures.sha256(bytes)},
        opts
      )
    end

    test "the same bytes in two tenants are two rows" do
      bytes = Fixtures.document_bytes(10)
      a = ingest(bytes, "a") |> elem(1)
      b = ingest(bytes, "b") |> elem(1)

      assert a.id != b.id
      assert a.tenant == "a"
      assert b.tenant == "b"
    end

    test "the same bytes twice in one tenant is an identity conflict; an upsert returns the same row" do
      bytes = Fixtures.document_bytes(11)
      {:ok, first} = ingest(bytes, "a")

      assert {:error, %Ash.Error.Invalid{}} = ingest(bytes, "a")

      upserted =
        Ash.create!(
          DocumentVersion,
          %{kind: "image/png", bytes: bytes, sha256: Fixtures.sha256(bytes)},
          action: :ingest,
          tenant: "a",
          upsert?: true,
          upsert_identity: :unique_content,
          upsert_fields: [:kind],
          authorize?: false
        )

      assert upserted.id == first.id
    end

    test "untenanted re-ingest of the same bytes is still a conflict (nulls not distinct)" do
      bytes = Fixtures.document_bytes(12)
      assert {:ok, _} = ingest(bytes, nil)
      assert {:error, %Ash.Error.Invalid{}} = ingest(bytes, nil)
    end

    test "an untenanted row and a tenanted row with the same bytes coexist" do
      bytes = Fixtures.document_bytes(13)
      {:ok, plain} = ingest(bytes, nil)
      {:ok, tenanted} = ingest(bytes, "a")

      assert plain.id != tenanted.id
      assert plain.tenant == nil
    end

    test "a tenanted read sees only its tenant; an untenanted read sees every tenant" do
      bytes = Fixtures.document_bytes(14)
      {:ok, a} = ingest(bytes, "a")
      {:ok, b} = ingest(bytes, "b")

      assert {:error, _} = Ash.get(DocumentVersion, a.id, tenant: "b", authorize?: false)
      assert {:ok, %{id: id}} = Ash.get(DocumentVersion, a.id, tenant: "a", authorize?: false)
      assert id == a.id

      # `global? true`: no tenant means unscoped.
      assert {:ok, _} = Ash.get(DocumentVersion, a.id, authorize?: false)
      assert {:ok, _} = Ash.get(DocumentVersion, b.id, authorize?: false)
    end

    test "destroy_document_version with the wrong tenant destroys nothing; the right tenant destroys the row" do
      bytes = Fixtures.document_bytes(15)
      {:ok, a} = ingest(bytes, "a")

      assert {:error, _} =
               AshEvidence.Domain.destroy_document_version(a.id, tenant: "b", authorize?: false)

      assert {:ok, _} = Ash.get(DocumentVersion, a.id, tenant: "a", authorize?: false)

      assert :ok =
               AshEvidence.Domain.destroy_document_version(a.id, tenant: "a", authorize?: false)

      assert {:error, _} = Ash.get(DocumentVersion, a.id, tenant: "a", authorize?: false)

      # A second destroy is an error value, never a crash.
      assert {:error, _} =
               AshEvidence.Domain.destroy_document_version(a.id, tenant: "a", authorize?: false)

      # A wrong-tenant bulk destroy of a live row leaves it standing.
      {:ok, b} = ingest(Fixtures.document_bytes(16), "a")

      DocumentVersion
      |> Ash.Query.filter(id == ^b.id)
      |> Ash.bulk_destroy(:destroy, %{},
        tenant: "b",
        authorize?: false,
        strategy: :atomic,
        return_errors?: true
      )

      assert {:ok, _} = Ash.get(DocumentVersion, b.id, tenant: "a", authorize?: false)
    end

    test "an untenanted upsert on :unique_content returns the same row" do
      bytes = Fixtures.document_bytes(17)
      {:ok, first} = ingest(bytes, nil)

      upserted =
        Ash.create!(
          DocumentVersion,
          %{kind: "image/png", bytes: bytes, sha256: Fixtures.sha256(bytes)},
          action: :ingest,
          upsert?: true,
          upsert_identity: :unique_content,
          upsert_fields: [:kind],
          authorize?: false
        )

      assert upserted.id == first.id
    end

    test "child writes and reads are scoped through the version's tenant" do
      {:ok, a} = ingest(Fixtures.document_bytes(18), "a")

      assert {:error, %Ash.Error.Invalid{}} =
               AshEvidence.Domain.start_parse_run(a.id, "x", %{}, tenant: "b")

      assert {:ok, run} = AshEvidence.Domain.start_parse_run(a.id, "x", %{}, tenant: "a")

      assert {:error, %Ash.Error.Invalid{}} =
               AshEvidence.Domain.ingest_atom(a.id, run.id, 1, "t", :line, tenant: "b")

      assert {:ok, atom} =
               AshEvidence.Domain.ingest_atom(a.id, run.id, 1, "t", :line, tenant: "a")

      assert [] = AshEvidence.Domain.atoms_for_version!(a.id, tenant: "b")
      assert [] = AshEvidence.Domain.atoms_for_run!(run.id, tenant: "b")
      assert [] = AshEvidence.Domain.atoms_by_ids!([atom.id], tenant: "b")
      assert [_] = AshEvidence.Domain.atoms_for_version!(a.id, tenant: "a")
      assert [_] = AshEvidence.Domain.atoms_for_version!(a.id)

      assert {:error, :document_version_not_found} =
               AshEvidence.retrieve(a.id, "claim", tenant: "b")

      assert {:ok, _} = AshEvidence.retrieve(a.id, "claim", tenant: "a")
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
