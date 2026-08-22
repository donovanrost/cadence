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

  MetaCommandCache already loads eagerly at init, so it doesn't need warming.
  """

  use GenServer
  require Logger

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.Telemetry.DerivedItems.Cache, as: DerivedItemsCache
  alias Cadence.Runtime.Telemetry.Limits.Cache, as: LimitsCache
  alias Cadence.Time, as: CadenceTime

  def start_link(opts) do
    if enabled?() do
      do_start_link(opts)
    else
      :ignore
    end
  end

  def enabled? do
    :cadence
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  defp do_start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    mission_id = config.mission_id

    GenServer.start_link(
      __MODULE__,
      %{mission_id: mission_id, config: config},
      name: via_tuple(mission_id)
    )
  end

  @impl true
  def init(state) do
    # Warm caches asynchronously via handle_continue to not block supervisor startup
    {:ok, state, {:continue, :warm_caches}}
  end

  @impl true
  def handle_continue(:warm_caches, state) do
    warm_all_caches(state)
    {:noreply, state}
  end

  defp warm_all_caches(%{mission_id: mission_id, config: %MissionConfig{} = config}) do
    start_time = CadenceTime.monotonic(:millisecond)

    # Warm derived items cache (mission-wide)
    DerivedItemsCache.warm_from_defs(mission_id, config.derived_item_defs)

    # Warm limits cache for each target using config snapshot
    LimitsCache.warm_from_packet_defs(mission_id, config.targets, config.packet_defs)

    elapsed = CadenceTime.monotonic(:millisecond) - start_time

    Logger.info(
      "Cache warming complete for mission_id=#{mission_id}: " <>
        "#{length(config.targets)} targets, #{elapsed}ms"
    )
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {mission_id, :cache_warmer}}}
  end
end
