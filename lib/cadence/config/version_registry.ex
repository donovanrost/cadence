defmodule Cadence.Config.VersionRegistry do
  @moduledoc """
  Tracks configuration versions for cache invalidation.

  ## Problem

  ETS caches (MetaCommandCache, etc.) can become stale when:
  - Database is updated directly (migrations, manual fixes)
  - Config changes aren't propagated to all cache consumers
  - Multi-node deployments have different cache states

  ## Solution

  Each config type has a version number stored in ETS. When config is updated:
  1. Version increments via `invalidate/2`
  2. PubSub broadcasts `{:config_invalidated, type, scope_id, version}`
  3. Cache consumers reload if their cached version is stale

  ## Config Types

  - `:definition_set` - MetaCommand definitions, packet definitions
  - `:targets` - Target configurations
  - `:interfaces` - Interface configurations
  - `:limits` - Limit set configurations
  - `:derived_items` - Derived item definitions
  - `:alarm_rules` - Alarm rule configurations
  - `:automations` - Automation configurations

  ## Usage

  ### Invalidating config (in application services):

      # After updating a definition_set
      VersionRegistry.invalidate(:definition_set, definition_set_id)

      # After updating target config
      VersionRegistry.invalidate(:targets, mission_id)

  ### Checking versions (in cache consumers):

      # On init, store current version
      version = VersionRegistry.get_version(:definition_set, definition_set_id)
      {:ok, %{version: version, ...}}

      # Handle invalidation events
      def handle_info({:config_invalidated, :definition_set, id, new_version}, state) do
        if new_version > state.version do
          # Reload cache
        end
      end

  ## PubSub Topics

  Broadcasts to: `config:{config_type}:{scope_id}`

  Subscribe with:
      Phoenix.PubSub.subscribe(Cadence.PubSub, "config:definition_set:\#{definition_set_id}")

  """

  require Logger

  @table :config_versions

  @type config_type ::
          :definition_set
          | :targets
          | :interfaces
          | :limits
          | :derived_items
          | :alarm_rules
          | :automations

  @doc """
  Initializes the version registry ETS table.

  Called from Application.start/2.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
      Logger.info("Config.VersionRegistry initialized")
    end

    :ok
  end

  @doc """
  Gets the current version for a config type and scope.

  Returns 0 if no version has been set.
  """
  @spec get_version(config_type(), String.t()) :: non_neg_integer()
  def get_version(config_type, scope_id) do
    case :ets.lookup(@table, {config_type, scope_id}) do
      [{_, version}] -> version
      [] -> 0
    end
  end

  @doc """
  Increments and returns the new version for a config type and scope.
  """
  @spec increment_version(config_type(), String.t()) :: non_neg_integer()
  def increment_version(config_type, scope_id) do
    :ets.update_counter(@table, {config_type, scope_id}, 1, {{config_type, scope_id}, 0})
  end

  @doc """
  Invalidates a config, incrementing version and broadcasting the change.

  Call this from application services after any config write operation.

  ## Example

      # After saving a definition_set
      VersionRegistry.invalidate(:definition_set, definition_set.id)

  """
  @spec invalidate(config_type(), String.t()) :: :ok
  def invalidate(config_type, scope_id) do
    new_version = increment_version(config_type, scope_id)
    topic = topic_for(config_type, scope_id)

    Logger.debug(
      "Config invalidated: type=#{config_type}, scope=#{scope_id}, version=#{new_version}"
    )

    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      topic,
      {:config_invalidated, config_type, scope_id, new_version}
    )

    :ok
  end

  @doc """
  Invalidates config for an entire mission (all related caches).

  Useful when major changes affect multiple config types.
  """
  @spec invalidate_mission(String.t()) :: :ok
  def invalidate_mission(mission_id) do
    [:targets, :interfaces, :limits, :derived_items, :alarm_rules, :automations]
    |> Enum.each(&invalidate(&1, mission_id))

    :ok
  end

  @doc """
  Returns the PubSub topic for a config type and scope.
  """
  @spec topic_for(config_type(), String.t()) :: String.t()
  def topic_for(config_type, scope_id) do
    "config:#{config_type}:#{scope_id}"
  end

  @doc """
  Returns all tracked versions (for debugging/monitoring).
  """
  @spec all_versions() :: [{config_type(), String.t(), non_neg_integer()}]
  def all_versions do
    :ets.tab2list(@table)
    |> Enum.map(fn {{type, scope}, version} -> {type, scope, version} end)
  end

  @doc """
  Clears all versions (for testing).
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end
end
