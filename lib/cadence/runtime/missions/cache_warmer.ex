defmodule Cadence.Runtime.Missions.CacheWarmer do
  @moduledoc """
  Pre-warms Data Plane caches at mission startup.

  This GenServer runs after the supervision tree is started and triggers eager
  loading of caches that would otherwise be lazily loaded. This ensures O(1)
  cache hits from the first telemetry packet, rather than incurring a database
  query on first access.

  ## Caches Warmed

  - **Limits.Cache** - Per-target limits configurations
  - **DerivedItems.Cache** - Mission-wide derived item definitions

  ## Note

  MetaCommandCache and PacketIdentifier already load eagerly at init, so they
  don't need warming.
  """

  use GenServer
  require Logger

  alias Cadence.Runtime.Telemetry.DerivedItems.Cache, as: DerivedItemsCache
  alias Cadence.Runtime.Telemetry.Limits.Cache, as: LimitsCache
  alias Cadence.Targets

  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    GenServer.start_link(__MODULE__, mission_id, name: via_tuple(mission_id))
  end

  @impl true
  def init(mission_id) do
    # Warm caches asynchronously via handle_continue to not block supervisor startup
    {:ok, %{mission_id: mission_id}, {:continue, :warm_caches}}
  end

  @impl true
  def handle_continue(:warm_caches, state) do
    warm_all_caches(state.mission_id)
    {:noreply, state}
  end

  defp warm_all_caches(mission_id) do
    start_time = System.monotonic_time(:millisecond)

    # Warm derived items cache (mission-wide)
    DerivedItemsCache.warm(mission_id)

    # Get all targets for this mission and warm limits cache for each
    targets = Targets.list_targets(mission_id)

    Enum.each(targets, fn target ->
      # Use target identifier for limits cache (as expected by limits processing)
      LimitsCache.warm(mission_id, target.identifier)
    end)

    elapsed = System.monotonic_time(:millisecond) - start_time

    Logger.info(
      "Cache warming complete for mission_id=#{mission_id}: " <>
        "#{length(targets)} targets, #{elapsed}ms"
    )
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :cache_warmer}}}
  end
end
