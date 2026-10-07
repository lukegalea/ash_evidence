# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Test.Fixtures do
  @moduledoc """
  Synthetic fixtures for the suite: a fake document (deterministic bytes,
  not a real certificate), and the seed helpers that mirror the slice-0
  pipeline sequence — version → run → atoms — with NO instrument on the
  path (the atoms are seeded directly; that is the seam this package
  leaves to the host).
  """

  import Ash.Changeset, only: [for_create: 3]

  alias AshEvidence.{AddressedAtom, Domain}

  @doc "Deterministic fake document bytes: the serial is in the content."
  def document_bytes(serial), do: "SYNTH-DOC-#{serial}\n" <> String.duplicate("body ", 64)

  @doc "The lowercase hex SHA-256 the caller computes (the slice-0 discipline)."
  def sha256(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @doc """
  Ingest a synthetic document version via the domain's code interface.
  """
  def ingest_document(serial \\ 1) do
    bytes = document_bytes(serial)
    Domain.ingest_document!("image/png", bytes, sha256(bytes))
  end

  @doc """
  Start a parse run over a version with a synthetic instrument name. No
  model id or endpoint literal ever belongs here — the package pins no
  instrument.
  """
  def start_run(version, opts \\ []) do
    Domain.start_parse_run!(
      version.id,
      Keyword.get(opts, :instrument, "synthetic-test-instrument"),
      Keyword.get(opts, :config, %{})
    )
  end

  @doc """
  Seed atoms directly (no instrument): `lines` become seq-ordered spans of
  the version. Returns them in seq order.
  """
  def seed_atoms(version, run, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {text, seq} ->
      Domain.ingest_atom!(version.id, run.id, seq, text)
    end)
  end

  @doc """
  The changeset form, for tests that exercise `Ash.create` directly rather
  than the domain interfaces.
  """
  def atom_changeset(version, run, seq, text, extra \\ %{}) do
    for_create(
      AddressedAtom,
      :ingest,
      Map.merge(
        %{
          document_version_id: version.id,
          parse_run_id: run.id,
          seq: seq,
          text: text
        },
        extra
      )
    )
  end
end
