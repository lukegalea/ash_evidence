# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.ParseRun do
  @moduledoc """
  One instrument pass over one document version — the seam where the
  host's OCR/LLM wiring plugs in.

  The lifecycle is directed and terminal:

      :pending  →  :ok
                →  :failed

  The host `start`s the run (the row exists BEFORE any instrument work),
  calls its instrument outside this package, then closes the run with
  `mark_ok` / `mark_failed`. Closing is a no-input action — the record of
  how a pass ended is not an input anyone can supply — and a closed run
  cannot be closed again (`AshEvidence.Validations.PendingTransition`).
  Instruments failing is a first-class outcome (`:failed`), recorded
  honestly rather than improvised.

  `instrument` is free-form host vocabulary (which member, which pass) and
  `config` pins the declared invocation parameters — enough to reconstruct
  what the pass was, never enough to re-run it from here. No model id,
  endpoint or key literal belongs in either.

  ## Page transforms

  When the instrument rotated or deskewed a page before measuring the
  atoms on it, it records the transform under the `"page_transforms"`
  config key, so a box (`AshEvidence.AtomGeometry`, measured in the
  transformed frame) maps back to the page as stored:

      %{
        "page_transforms" => %{
          "1" => %{"rotation" => 90.0, "deskew" => -0.4}
        }
      }

  Keys are page numbers as strings; `rotation` and `deskew` are degrees,
  clockwise. Their sum is the atoms' `rotation_applied` on that page. A
  page the instrument left as stored has no entry. The package records the
  key and never reads it.

  Ported from the slice-0 observation envelope's discipline
  (`AshEnterprise.Evidence.Observation`): status is an enum, transitions
  are named actions, and the record stays. Deltas: the envelope's
  digest_only machinery (`state_digest`, `record_hash`, `raw` +
  tombstoning) and the shadow/calibration mode gate are NOT ported in this
  ticket — ParseRun is the run row; the observation seam lands with the
  retrieval/packets tickets that need it.

  Deleting a version deletes its runs, by foreign-key cascade.

  A version may carry many runs (slice-0's pipeline made three passes per
  blob — OCR, extraction, verification — and a re-parse is a new pass, so
  there is deliberately no unique identity tying a run to one per
  version).
  """

  use Ash.Resource,
    domain: AshEvidence.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshEvidence.Validations.PendingTransition

  postgres do
    table "parse_runs"
    repo fn _resource, _type -> AshEvidence.repo() end

    references do
      # Erasure linkage: a run dies with its version.
      reference :document_version, on_delete: :delete
    end
  end

  validations do
    validate AshEvidence.Validations.VersionInTenant
  end

  preparations do
    prepare AshEvidence.Preparations.VersionInTenant
  end

  actions do
    defaults [:read]

    create :start do
      primary? true
      accept [:document_version_id, :instrument, :config]
      # `status` is not accepted: a run starts pending, structurally.
    end

    update :mark_ok do
      accept []
      validate PendingTransition
      change set_attribute(:status, :ok)
    end

    update :mark_failed do
      accept []
      validate PendingTransition
      change set_attribute(:status, :failed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :instrument, :string, allow_nil?: false, public?: true

    attribute :config, :map do
      public? true
      default %{}
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :pending
      constraints one_of: [:pending, :ok, :failed]
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
  end
end
