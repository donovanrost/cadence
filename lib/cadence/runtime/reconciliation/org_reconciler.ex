defmodule Cadence.Runtime.Reconciliation.OrgReconciler do
  @moduledoc """
  Reconciles missions for a single organization.

  Each organization gets its own reconciler for tenant isolation.
  A crash in org A's reconciler doesn't affect org B.

  ## Reconciliation Logic

  Every `@reconcile_interval`, this reconciler:
  1. Fetches all missions for the org from the database (desired state)
  2. Gets all running mission states from Phoenix.Tracker (actual state)
  3. For each mission, determines the action needed:
     - Mission should be active but isn't running → start it
     - Mission is running but should be inactive → stop it
     - Mission is running but config changed → reload config
     - Mission is converged → no action

  ## Parallel Reconciliation

  Uses Task.Supervisor for parallel mission reconciliation within the org,
  with configurable concurrency limits to avoid overwhelming the system.

  ## Tracker Diffs (Optimization)

  The reconciler subscribes to Phoenix.Tracker diffs for its org.
  When a diff arrives, it can immediately reconcile affected missions
  rather than waiting for the next periodic cycle. This is an optimization;
  the periodic reconcile ensures correctness even if diffs are missed.
  """

  use GenServer

  require Logger

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Application.Missions.MissionQueries
  alias Cadence.Runtime.Missions.{ConfigManager, MissionInstance}
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Missions.MissionTracker

  @reconcile_interval :timer.seconds(10)
  @max_concurrent_reconciles 5

  defstruct [:org_id, :reconcile_timer]

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts) do
    org_id = Keyword.fetch!(opts, :org_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Cadence.ReconcilerRegistry, org_id}}
    )
  end

  @doc """
  Forces an immediate reconciliation for this org.
  """
  def reconcile_now(org_id) do
    case Registry.lookup(Cadence.ReconcilerRegistry, org_id) do
      [{pid, _}] -> GenServer.call(pid, :reconcile_now)
      [] -> {:error, :not_found}
    end
  end

  # ===========================================================================
  # GenServer Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    org_id = Keyword.fetch!(opts, :org_id)

    Logger.info("OrgReconciler starting for org #{org_id}")

    # Subscribe to tracker diffs for this org's missions
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission_tracker:org:#{org_id}")

    # Immediate first reconcile
    send(self(), :reconcile)

    {:ok, %__MODULE__{org_id: org_id}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    reconcile_all_missions(state.org_id)
    schedule_reconcile()
    {:noreply, state}
  end

  # Tracker diff triggers targeted reconcile (optimization, not required for correctness)
  @impl true
  def handle_info({:tracker_diff, _topic, joins, leaves}, state) do
    mission_ids = extract_mission_ids(joins ++ leaves)

    if mission_ids != [] do
      reconcile_missions(state.org_id, mission_ids)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:reconcile_now, _from, state) do
    reconcile_all_missions(state.org_id)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("OrgReconciler for org #{state.org_id} terminating: #{inspect(reason)}")
    :ok
  end

  # ===========================================================================
  # Private - Reconciliation
  # ===========================================================================

  defp reconcile_all_missions(org_id) do
    mission_ids = fetch_mission_ids(org_id)
    reconcile_missions(org_id, mission_ids)
  end

  defp reconcile_missions(_org_id, []), do: :ok

  defp reconcile_missions(org_id, mission_ids) do
    Task.Supervisor.async_stream_nolink(
      Cadence.ReconcilerTaskSupervisor,
      mission_ids,
      fn mission_id -> reconcile_mission(org_id, mission_id) end,
      max_concurrency: @max_concurrent_reconciles,
      timeout: :timer.seconds(30)
    )
    |> Stream.run()
  end

  defp reconcile_mission(org_id, mission_id) do
    with {:ok, desired} <- get_desired_state(mission_id),
         {:ok, actual} <- get_actual_state(mission_id, org_id) do
      execute_reconciliation(mission_id, desired, actual)
    else
      {:error, :not_found} ->
        # Mission was deleted, ensure it's stopped
        stop_mission_if_running(mission_id, org_id)

      {:error, reason} ->
        Logger.warning("Failed to reconcile mission #{mission_id}: #{inspect(reason)}")
    end
  end

  defp execute_reconciliation(mission_id, desired, actual) do
    case {desired.status, actual} do
      # Mission should be active but isn't running
      {:active, nil} ->
        Logger.info("Starting mission #{mission_id} (desired=active, actual=not_running)")
        start_mission(mission_id)

      # Mission is running but should be inactive
      {status, %{pid: pid}} when status != :active and is_pid(pid) ->
        Logger.info("Stopping mission #{mission_id} (desired=#{status}, actual=running)")
        stop_mission(mission_id)

      # Mission is running but config generation changed
      {:active, %{observed_generation: gen}} when gen != desired.config_generation ->
        Logger.info(
          "Reloading mission #{mission_id} config (observed=#{gen}, desired=#{desired.config_generation})"
        )

        reload_mission(mission_id)

      # Already converged
      _ ->
        :ok
    end
  end

  # ===========================================================================
  # Private - State Fetching
  # ===========================================================================

  defp get_desired_state(mission_id) do
    case MissionQueries.find(mission_id) do
      {:ok, mission} ->
        {:ok,
         %{
           status: mission.status,
           config_generation: mission.config_generation
         }}

      {:error, _} = error ->
        error
    end
  end

  defp get_actual_state(mission_id, org_id) do
    case MissionTracker.get_mission(mission_id, org_id) do
      {:ok, meta} ->
        pid = MissionInstance.whereis(mission_id)

        {:ok,
         %{
           pid: pid,
           observed_generation: meta[:observed_generation] || meta[:config_generation],
           status: meta[:status]
         }}

      {:error, :not_found} ->
        # Check if process exists but isn't tracked yet
        case MissionInstance.whereis(mission_id) do
          nil -> {:ok, nil}
          pid -> {:ok, %{pid: pid, observed_generation: 0, status: :unknown}}
        end
    end
  end

  defp stop_mission_if_running(mission_id, org_id) do
    case get_actual_state(mission_id, org_id) do
      {:ok, %{pid: pid}} when is_pid(pid) ->
        stop_mission(mission_id)

      _ ->
        :ok
    end
  end

  # ===========================================================================
  # Private - Mission Lifecycle
  # ===========================================================================

  defp start_mission(mission_id) do
    with {:ok, config} <- MissionConfig.load(mission_id),
         {:ok, _pid} <- MissionSupervisor.start_mission(config) do
      :ok
    else
      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start mission #{mission_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp stop_mission(mission_id) do
    case MissionSupervisor.stop_mission(mission_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  defp reload_mission(mission_id) do
    with {:ok, config} <- MissionConfig.load(mission_id),
         :ok <- push_config_to_mission(mission_id, config) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to reload mission #{mission_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp push_config_to_mission(mission_id, config) do
    case MissionInstance.whereis(mission_id) do
      nil ->
        {:error, :not_running}

      _pid ->
        ConfigManager.apply_config(mission_id, config)
        :ok
    end
  end

  # ===========================================================================
  # Private - Helpers
  # ===========================================================================

  defp fetch_mission_ids(org_id) do
    MissionQueries.list(org_id)
    |> Enum.map(& &1.id)
  rescue
    e ->
      Logger.error("Failed to fetch mission IDs for org #{org_id}: #{inspect(e)}")
      []
  end

  defp extract_mission_ids(presences) do
    presences
    |> Enum.map(fn {mission_id, _meta} -> mission_id end)
    |> Enum.uniq()
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval)
  end
end
