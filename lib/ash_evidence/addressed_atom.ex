# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.AddressedAtom do
  @moduledoc """
  One addressed atom of a document version: the text span a parse run
  produced, addressed by `seq` within its version (the packet posture —
  "OCR/atoms: the addressed text of the document").

  Atom **ids** are the only thing instrument packets carry; the text and
  geometry resolve from the store, and are deleted with the version in the
  host's erasure linkage (both resources ship `destroy` for exactly that).

  Fields:

    * `text` — the span itself (not public surface: content is payload
      class; ids are the packet currency).
    * `kind` — the layout unit the atom is (`AshEvidence.AtomKind`):
      `:word`, `:line`, `:cell` or `:region`. Required.
    * `page` — the 1-based page the atom is on. `nil` only when the
      instrument's input has no pages.
    * `geometry` — where on that page (`AshEvidence.AtomGeometry`): the
      measured page size and unit, the rotation applied before measuring,
      and the box normalised to `[0, 1]` with a top-left origin. Optional
      — a pass may not yield boxes — but an atom with geometry must name
      its page.
    * `source_ids` — the OTHER atom ids this atom was derived from. The
      enum-narrowing discipline — a citation outside the packet is
      structurally impossible — belongs to the instrument client; this
      field records the narrowed result.

  ## Composite atoms resolve to their parts through `source_ids`

  A `:line` atom's `source_ids` are its `:word` atoms in reading order;
  a `:cell` or `:region` atom's are the words or lines it contains. That
  is the address of a span below its own atom — there are no character
  offsets. An atom derived from others (an extraction citing the atoms it
  read) uses the same field the same way.

  Ported from the slice-0 atom (`AshEnterprise.Evidence.TextAtom`: seq +
  text, `unique_seq_per_blob`, the sorted `for_blob` read). Deltas: atoms
  hang off a parse run (slice-0's OCR was implicit in the blob), and carry
  `source_ids`, `kind`, `page` and `geometry` — which is where retrieval
  and packets hook in.
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "addressed_atoms"
    repo AshEvidence.Repo

    custom_indexes do
      # The lexical retrieval leg: full-text over the atom's own text,
      # expression-indexed so `to_tsvector('english', text) @@ tsquery`
      # scans the GIN instead of the table. The expression must match the
      # retrieval query verbatim (same config, same argument shape).
      index ["(to_tsvector('english', text))"],
        using: "gin",
        name: "addressed_atoms_text_fts_index"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :ingest do
      primary? true

      accept [
        :document_version_id,
        :parse_run_id,
        :seq,
        :text,
        :kind,
        :page,
        :geometry,
        :source_ids
      ]

      validate present(:page) do
        where present(:geometry)
        message "an atom with geometry must name its page"
      end
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

    read :by_ids do
      description "The explanation surface's batch resolution: cited atom ids to content."
      argument :ids, {:array, :uuid}, allow_nil?: false
      filter expr(id in ^arg(:ids))
      prepare build(load: [:id, :seq, :text, :kind, :page, :geometry], sort: [:seq])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :seq, :integer, allow_nil?: false, public?: true

    attribute :text, :string, allow_nil?: false, public?: false

    attribute :kind, AshEvidence.AtomKind, allow_nil?: false, public?: true

    attribute :page, :integer do
      public? true
      constraints min: 1
    end

    attribute :geometry, AshEvidence.AtomGeometry, public?: true

    attribute :source_ids, {:array, :uuid} do
      public? true
      default []
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
