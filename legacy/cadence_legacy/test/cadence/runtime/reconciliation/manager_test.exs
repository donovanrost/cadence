defmodule Cadence.Runtime.Reconciliation.ManagerTest do
  use Cadence.DataCase, async: false

  import Cadence.OrganizationsFixtures

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Reconciliation.Manager
  alias Cadence.Runtime.Reconciliation.Supervisor, as: ReconciliationSupervisor

  setup_virtual_time()

  setup do
    case Process.whereis(ReconciliationSupervisor) do
      nil -> start_supervised!(ReconciliationSupervisor)
      _pid -> :ok
    end

    :ok
  end

  test "reconciles new organizations on successive virtual time ticks" do
    org1 = organization_fixture()

    :ok = Manager.reconcile_now()

    Cadence.PureCase.assert_eventually(
      fn -> Enum.member?(Manager.list_running_reconcilers(), org1.id) end,
      timeout: 1000
    )

    org2 = organization_fixture()

    refute Enum.member?(Manager.list_running_reconcilers(), org2.id)

    :ok = Time.advance(:timer.seconds(30))

    Cadence.PureCase.assert_eventually(
      fn -> Enum.member?(Manager.list_running_reconcilers(), org2.id) end,
      timeout: 1000
    )

    org3 = organization_fixture()

    refute Enum.member?(Manager.list_running_reconcilers(), org3.id)

    :ok = Time.advance(:timer.seconds(30))

    Cadence.PureCase.assert_eventually(
      fn -> Enum.member?(Manager.list_running_reconcilers(), org3.id) end,
      timeout: 1000
    )
  end
end
