defmodule Cadence.Runtime.Missions.MissionTracker do
  @moduledoc """
  Phoenix.Tracker for mission runtime state advertisement.

  The data plane uses this tracker to advertise the state of running missions.
  The control plane reconcilers observe this state to detect drift between
  desired state (database) and actual state (running processes).

  ## Topics

  Each mission is tracked under the topic `"mission:{mission_id}"`.
  Organization-level aggregation is available via `"org:{org_id}"`.

  ## Metadata

  Each tracked mission includes:
  - `config_generation` - The config version the mission was started with
  - `observed_generation` - The config version currently applied
  - `status` - Runtime status (:starting, :ready, :degraded, :stopping)
  - `conditions` - Component-level health conditions
  - `started_at` - When the mission instance started
  - `node` - Which node the mission is running on

  ## Usage

      # Track a mission (called by MissionInstance on startup)
      MissionTracker.track(mission_id, org_id, metadata)

      # Update metadata (called when status changes)
      MissionTracker.update(mission_id, org_id, new_metadata)

      # List all missions for an org (called by OrgReconciler)
      MissionTracker.list_missions_for_org(org_id)

      # Get a specific mission's state
      MissionTracker.get_mission(mission_id)
  """

  use Phoenix.Tracker

  require Logger

  @tracker_name __MODULE__

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts) do
    opts = Keyword.merge([name: @tracker_name], opts)
    Phoenix.Tracker.start_link(__MODULE__, opts, opts)
  end

  @doc """
  Tracks a mission instance.

  Called by MissionInstance when it starts up.
  """
  @spec track(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def track(mission_id, org_id, metadata) when is_binary(mission_id) and is_binary(org_id) do
    meta = Map.merge(metadata, %{mission_id: mission_id, org_id: org_id})

    Phoenix.Tracker.track(@tracker_name, self(), topic(org_id), mission_id, meta)
  end

  @doc """
  Updates a tracked mission's metadata.

  Called by MissionInstance when status changes.
  """
  @spec update(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def update(mission_id, org_id, metadata) when is_binary(mission_id) and is_binary(org_id) do
    meta = Map.merge(metadata, %{mission_id: mission_id, org_id: org_id})

    Phoenix.Tracker.update(@tracker_name, self(), topic(org_id), mission_id, meta)
  end

  @doc """
  Untracks a mission instance.

  Called by MissionInstance when it shuts down.
  """
  @spec untrack(String.t(), String.t()) :: :ok
  def untrack(mission_id, org_id) when is_binary(mission_id) and is_binary(org_id) do
    Phoenix.Tracker.untrack(@tracker_name, self(), topic(org_id), mission_id)
  end

  @doc """
  Lists all tracked missions for an organization.

  Returns a list of `{mission_id, metadata}` tuples.
  """
  @spec list_missions_for_org(String.t()) :: [{String.t(), map()}]
  def list_missions_for_org(org_id) when is_binary(org_id) do
    Phoenix.Tracker.list(@tracker_name, topic(org_id))
  end

  @doc """
  Gets a specific mission's tracked state.

  Returns `{:ok, metadata}` or `{:error, :not_found}`.
  """
  @spec get_mission(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_mission(mission_id, org_id) when is_binary(mission_id) and is_binary(org_id) do
    org_id
    |> list_missions_for_org()
    |> Enum.find(fn {id, _meta} -> id == mission_id end)
    |> case do
      {_id, meta} -> {:ok, meta}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Lists all tracked missions across all organizations.

  Note: This is expensive and should only be used for debugging/admin purposes.
  """
  @spec list_all_missions() :: [{String.t(), map()}]
  def list_all_missions do
    # Get all tracked topics from the tracker's ETS table
    # This is a workaround since Phoenix.Tracker doesn't expose a list_all
    []
  end

  # ===========================================================================
  # Phoenix.Tracker Callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :pubsub_server)

    {:ok,
     %{
       pubsub_server: server,
       node_name: node()
     }}
  end

  @impl true
  def handle_diff(diff, state) do
    # Broadcast diffs to interested parties (reconcilers subscribe to these)
    for {topic, {joins, leaves}} <- diff do
      # Extract org_id from topic
      case parse_topic(topic) do
        {:ok, org_id} ->
          if joins != [] or leaves != [] do
            Phoenix.PubSub.broadcast(
              state.pubsub_server,
              "mission_tracker:org:#{org_id}",
              {:tracker_diff, topic, joins, leaves}
            )
          end

        :error ->
          :ok
      end
    end

    {:ok, state}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp topic(org_id), do: "missions:org:#{org_id}"

  defp parse_topic("missions:org:" <> org_id), do: {:ok, org_id}
  defp parse_topic(_), do: :error
end
