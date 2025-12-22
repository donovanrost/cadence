defmodule Cadence.Alarms.Engine.RuleCache do
  @moduledoc """
  ETS-based cache for alarm rules to enable fast rule lookup during event processing.

  The cache is organized by mission_id for efficient lookup. When an event arrives,
  we fetch all potentially matching rules for that mission and evaluate them.

  ## Cache Structure

  - Table: `:alarm_rules_cache`
  - Key: `{mission_id}` or `:org_rules`
  - Value: List of `AlarmRule` structs

  ## Cache Invalidation

  The cache is invalidated when rules are created, updated, or deleted.
  Subscribe to `"alarm_rules:changed"` PubSub topic for invalidation events.
  """

  use GenServer
  require Logger

  alias Cadence.Alarms
  alias Cadence.Alarms.AlarmRule
  alias Cadence.Ports.Messaging.EventPublisher
  alias Cadence.Targets

  # Event publisher accessor
  defp event_publisher, do: EventPublisher.impl()

  @table_name :alarm_rules_cache
  @refresh_interval :timer.minutes(5)

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets all rules that could potentially match for a given mission.

  Returns rules in specificity order (most specific first).
  """
  @spec get_rules_for_mission(String.t(), String.t(), String.t() | nil) :: [AlarmRule.t()]
  def get_rules_for_mission(organization_id, mission_id, target_id \\ nil) do
    case :ets.lookup(@table_name, {:mission, mission_id}) do
      [{_, rules}] ->
        filter_and_sort_rules(rules, organization_id, mission_id, target_id)

      [] ->
        # Cache miss - fetch from database and cache
        rules = fetch_and_cache_mission_rules(organization_id, mission_id)
        filter_and_sort_rules(rules, organization_id, mission_id, target_id)
    end
  end

  @doc """
  Gets rules for a specific event type within a mission.
  """
  @spec get_rules_for_event(String.t(), String.t(), String.t() | nil, String.t()) ::
          [AlarmRule.t()]
  def get_rules_for_event(organization_id, mission_id, target_id, event_type) do
    get_rules_for_mission(organization_id, mission_id, target_id)
    |> Enum.filter(&(&1.event_type == event_type))
  end

  @doc """
  Invalidates the cache for a specific mission.
  """
  @spec invalidate_mission(String.t()) :: :ok
  def invalidate_mission(mission_id) do
    :ets.delete(@table_name, {:mission, mission_id})
    :ok
  end

  @doc """
  Invalidates the entire cache.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Forces a refresh of the cache for a mission.
  """
  @spec refresh_mission(String.t(), String.t()) :: :ok
  def refresh_mission(organization_id, mission_id) do
    fetch_and_cache_mission_rules(organization_id, mission_id)
    :ok
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    # Subscribe to rule change events
    event_publisher().subscribe("alarm_rules:changed")

    # Schedule periodic refresh
    schedule_refresh()

    Logger.info("AlarmRule cache initialized")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:refresh, state) do
    # Clear stale entries (entries older than refresh interval get refreshed on next access)
    # For now, just schedule the next refresh
    schedule_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_info({:alarm_rule_changed, _event_type, %AlarmRule{mission_id: nil}}, state) do
    # Org-wide rule changed - invalidate entire cache since it could affect any mission
    Logger.debug("Org-wide alarm rule changed, invalidating entire cache")
    invalidate_all()
    {:noreply, state}
  end

  @impl true
  def handle_info({:alarm_rule_changed, _event_type, %AlarmRule{mission_id: mission_id}}, state) do
    Logger.debug("Alarm rule changed for mission #{mission_id}, invalidating cache")
    invalidate_mission(mission_id)
    {:noreply, state}
  end

  # Legacy handlers for backwards compatibility
  @impl true
  def handle_info({:rule_changed, :all}, state) do
    Logger.debug("Invalidating entire alarm rule cache")
    invalidate_all()
    {:noreply, state}
  end

  @impl true
  def handle_info({:rule_changed, mission_id}, state) when is_binary(mission_id) do
    Logger.debug("Invalidating alarm rule cache for mission #{mission_id}")
    invalidate_mission(mission_id)
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_and_cache_mission_rules(organization_id, mission_id) do
    # Fetch rules that could apply to this mission:
    # 1. Org-wide rules (no mission_id, no target_id)
    # 2. Mission-wide rules (this mission_id, no target_id)
    # 3. Target-specific rules (this mission_id, any target_id)
    all_rules =
      Alarms.list_rules(organization_id, mission_id: mission_id, enabled: true)

    # Pre-compile regex patterns for faster matching
    rules_with_compiled_patterns = Enum.map(all_rules, &compile_patterns/1)

    # Cache the rules
    :ets.insert(@table_name, {{:mission, mission_id}, rules_with_compiled_patterns})

    rules_with_compiled_patterns
  end

  # Pre-compiles regex patterns in rule conditions for faster matching
  defp compile_patterns(%AlarmRule{conditions: conditions} = rule) when is_map(conditions) do
    case Map.get(conditions, "item_name_pattern") do
      nil ->
        rule

      pattern when is_binary(pattern) ->
        case Regex.compile(pattern) do
          {:ok, regex} ->
            # Store compiled regex in conditions under a special key
            updated_conditions = Map.put(conditions, :compiled_item_name_pattern, regex)
            %{rule | conditions: updated_conditions}

          {:error, _} ->
            # Invalid regex, keep original (will fail matching)
            Logger.warning("Invalid regex pattern in alarm rule #{rule.id}: #{pattern}")
            rule
        end

      _ ->
        rule
    end
  end

  defp compile_patterns(rule), do: rule

  defp filter_and_sort_rules(rules, _organization_id, mission_id, target_id) do
    # Resolve target_id if it's a string identifier
    resolved_target_id = resolve_target_id(mission_id, target_id)

    rules
    |> Enum.filter(fn rule ->
      rule.enabled &&
        (is_nil(rule.mission_id) || rule.mission_id == mission_id) &&
        (is_nil(rule.target_id) || rule.target_id == resolved_target_id)
    end)
    |> Enum.sort_by(&AlarmRule.specificity/1, :desc)
  end

  # Resolves a target_id to a UUID.
  # If it's already a valid UUID, returns it as-is.
  # If it's a string identifier, looks up the target and returns its UUID.
  defp resolve_target_id(_mission_id, nil), do: nil

  defp resolve_target_id(mission_id, target_id) when is_binary(target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        uuid

      :error ->
        case Targets.get_target_by_identifier(mission_id, target_id) do
          {:ok, %{id: uuid}} -> uuid
          {:error, :not_found} -> nil
        end
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
