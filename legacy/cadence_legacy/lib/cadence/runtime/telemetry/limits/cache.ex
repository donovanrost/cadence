defmodule Cadence.Runtime.Telemetry.Limits.Cache do
  @moduledoc """
  ETS-based cache for limits configurations.

  Caches limits configurations per mission to avoid database queries in the hot
  telemetry processing path. The cache provides O(1) lookups for item limits.

  ## Cache Structure

  - Table: `:limits_cache`
  - Key: `{mission_id, target_id}`
  - Value: `{item_limits_map, active_limit_set, cached_at}`

  Where `item_limits_map` is:
  ```
  %{
    "PACKET.item_name" => %{
      has_limits: true,
      limits_config: %{"NOMINAL" => %{...}, "ECLIPSE" => %{...}},
      persistence: 1,
      stale_timeout_ms: 30000
    }
  }
  ```

  ## Cache Invalidation

  The cache is invalidated when:
  - Packet item limits are updated
  - Target's active limit set changes
  - Explicitly cleared via `invalidate/2`

  ## Usage

      # Get limits for a specific item
      {:ok, limits, persistence} = Cache.get_limits(mission_id, target_id, "HEALTH.cpu_temp")

      # Check if item has limits configured
      Cache.has_limits?(mission_id, target_id, "HEALTH.cpu_temp")

      # Invalidate after changes
      Cache.invalidate(mission_id, target_id)
  """

  use GenServer
  require Logger

  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  alias Cadence.Runtime.Telemetry.ConfigBundle

  @table :limits_cache
  @cache_ttl_ms :timer.minutes(5)

  # Default values
  @default_persistence 1
  @default_stale_timeout_ms 30_000

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the cache server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the limits configuration for a specific item.

  Returns the applicable limits for the target's active limit set.

  ## Returns

  - `{:ok, limits, persistence, stale_timeout_ms}` - Limits found
  - `:not_configured` - Item has no limits configured
  - `{:error, reason}` - Cache loading failed
  """
  @spec get_limits(String.t(), String.t(), String.t()) ::
          {:ok, map(), pos_integer(), pos_integer()} | :not_configured | {:error, term()}
  def get_limits(mission_id, target_id, qualified_item_name) do
    with {:ok, config, active_limit_set} <-
           fetch_limits_config(mission_id, target_id, qualified_item_name),
         {:ok, limits} <- select_limits(config, active_limit_set) do
      {:ok, limits, persistence_for(config), stale_timeout_for(config)}
    else
      :not_configured -> :not_configured
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_limits_config(mission_id, target_id, qualified_item_name) do
    with {:ok, item_limits_map, active_limit_set} <- get_cached_data(mission_id, target_id),
         {:ok, config} <- fetch_item_config(item_limits_map, qualified_item_name) do
      {:ok, config, active_limit_set}
    end
  end

  defp persistence_for(config) do
    Map.get(config, :persistence, @default_persistence)
  end

  defp stale_timeout_for(config) do
    Map.get(config, :stale_timeout_ms, @default_stale_timeout_ms)
  end

  defp fetch_item_config(item_limits_map, qualified_item_name) do
    case Map.get(item_limits_map, qualified_item_name) do
      nil -> :not_configured
      %{has_limits: false} -> :not_configured
      %{has_limits: true} = config -> {:ok, config}
    end
  end

  defp select_limits(%{limits_config: limits_config}, active_limit_set) do
    case Map.get(limits_config, active_limit_set) || Map.get(limits_config, "DEFAULT") do
      nil -> :not_configured
      limits -> {:ok, limits}
    end
  end

  @doc """
  Checks if an item has limits configured.

  ## Returns

  - `true` - Item has limits
  - `false` - Item has no limits or cache not available
  """
  @spec has_limits?(String.t(), String.t(), String.t()) :: boolean()
  def has_limits?(mission_id, target_id, qualified_item_name) do
    case get_cached_data(mission_id, target_id) do
      {:ok, item_limits_map, _active_set} ->
        case Map.get(item_limits_map, qualified_item_name) do
          %{has_limits: true} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Gets the active limit set for a target.

  ## Returns

  - `{:ok, active_set}` - Active limit set name
  - `{:error, reason}` - Cache loading failed
  """
  @spec get_active_limit_set(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_active_limit_set(mission_id, target_id) do
    case get_cached_data(mission_id, target_id) do
      {:ok, _item_limits_map, active_limit_set} ->
        {:ok, active_limit_set}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets all items with limits configured for a mission/target.

  Returns a list of qualified item names that have limits.
  """
  @spec get_items_with_limits(String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def get_items_with_limits(mission_id, target_id) do
    case get_cached_data(mission_id, target_id) do
      {:ok, item_limits_map, _active_set} ->
        items_with_limits =
          item_limits_map
          |> Enum.filter(fn {_name, config} -> config[:has_limits] == true end)
          |> Enum.map(fn {name, _config} -> name end)

        {:ok, items_with_limits}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Invalidates the cache for a specific mission/target combination.

  Call this when limits or active limit set changes.
  """
  @spec invalidate(String.t(), String.t()) :: :ok
  def invalidate(mission_id, target_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, {mission_id, target_id})
      Logger.debug("Invalidated limits cache for mission=#{mission_id}, target=#{target_id}")
    end

    :ok
  end

  @doc """
  Invalidates all cache entries for a mission (all targets).
  """
  @spec invalidate_mission(String.t()) :: :ok
  def invalidate_mission(mission_id) do
    if :ets.whereis(@table) != :undefined do
      # Find and delete all entries for this mission
      match_spec = [{{{{mission_id, :_}, :_, :_, :_}}, [], [true]}]
      :ets.select_delete(@table, match_spec)
      Logger.debug("Invalidated all limits cache entries for mission=#{mission_id}")
    end

    :ok
  end

  @doc """
  Invalidates all cached entries.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      Logger.debug("Invalidated all limits cache entries")
    end

    :ok
  end

  @doc """
  Pre-warms the cache for a specific mission/target combination.

  Call this at mission startup to ensure limits are cached before telemetry
  processing begins. This avoids a database query on the first telemetry packet.

  ## Example

      Cache.warm(mission_id, target_id)

  """
  @spec warm(String.t(), String.t()) :: :ok
  def warm(mission_id, target_id) do
    _ = get_cached_data(mission_id, target_id)
    :ok
  end

  @doc """
  Pre-warms the cache from preloaded packet definitions and targets.

  This avoids database access when config is provided by the control plane.
  """
  @spec warm_from_packet_defs(String.t(), list(), list()) :: :ok
  def warm_from_packet_defs(mission_id, targets, packet_defs)
      when is_list(targets) and is_list(packet_defs) do
    if :ets.whereis(@table) != :undefined do
      item_limits_map = build_item_limits_map(packet_defs)
      cached_at = CadenceTime.monotonic(:millisecond)

      Enum.each(targets, fn target ->
        target_id = target.identifier
        active_limit_set = target.active_limit_set || "NOMINAL"

        :ets.insert(
          @table,
          {{mission_id, target_id}, item_limits_map, active_limit_set, cached_at}
        )
      end)
    end

    :ok
  end

  @doc """
  Returns cache statistics for monitoring.
  """
  @spec stats() :: map()
  def stats do
    if :ets.whereis(@table) != :undefined do
      info = :ets.info(@table)

      %{
        size: Keyword.get(info, :size, 0),
        memory_bytes: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
      }
    else
      %{size: 0, memory_bytes: 0}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(_opts) do
    table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true
      ])

    Logger.info("Limits cache started (table: #{inspect(table)})")

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_stale_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # ============================================================================
  # Semi-public Functions (for batch optimization)
  # ============================================================================

  @doc """
  Gets the cached data for a mission/target.

  Returns `{:ok, item_limits_map, active_limit_set}` or `{:error, reason}`.

  This is exposed for batch processing optimizations in StateTracker.
  """
  @spec get_cached_data(String.t(), String.t()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def get_cached_data(mission_id, target_id) do
    if :ets.whereis(@table) != :undefined do
      case lookup(mission_id, target_id) do
        {:ok, item_limits_map, active_limit_set} ->
          {:ok, item_limits_map, active_limit_set}

        :miss ->
          load_and_cache(mission_id, target_id)
      end
    else
      # Cache not started, load directly
      load_without_cache(mission_id, target_id)
    end
  end

  defp lookup(mission_id, target_id) do
    case :ets.lookup(@table, {mission_id, target_id}) do
      [{{^mission_id, ^target_id}, item_limits_map, active_limit_set, cached_at}] ->
        if CadenceTime.monotonic(:millisecond) - cached_at < @cache_ttl_ms do
          {:ok, item_limits_map, active_limit_set}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  defp load_and_cache(mission_id, target_id) do
    case load_limits_data(mission_id, target_id) do
      {:ok, item_limits_map, active_limit_set} ->
        cached_at = CadenceTime.monotonic(:millisecond)

        :ets.insert(
          @table,
          {{mission_id, target_id}, item_limits_map, active_limit_set, cached_at}
        )

        Logger.debug(
          "Cached limits for mission=#{mission_id}, target=#{target_id}: " <>
            "#{map_size(item_limits_map)} items, active_set=#{active_limit_set}"
        )

        {:ok, item_limits_map, active_limit_set}

      {:error, reason} = error ->
        Logger.error(
          "Failed to load limits for mission=#{mission_id}, target=#{target_id}: #{inspect(reason)}"
        )

        error
    end
  end

  defp load_without_cache(mission_id, target_id) do
    load_limits_data(mission_id, target_id)
  end

  defp load_limits_data(mission_id, target_id) do
    case ConfigBundle.fetch(mission_id) do
      {:ok, bundle} ->
        active_limit_set = get_target_active_limit_set(bundle, target_id)
        item_limits_map = build_item_limits_map(bundle.packet_defs || [])
        {:ok, item_limits_map, active_limit_set}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  defp get_target_active_limit_set(bundle, target_identifier) do
    target =
      Map.get(bundle.targets_by_identifier, target_identifier) ||
        Map.get(bundle.targets_by_identifier, to_string(target_identifier))

    case target do
      nil -> "NOMINAL"
      _ -> Map.get(target, :active_limit_set) || "NOMINAL"
    end
  end

  defp build_item_config(item) do
    %{
      has_limits: item.has_limits || false,
      limits_config: parse_limits_config(item.limits_config),
      persistence: get_persistence(item.limits_config),
      stale_timeout_ms: get_stale_timeout(item.limits_config)
    }
  end

  defp build_item_limits_map(packet_defs) do
    packet_defs
    |> Enum.flat_map(fn packet_def ->
      packet_name = packet_def.name

      packet_def.packet_items
      |> Enum.map(fn item ->
        qualified_name = "#{packet_name}.#{item.name}"
        config = build_item_config(item)
        {qualified_name, config}
      end)
    end)
    |> Map.new()
  end

  # Parse limits_config - handle both legacy (flat) and new (named sets) formats
  defp parse_limits_config(nil), do: %{}
  defp parse_limits_config(config) when not is_map(config), do: %{}

  defp parse_limits_config(config) do
    # Check if this is the new format (has named sets)
    # New format: %{"NOMINAL" => %{...}, "ECLIPSE" => %{...}}
    # Legacy format: %{"red_low" => -50.0, "red_high" => 100.0, ...}
    if has_named_sets?(config) do
      config
    else
      # Convert legacy format to new format under "DEFAULT" key
      %{"DEFAULT" => config}
    end
  end

  defp has_named_sets?(config) when is_map(config) do
    # Check if any key looks like a named set (value is a map with limit keys)
    Enum.any?(config, fn {_key, value} ->
      is_map(value) and
        (Map.has_key?(value, "red_low") or Map.has_key?(value, "red_high") or
           Map.has_key?(value, "yellow_low") or Map.has_key?(value, "yellow_high"))
    end)
  end

  defp has_named_sets?(_), do: false

  # Get persistence from any limit set (use first found or default)
  defp get_persistence(nil), do: @default_persistence

  defp get_persistence(config) when is_map(config) do
    # Look for persistence in any of the limit sets
    config
    |> Enum.find_value(@default_persistence, fn
      {_set_name, set_config} when is_map(set_config) ->
        Map.get(set_config, "persistence")

      _ ->
        nil
    end)
  end

  defp get_persistence(_), do: @default_persistence

  # Get stale timeout from any limit set (use first found or default)
  defp get_stale_timeout(nil), do: @default_stale_timeout_ms

  defp get_stale_timeout(config) when is_map(config) do
    config
    |> Enum.find_value(@default_stale_timeout_ms, fn
      {_set_name, set_config} when is_map(set_config) ->
        Map.get(set_config, "stale_timeout_ms")

      _ ->
        nil
    end)
  end

  defp get_stale_timeout(_), do: @default_stale_timeout_ms

  defp schedule_cleanup do
    TimeTimer.send_after(self(), :cleanup, :timer.minutes(1))
  end

  defp cleanup_stale_entries do
    now = CadenceTime.monotonic(:millisecond)

    stale_keys =
      :ets.foldl(
        fn {{mission_id, target_id}, _map, _set, cached_at}, acc ->
          if now - cached_at >= @cache_ttl_ms do
            [{mission_id, target_id} | acc]
          else
            acc
          end
        end,
        [],
        @table
      )

    Enum.each(stale_keys, &:ets.delete(@table, &1))

    if length(stale_keys) > 0 do
      Logger.debug("Cleaned up #{length(stale_keys)} stale limits cache entries")
    end
  end
end
