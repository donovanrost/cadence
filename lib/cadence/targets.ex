defmodule Cadence.Targets do
  @moduledoc """
  The Targets context - boundary for target-related operations.

  This context handles:
  - Target CRUD operations
  - Circuit breaker state management
  - Target status tracking
  - Pipeline orchestration for running missions

  ## Hexagonal Architecture

  This facade delegates persistence to use case modules:
  - `Cadence.Application.Targeting.TargetQueries` - read operations
  - `Cadence.Application.Targeting.TargetOperations` - write operations

  Domain operations return domain entities (`Cadence.Domain.Targeting.Entities.Target`).

  ## LiveView Form Support

  For LiveView forms that require Ecto schemas/changesets, use:
  - `get_target_schema/2` / `get_target_schema!/2` - Returns Ecto schema
  - `get_target_schema_unscoped/1` / `get_target_schema_unscoped!/1` - Returns Ecto schema
  """

  alias Cadence.Application.Targeting.{TargetOperations, TargetQueries}
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Missions.Mission
  alias Cadence.Repo
  alias Cadence.Runtime.Commands.TargetPipelineSupervisor
  alias Cadence.Runtime.Missions.MissionInstance
  alias Cadence.Targets.Target, as: TargetSchema

  import Ecto.Query, only: [from: 2]

  # ===========================================================================
  # Query Operations
  # ===========================================================================

  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity

  @doc """
  Returns the list of targets for a mission.
  """
  @spec list_targets(Mission.t() | MissionEntity.t() | String.t()) :: [Target.t()]
  def list_targets(%Mission{id: mission_id}), do: list_targets(mission_id)
  def list_targets(%MissionEntity{id: mission_id}), do: list_targets(mission_id)

  def list_targets(mission_id) when is_binary(mission_id) do
    TargetQueries.list(mission_id)
  end

  @doc """
  Returns the list of targets for a mission with definition_set preloaded.

  Returns Ecto schemas (not domain entities) for use in views that need
  association data like `target.definition_set.database.name`.
  """
  @spec list_targets_with_preloads(Mission.t() | MissionEntity.t() | String.t()) :: [
          TargetSchema.t()
        ]
  def list_targets_with_preloads(%Mission{id: mission_id}),
    do: list_targets_with_preloads(mission_id)

  def list_targets_with_preloads(%MissionEntity{id: mission_id}),
    do: list_targets_with_preloads(mission_id)

  def list_targets_with_preloads(mission_id) when is_binary(mission_id) do
    from(t in TargetSchema,
      where: t.mission_id == ^mission_id,
      order_by: [asc: t.identifier],
      preload: [definition_set: :database]
    )
    |> Repo.all()
  end

  @doc """
  Lists targets with optional filtering.

  ## Options

  - `:status` - Filter by status (atom or list of atoms)
  - `:type` - Filter by type (atom or list of atoms)
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Offset for pagination (default: 0)
  """
  @spec list_targets(String.t(), keyword()) :: [Target.t()]
  def list_targets(mission_id, opts) when is_binary(mission_id) do
    TargetQueries.list(mission_id, opts)
  end

  @doc """
  Lists online targets for a mission.
  """
  @spec list_online_targets(String.t()) :: [Target.t()]
  def list_online_targets(mission_id) do
    TargetQueries.list_online(mission_id)
  end

  @doc """
  Gets a single target scoped to a mission.

  Returns `{:ok, target}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_target(String.t(), String.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def get_target(id, mission_id) do
    TargetQueries.find(id, mission_id)
  end

  @doc """
  Gets a single target scoped to a mission.

  Raises if the Target does not exist or doesn't belong to the mission.
  """
  @spec get_target!(String.t(), String.t()) :: Target.t()
  def get_target!(id, mission_id) do
    TargetQueries.find!(id, mission_id)
  end

  @doc """
  Gets a single target by ID without mission scoping.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where mission context is verified elsewhere (e.g., command pipeline, queue).
  """
  @spec get_target_unscoped(String.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def get_target_unscoped(id) do
    TargetQueries.find_unscoped(id)
  end

  @doc """
  Gets a single target by ID without mission scoping, raises if not found.

  WARNING: This bypasses multi-tenancy. Only use for internal operations
  where mission context is verified elsewhere.
  """
  @spec get_target_unscoped!(String.t()) :: Target.t()
  def get_target_unscoped!(id) do
    TargetQueries.find_unscoped!(id)
  end

  @doc """
  Gets a target by identifier within a mission.
  """
  @spec get_target_by_identifier(Mission.t() | MissionEntity.t() | String.t(), String.t()) ::
          {:ok, Target.t()} | {:error, :not_found}
  def get_target_by_identifier(%Mission{id: mission_id}, identifier) do
    get_target_by_identifier(mission_id, identifier)
  end

  def get_target_by_identifier(%MissionEntity{id: mission_id}, identifier) do
    get_target_by_identifier(mission_id, identifier)
  end

  def get_target_by_identifier(mission_id, identifier) when is_binary(mission_id) do
    TargetQueries.find_by_identifier(mission_id, identifier)
  end

  @doc """
  Gets a target with its definition set preloaded.
  """
  @spec get_target_with_definition_set(String.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def get_target_with_definition_set(id) do
    TargetQueries.find_with_definition_set(id)
  end

  @doc """
  Gets a target with definition set, raises if not found.
  """
  @spec get_target_with_definition_set!(String.t()) :: Target.t()
  def get_target_with_definition_set!(id) do
    TargetQueries.find_with_definition_set!(id)
  end

  # ===========================================================================
  # Ecto Schema Query Operations (for LiveView forms)
  # ===========================================================================

  @doc """
  Gets the Ecto schema for a target by ID, scoped to a mission.

  Returns the Ecto schema (not domain entity) for use with Phoenix forms.
  Raises if not found.
  """
  @spec get_target_schema!(String.t(), String.t()) :: TargetSchema.t()
  def get_target_schema!(id, mission_id) do
    from(t in TargetSchema,
      where: t.id == ^id and t.mission_id == ^mission_id
    )
    |> Repo.one!()
  end

  @doc """
  Gets the Ecto schema for a target by ID without mission scoping.

  Returns the Ecto schema (not domain entity) for use with Phoenix forms.
  Raises if not found.

  WARNING: This bypasses multi-tenancy.
  """
  @spec get_target_schema_unscoped!(String.t()) :: TargetSchema.t()
  def get_target_schema_unscoped!(id) do
    Repo.get!(TargetSchema, id)
  end

  @doc """
  Gets the Ecto schema for a target by ID without mission scoping.

  Returns `nil` if not found.

  WARNING: This bypasses multi-tenancy.
  """
  @spec get_target_schema_unscoped(String.t()) :: TargetSchema.t() | nil
  def get_target_schema_unscoped(id) do
    Repo.get(TargetSchema, id)
  end

  # ===========================================================================
  # Definition Set Queries
  # ===========================================================================

  @doc """
  Gets the definition_set_id for a target by mission_id and identifier.

  Returns `{:ok, id}` if found, `{:error, :not_found}` otherwise.
  This is used by the telemetry pipeline to look up the correct dictionary.
  """
  @spec get_definition_set_id(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_definition_set_id(mission_id, target_identifier)
      when is_binary(mission_id) and is_binary(target_identifier) do
    TargetQueries.get_definition_set_id(mission_id, target_identifier)
  end

  @doc """
  Gets the definition_set_id for a target by its ID.

  Returns `{:ok, id}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_definition_set_id_by_target_id(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_definition_set_id_by_target_id(target_id) when is_binary(target_id) do
    TargetQueries.get_definition_set_id_by_target_id(target_id)
  end

  @doc """
  Returns all targets using a specific definition set.

  Useful for determining which targets are affected by a given
  command/telemetry database version.
  """
  @spec list_targets_by_definition_set(String.t()) :: [Target.t()]
  def list_targets_by_definition_set(definition_set_id) do
    TargetQueries.list_by_definition_set(definition_set_id)
  end

  # ===========================================================================
  # Write Operations
  # ===========================================================================

  @doc """
  Creates a target.

  If the mission is currently running, also starts the target's command pipeline.
  Accepts both string-keyed and atom-keyed params (for LiveView form compatibility).

  ## Required Attributes

  - `:mission_id` - The mission this target belongs to
  - `:definition_set_id` - The C&T database definition set
  - `:name` - Human-readable name
  - `:identifier` - Unique identifier within mission (e.g., "SAT_001")
  - `:type` - Target type (:spacecraft, :ground_station, :simulator, :relay)

  ## Optional Attributes

  - `:status` - Initial status (default: :offline)
  - `:scid` - Spacecraft ID (required for spacecraft targets)
  - `:config` - Configuration map
  - `:metadata` - Metadata map
  - `:active_limit_set` - Active limit set name (default: "NOMINAL")
  - `:bucket_id` - Associated bucket for hierarchical grouping
  """
  @spec create_target(map()) :: {:ok, Target.t()} | {:error, term()}
  def create_target(attrs \\ %{}) do
    # Normalize string keys to atoms for domain entity
    normalized_attrs = normalize_attrs(attrs)

    case TargetOperations.create(normalized_attrs) do
      {:ok, target} ->
        maybe_start_pipeline(target)
        {:ok, target}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a target.

  Accepts either a domain entity or an Ecto schema. When passed an Ecto schema,
  converts it to a domain entity internally.

  ## Allowed Attributes

  - `:name` - Human-readable name
  - `:status` - Target status
  - `:scid` - Spacecraft ID (spacecraft targets only)
  - `:config` - Configuration map
  - `:metadata` - Metadata map
  - `:active_limit_set` - Active limit set name
  - `:definition_set_id` - Definition set ID
  - `:bucket_id` - Bucket ID
  """
  @spec update_target(Target.t() | TargetSchema.t(), map()) ::
          {:ok, Target.t()} | {:error, term()}
  def update_target(%Target{} = target, attrs) do
    normalized_attrs = normalize_attrs(attrs)
    TargetOperations.update(target, normalized_attrs)
  end

  def update_target(%TargetSchema{id: id}, attrs) do
    normalized_attrs = normalize_attrs(attrs)

    with {:ok, target} <- TargetQueries.find_unscoped(id) do
      TargetOperations.update(target, normalized_attrs)
    end
  end

  @doc """
  Deletes a target.

  Accepts either a domain entity or an Ecto schema.

  If the mission is running, stops the target's command pipeline and cancels
  any pending queued commands for this target.
  """
  @spec delete_target(Target.t() | TargetSchema.t()) :: {:ok, Target.t()} | {:error, term()}
  def delete_target(%Target{} = target) do
    cleanup_target_commands(target)
    maybe_stop_pipeline(target)
    TargetOperations.delete(target)
  end

  def delete_target(%TargetSchema{id: id}) do
    with {:ok, target} <- TargetQueries.find_unscoped(id) do
      cleanup_target_commands(target)
      maybe_stop_pipeline(target)
      TargetOperations.delete(target)
    end
  end

  # ===========================================================================
  # Definition Set Assignment
  # ===========================================================================

  @doc """
  Assigns a definition set to a target.

  This determines which command/telemetry dictionary the target uses.
  """
  @spec assign_definition_set(Target.t(), String.t()) :: {:ok, Target.t()} | {:error, term()}
  def assign_definition_set(%Target{} = target, definition_set_id) do
    TargetOperations.assign_definition_set(target, definition_set_id)
  end

  # ===========================================================================
  # Circuit Breaker Operations
  # ===========================================================================

  @doc """
  Opens the circuit breaker for a target after command failures.
  """
  @spec open_circuit_breaker(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def open_circuit_breaker(%Target{} = target) do
    TargetOperations.open_circuit_breaker(target)
  end

  @doc """
  Closes the circuit breaker, resetting failure count.
  """
  @spec close_circuit_breaker(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def close_circuit_breaker(%Target{} = target) do
    TargetOperations.close_circuit_breaker(target)
  end

  @doc """
  Increments the failure count for a target's circuit breaker.

  If the failure count exceeds the threshold (default: 3), opens the circuit breaker.
  """
  @spec increment_circuit_breaker_failures(Target.t(), non_neg_integer()) ::
          {:ok, Target.t()} | {:error, term()}
  def increment_circuit_breaker_failures(%Target{} = target, threshold \\ 3) do
    with {:ok, updated} <- TargetOperations.increment_failures(target) do
      if updated.circuit_breaker_failures >= threshold do
        open_circuit_breaker(updated)
      else
        {:ok, updated}
      end
    end
  end

  @doc """
  Checks if a target's circuit breaker is open.
  """
  @spec circuit_breaker_open?(Target.t()) :: boolean()
  def circuit_breaker_open?(%Target{} = target) do
    Target.circuit_breaker_open?(target)
  end

  @doc """
  Checks if a target can receive commands.

  A target can receive commands if:
  - It's online (or standby)
  - The circuit breaker is not open
  """
  @spec can_command?(Target.t()) :: boolean()
  def can_command?(%Target{} = target) do
    Target.can_command?(target)
  end

  # ===========================================================================
  # Status Operations
  # ===========================================================================

  @doc """
  Sets the target to online status.
  """
  @spec go_online(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def go_online(%Target{} = target) do
    TargetOperations.go_online(target)
  end

  @doc """
  Sets the target to offline status.
  """
  @spec go_offline(Target.t()) :: {:ok, Target.t()} | {:error, term()}
  def go_offline(%Target{} = target) do
    TargetOperations.go_offline(target)
  end

  # ===========================================================================
  # Pipeline Orchestration (Private)
  # ===========================================================================

  defp maybe_start_pipeline(%Target{} = target) do
    case MissionInstance.whereis(target.mission_id) do
      nil ->
        :ok

      _pid ->
        case TargetPipelineSupervisor.start_pipeline(target.mission_id, target) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.warning("Failed to start pipeline for target #{target.id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp maybe_stop_pipeline(%Target{} = target) do
    case MissionInstance.whereis(target.mission_id) do
      nil ->
        :ok

      _pid ->
        case TargetPipelineSupervisor.stop_pipeline(target.mission_id, target.id) do
          :ok ->
            :ok

          {:error, :not_found} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.warning("Failed to stop pipeline for target #{target.id}: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp cleanup_target_commands(%Target{} = target) do
    alias Cadence.Ports.Repository.Commanding.QueueRepository
    alias Cadence.Runtime.Commands.TargetQueue

    case TargetQueue.whereis(target.mission_id, target.id) do
      nil ->
        # Queue not running, cancel via repository
        QueueRepository.impl().cancel_all_pending(target.id)

      _pid ->
        TargetQueue.clear(target.mission_id, target.id)
    end
  end

  # Converts string keys to atoms and normalizes type values for domain entity
  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn
      {"mission_id", v} -> {:mission_id, v}
      {"definition_set_id", v} -> {:definition_set_id, v}
      {"bucket_id", v} -> {:bucket_id, v}
      {"name", v} -> {:name, v}
      {"identifier", v} -> {:identifier, v}
      {"scid", v} -> {:scid, normalize_scid(v)}
      {"type", v} -> {:type, normalize_type(v)}
      {"status", v} -> {:status, normalize_status(v)}
      {"config", v} -> {:config, v}
      {"metadata", v} -> {:metadata, v}
      {"active_limit_set", v} -> {:active_limit_set, v}
      {k, v} when is_atom(k) -> {k, v}
      {_k, _v} = pair -> pair
    end)
    |> Map.new()
    |> then(fn m ->
      # Normalize type and status if they're atoms passed as keys
      m
      |> maybe_normalize_field(:type, &normalize_type/1)
      |> maybe_normalize_field(:status, &normalize_status/1)
      |> maybe_normalize_field(:scid, &normalize_scid/1)
    end)
  end

  defp maybe_normalize_field(map, key, normalizer) do
    case Map.get(map, key) do
      nil -> map
      value -> Map.put(map, key, normalizer.(value))
    end
  end

  defp normalize_type("spacecraft"), do: :spacecraft
  defp normalize_type("ground_station"), do: :ground_station
  defp normalize_type("simulator"), do: :simulator
  defp normalize_type("relay"), do: :relay
  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type(_), do: nil

  defp normalize_status("offline"), do: :offline
  defp normalize_status("online"), do: :online
  defp normalize_status("standby"), do: :standby
  defp normalize_status("fault"), do: :fault
  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status(_), do: :offline

  defp normalize_scid(nil), do: nil
  defp normalize_scid(""), do: nil
  defp normalize_scid(scid) when is_integer(scid), do: scid

  defp normalize_scid(scid) when is_binary(scid) do
    case Integer.parse(scid) do
      {int, ""} -> int
      _ -> scid
    end
  end

  defp normalize_scid(scid), do: scid
end
