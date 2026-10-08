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
  end
end

defmodule AshEvidence.Test.HostAssertion do
  @moduledoc """
  The test host's assertion: the package's fragment on the host's own
  base (plain Postgres here; a real host adds AshEvents, tenancy and
  policies) — exactly the composition shape the Ledger.Fragment pattern
  prescribes. The package never defines the persisted assertion.
  """

  use Ash.Resource,
    domain: AshEvidence.Test.HostDomain,
    data_layer: AshPostgres.DataLayer,
    fragments: [AshEvidence.Assertions.Fragment]

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
