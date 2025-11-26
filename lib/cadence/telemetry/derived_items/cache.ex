defmodule Cadence.Telemetry.DerivedItems.Cache do
  @moduledoc """
  ETS-based cache for derived item definitions.

  Caches derived items per mission to avoid database queries in the hot
  telemetry processing path. Items are pre-sorted by dependencies for
  efficient evaluation.

  ## Cache Structure

  - Table: `:derived_items_cache`
  - Key: `mission_id`
  - Value: `{sorted_defs, updated_at}`

  ## Cache Invalidation

  The cache is invalidated when:
  - A derived item is created, updated, or deleted
  - Explicitly cleared via `invalidate/1`

  ## Usage

      # Get cached definitions (loads from DB if not cached)
      {:ok, sorted_defs} = Cache.get_definitions(mission_id)

      # Invalidate after changes
      Cache.invalidate(mission_id)
  """

  use GenServer
  require Logger

  alias Cadence.Telemetry.Database.DerivedItem
  alias Cadence.Telemetry.DerivedItems

  @table :derived_items_cache
  @cache_ttl_ms :timer.minutes(5)

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
  Gets cached derived item definitions for a mission.

  Returns pre-sorted definitions ready for evaluation. Loads from database
  and caches if not already cached.

  If the cache is not running (e.g., in tests), falls back to loading
  directly from the database.

  ## Returns

  - `{:ok, sorted_defs}` - List of definitions sorted by dependencies
  - `{:error, reason}` - If loading or sorting fails
  """
  @spec get_definitions(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_definitions(mission_id) do
    if :ets.whereis(@table) != :undefined do
      case lookup(mission_id) do
        {:ok, sorted_defs} ->
          {:ok, sorted_defs}

        :miss ->
          # Load from database and cache
          load_and_cache(mission_id)
      end
    else
      # Cache not started, load directly (e.g., in tests)
      load_without_cache(mission_id)
    end
  end

  @doc """
  Invalidates the cache for a specific mission.

  Call this when derived items are created, updated, or deleted.
  Safe to call even if cache is not running.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(mission_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, mission_id)
      Logger.debug("Invalidated derived items cache for mission #{mission_id}")
    end

    :ok
  end

  @doc """
  Invalidates all cached entries.

  Safe to call even if cache is not running.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      Logger.debug("Invalidated all derived items cache entries")
    end

    :ok
  end

  @doc """
  Returns cache statistics for monitoring.
  """
  @spec stats() :: map()
  def stats do
    info = :ets.info(@table)

    %{
      size: Keyword.get(info, :size, 0),
      memory_bytes: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
    }
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl GenServer
  def init(_opts) do
    # Create ETS table owned by this process
    table = :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    Logger.info("Derived items cache started (table: #{inspect(table)})")

    # Schedule periodic cache cleanup
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
  # Private Functions
  # ============================================================================

  defp lookup(mission_id) do
    case :ets.lookup(@table, mission_id) do
      [{^mission_id, {_defs, _index} = cached_data, cached_at}] ->
        # Check if cache is still valid
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          {:ok, cached_data}
        else
          :miss
        end

      # Handle legacy format (defs only, no index) - will be replaced on next cache miss
      [{^mission_id, sorted_defs, cached_at}] when is_list(sorted_defs) ->
        if System.monotonic_time(:millisecond) - cached_at < @cache_ttl_ms do
          {:ok, {sorted_defs, %{}}}
        else
          :miss
        end

      [] ->
        :miss
    end
  end

  defp load_and_cache(mission_id) do
    alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

    # Load from database
    derived_items = DerivedItem.list_enabled(mission_id)
    derived_defs = Enum.map(derived_items, &DerivedItem.to_compute_format/1)

    # Sort by dependencies
    case DerivedItems.sort_by_dependencies(derived_defs) do
      {:ok, sorted_defs} ->
        # Pre-extract required variables and pre-parse AST (avoids parsing in hot path)
        # Also assign topological order index for maintaining sort after filtering
        alias Cadence.Telemetry.DerivedItems.ExpressionParser

        enriched_defs =
          sorted_defs
          |> Enum.with_index()
          |> Enum.map(fn {def, topo_order} ->
            expression = get_in(def.derived_config, ["expression"]) || ""

            required_vars =
              case ExpressionEvaluator.extract_variables(expression) do
                {:ok, vars} -> vars
                {:error, _} -> []
              end

            # Pre-parse the expression to AST (huge performance win - avoids parsing per evaluation)
            parsed_ast =
              case ExpressionParser.parse(expression) do
                {:ok, ast} -> ast
                {:error, _} -> nil
              end

            # Pre-compute whether expression has stateful functions
            # This allows skipping stateful evaluation overhead for pure expressions
            has_stateful =
              if parsed_ast do
                ExpressionParser.ast_has_stateful?(parsed_ast)
              else
                ExpressionParser.has_stateful_functions?(expression)
              end

            def
            |> Map.put(:required_vars, required_vars)
            |> Map.put(:topo_order, topo_order)
            |> Map.put(:parsed_ast, parsed_ast)
            |> Map.put(:has_stateful, has_stateful)
          end)

        # Compute root packets for each item (which raw telemetry packets it depends on)
        derived_names = MapSet.new(enriched_defs, & &1.name)
        enriched_defs = compute_root_packets(enriched_defs, derived_names)

        # Build packet index for O(1) lookup
        packet_index = build_packet_index(enriched_defs)

        # Cache the enriched definitions and index
        cached_at = System.monotonic_time(:millisecond)
        :ets.insert(@table, {mission_id, {enriched_defs, packet_index}, cached_at})

        Logger.debug(
          "Cached #{length(enriched_defs)} derived items for mission #{mission_id} " <>
          "(#{map_size(packet_index)} packet types indexed)"
        )

        {:ok, {enriched_defs, packet_index}}

      {:error, reason} = error ->
        Logger.error(
          "Failed to sort derived items for mission #{mission_id}: #{inspect(reason)}"
        )

        error
    end
  end

  # Compute which raw telemetry packets each derived item ultimately depends on
  # This allows us to skip items that can't possibly be computed for a given packet
  defp compute_root_packets(defs, derived_names) do
    # Build a map of item name -> root packets (computed iteratively for dependencies)
    root_packets_map =
      Enum.reduce(defs, %{}, fn def, acc ->
        root_packets = compute_root_packets_for_item(def, derived_names, acc)
        Map.put(acc, def.name, root_packets)
      end)

    # Enrich each def with its root_packets
    Enum.map(defs, fn def ->
      Map.put(def, :root_packets, Map.get(root_packets_map, def.name, MapSet.new()))
    end)
  end

  defp compute_root_packets_for_item(def, derived_names, computed_so_far) do
    def.required_vars
    |> Enum.reduce(MapSet.new(), fn var, acc ->
      case String.split(var, ".", parts: 2) do
        [packet_name, _item_name] ->
          if MapSet.member?(derived_names, packet_name) do
            # This depends on another derived item - get its root packets
            case Map.get(computed_so_far, packet_name) do
              nil -> acc  # Not yet computed (shouldn't happen due to topo sort)
              root_packets -> MapSet.union(acc, root_packets)
            end
          else
            # This is a raw telemetry packet
            MapSet.put(acc, packet_name)
          end

        _ ->
          acc
      end
    end)
  end

  # Build an index: packet_name -> list of derived items that can be computed
  # when that packet (and possibly others) is available
  defp build_packet_index(defs) do
    Enum.reduce(defs, %{}, fn def, acc ->
      Enum.reduce(def.root_packets, acc, fn packet, inner_acc ->
        Map.update(inner_acc, packet, [def], &[def | &1])
      end)
    end)
    # Reverse lists to maintain topological order
    |> Enum.map(fn {k, v} -> {k, Enum.reverse(v)} end)
    |> Map.new()
  end

  # Load without caching (fallback when cache not started)
  defp load_without_cache(mission_id) do
    alias Cadence.Telemetry.DerivedItems.ExpressionEvaluator

    derived_items = DerivedItem.list_enabled(mission_id)
    derived_defs = Enum.map(derived_items, &DerivedItem.to_compute_format/1)

    case DerivedItems.sort_by_dependencies(derived_defs) do
      {:ok, sorted_defs} ->
        # Enrich with required variables, topological order, and pre-parsed AST
        alias Cadence.Telemetry.DerivedItems.ExpressionParser

        enriched_defs =
          sorted_defs
          |> Enum.with_index()
          |> Enum.map(fn {def, topo_order} ->
            expression = get_in(def.derived_config, ["expression"]) || ""

            required_vars =
              case ExpressionEvaluator.extract_variables(expression) do
                {:ok, vars} -> vars
                {:error, _} -> []
              end

            parsed_ast =
              case ExpressionParser.parse(expression) do
                {:ok, ast} -> ast
                {:error, _} -> nil
              end

            # Pre-compute whether expression has stateful functions
            has_stateful =
              if parsed_ast do
                ExpressionParser.ast_has_stateful?(parsed_ast)
              else
                ExpressionParser.has_stateful_functions?(expression)
              end

            def
            |> Map.put(:required_vars, required_vars)
            |> Map.put(:topo_order, topo_order)
            |> Map.put(:parsed_ast, parsed_ast)
            |> Map.put(:has_stateful, has_stateful)
          end)

        # Compute root packets and build index
        derived_names = MapSet.new(enriched_defs, & &1.name)
        enriched_defs = compute_root_packets(enriched_defs, derived_names)
        packet_index = build_packet_index(enriched_defs)

        {:ok, {enriched_defs, packet_index}}

      error ->
        error
    end
  end

  defp schedule_cleanup do
    # Run cleanup every minute
    Process.send_after(self(), :cleanup, :timer.minutes(1))
  end

  defp cleanup_stale_entries do
    now = System.monotonic_time(:millisecond)

    # Find and delete stale entries
    stale_keys =
      :ets.foldl(
        fn {mission_id, _defs, cached_at}, acc ->
          if now - cached_at >= @cache_ttl_ms do
            [mission_id | acc]
          else
            acc
          end
        end,
        [],
        @table
      )

    Enum.each(stale_keys, &:ets.delete(@table, &1))

    if length(stale_keys) > 0 do
      Logger.debug("Cleaned up #{length(stale_keys)} stale cache entries")
    end
  end
end
