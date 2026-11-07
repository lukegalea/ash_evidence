# SPDX-FileCopyrightText: 2026 ash_evidence contributors <https://github.com/lukegalea/ash_evidence>
#
# SPDX-License-Identifier: MIT

defmodule AshEvidence.Test.HostDomain do
  @moduledoc """
  The test host's own domain — the assertion resource the host defines
  on its platform base does not belong to the package's domain.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshEvidence.Test.HostAssertion

    resource AshEvidence.Test.HostEventLog
  end
end

defmodule AshEvidence.Test.HostEventLog do
  @moduledoc """
  The test host's AshEvents event log: every assertion write lands here,
  which is what lets the replay test rebuild the row from its event.
  """

  use Ash.Resource,
    domain: AshEvidence.Test.HostDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.EventLog]

  event_log do
    clear_records_for_replay(AshEvidence.Test.ClearHostAssertions)
    primary_key_type(Ash.Type.UUIDv7)
  end

  actions do
    read :read do
      # Replay streams the log; keyset pagination is required.
      primary?(true)
      pagination(keyset?: true, required?: false)
    end
  end

  postgres do
    table "test_host_event_log"
    repo AshEvidence.Repo
  end
end

defmodule AshEvidence.Test.ClearHostAssertions do
  @moduledoc false
  # Clears the event-tracked table before a replay. Test-only; speaks to
  # the repo directly because the resource it clears is the very thing
  # being replayed.
  use AshEvents.ClearRecordsForReplay

  @impl true
  def clear_records!(_opts) do
    AshEvidence.Repo.query!("DELETE FROM test_host_assertions", [])
    :ok
  end
end

defmodule AshEvidence.Test.HostAssertion do
  @moduledoc """
  The test host's assertion: the package's fragment on the host's own
  base (Postgres + AshEvents audit here; a real host adds tenancy and
  policies) — exactly the composition shape the Ledger.Fragment pattern
  prescribes. The package never defines the persisted assertion.
  """

  use Ash.Resource,
    domain: AshEvidence.Test.HostDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshEvents.Events],
    fragments: [AshEvidence.Assertions.Fragment]

  events do
    event_log(AshEvidence.Test.HostEventLog)
    create_timestamp :created_at
  end

  postgres do
    table "test_host_assertions"
    repo AshEvidence.Repo
  end

  actions do
    read :by_subject do
      argument :subject_type, :string, allow_nil?: false
      argument :subject_id, :string, allow_nil?: false
      filter expr(subject[:type] == ^arg(:subject_type) and subject[:id] == ^arg(:subject_id))
    end
  end
end
