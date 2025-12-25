defmodule Cadence.Runtime.Reconciliation.Manager do
  @moduledoc """
  Manages OrgReconciler processes using periodic reconciliation.

  Rather than event-driven creation (on org create), we periodically
  reconcile the set of running OrgReconcilers against the set of orgs
  in the database. This provides self-healing and avoids coupling
  org creation to runtime process management.

  ## Reconciliation Pattern

  Every `@reconcile_interval`, this manager:
  1. Fetches all organization IDs from the database
  2. Gets all running OrgReconciler org_ids from the registry
  3. Starts OrgReconcilers for orgs that don't have one
  4. Stops OrgReconcilers for orgs that no longer exist

  This is the same level-triggered pattern used by OrgReconcilers
  for missions - reconcilers all the way down.
  """

  use GenServer

  require Logger

  alias Cadence.Runtime.Reconciliation.OrgReconciler

  @reconcile_interval :timer.seconds(30)

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Forces an immediate reconciliation cycle.

  Useful for testing or after bulk operations.
  """
  def reconcile_now do
    GenServer.call(__MODULE__, :reconcile_now)
  end

  @doc """
  Lists all running OrgReconciler org_ids.
  """
  def list_running_reconcilers do
    Registry.select(Cadence.ReconcilerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    Logger.info("ReconcilerManager starting")

    # Immediate first reconcile on boot
    send(self(), :reconcile)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    reconcile_org_reconcilers()
    schedule_reconcile()
    {:noreply, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    reconcile_org_reconcilers()
    {:reply, :ok, state}
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp reconcile_org_reconcilers do
    desired = fetch_org_ids()
    actual = MapSet.new(list_running_reconcilers())

    # Start missing reconcilers
    to_start = MapSet.difference(desired, actual)

    for org_id <- to_start do
      start_org_reconciler(org_id)
    end

    # Stop orphaned reconcilers (org was deleted)
    to_stop = MapSet.difference(actual, desired)

    for org_id <- to_stop do
      stop_org_reconciler(org_id)
    end

    if MapSet.size(to_start) > 0 or MapSet.size(to_stop) > 0 do
      Logger.info(
        "ReconcilerManager reconciled: started=#{MapSet.size(to_start)}, stopped=#{MapSet.size(to_stop)}"
      )
    end
  end

  defp fetch_org_ids do
    # Fetch all organization IDs from the database
    Cadence.Organizations.list_organizations()
    |> Enum.map(& &1.id)
    |> MapSet.new()
  rescue
    e ->
      Logger.error("Failed to fetch org IDs: #{inspect(e)}")
      MapSet.new()
  end

  defp start_org_reconciler(org_id) do
    spec = {OrgReconciler, org_id: org_id}

    case DynamicSupervisor.start_child(Cadence.OrgReconcilerSupervisor, spec) do
      {:ok, _pid} ->
        Logger.debug("Started OrgReconciler for org #{org_id}")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start OrgReconciler for org #{org_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stop_org_reconciler(org_id) do
    case Registry.lookup(Cadence.ReconcilerRegistry, org_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Cadence.OrgReconcilerSupervisor, pid)
        Logger.debug("Stopped OrgReconciler for org #{org_id}")
        :ok

      [] ->
        :ok
    end
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval)
  end
end
