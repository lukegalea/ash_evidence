# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Repo.Migrations.TestHostEventLog do
  @moduledoc """
  The TEST HOST\x27s AshEvents event log, hand-written like the host
  assertion table (it is not a package resource, so `mix ash.codegen`
  never sees it).
  """

  use Ecto.Migration

  def up do
    create table(:test_host_event_log, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:record_id, :uuid, null: false)
      add(:resource, :text, null: false)
      add(:action, :text, null: false)
      add(:action_type, :text, null: false)
      add(:version, :integer, null: false)
      add(:data, :map, null: false)
      add(:changed_attributes, :map)
      add(:metadata, :map)
      add(:actor, :map)
      add(:tenant, :text)
      add(:occurred_at, :utc_datetime_usec, null: false)
    end

    create index(:test_host_event_log, [:record_id])
  end

  def down do
    drop table(:test_host_event_log)
  end
end
