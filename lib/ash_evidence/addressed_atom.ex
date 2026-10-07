# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AddressedAtom do
  @moduledoc """
  One addressed atom of a document version: the text span a parse run
  produced, addressed by `seq` within its version (the packet posture —
  "OCR/atoms: the addressed text of the document").

  Atom **ids** are the only thing instrument packets carry; the text and
  bbox resolve from the store, and are deleted with the version in the
  host's erasure linkage (both resources ship `destroy` for exactly that).

  Fields:

    * `text` — the span itself (not public surface: content is payload
      class; ids are the packet currency).
    * `source_ids` — the OTHER atom ids this atom was derived from (the
      OCR atoms a generative extraction cites). The enum-narrowing
      discipline — a citation outside the packet is structurally
      impossible — belongs to the instrument client; this field records
      the narrowed result.
    * `bbox` — page geometry, when the instrument produced it:
      `{x0, y0, x1, y2}` in pixels, top-left to bottom-right. Optional —
      OCR passes may not yield boxes.

  Ported from the slice-0 atom (`AshEnterprise.Evidence.TextAtom`: seq +
  text, `unique_seq_per_blob`, the sorted `for_blob` read). Deltas: atoms
  hang off a parse run (slice-0's OCR was implicit in the blob), and carry
  `source_ids` + `bbox` (this ticket's brief) — which is where AST-50
  retrieval and AST-51 packets hook in.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "addressed_atoms"
    repo AshEvidence.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :ingest do
      primary? true
      accept [:document_version_id, :parse_run_id, :seq, :text, :source_ids, :bbox]
    end

    read :for_version do
      argument :document_version_id, :uuid, allow_nil?: false
      filter expr(document_version_id == ^arg(:document_version_id))
      prepare build(load: [:id], sort: [:seq])
    end

    read :for_run do
      argument :parse_run_id, :uuid, allow_nil?: false
      filter expr(parse_run_id == ^arg(:parse_run_id))
      prepare build(sort: [:seq])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :seq, :integer, allow_nil?: false, public?: true

    attribute :text, :string, allow_nil?: false, public?: false

    attribute :source_ids, {:array, :uuid} do
      public? true
      default []
    end

    attribute :bbox, :map do
      public? true

      constraints fields: [
                    x0: [type: :float],
                    y0: [type: :float],
                    x1: [type: :float],
                    y2: [type: :float]
                  ]
    end

    attribute :created_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      writable? false
    end
  end

  relationships do
    belongs_to :document_version, AshEvidence.DocumentVersion do
      allow_nil? false
      public? true
    end

    belongs_to :parse_run, AshEvidence.ParseRun do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_seq_per_version, [:document_version_id, :seq]
  end
end
