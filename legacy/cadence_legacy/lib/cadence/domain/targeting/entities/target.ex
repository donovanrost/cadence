defmodule Cadence.Domain.Targeting.Entities.Target do
  @moduledoc """
  Pure domain entity representing a target (spacecraft, ground station, etc).

  This entity contains all business logic for target management,
  completely independent of any persistence or infrastructure concerns.

  ## Target Types

  - `spacecraft` - An orbiting or in-flight vehicle
  - `ground_station` - A ground-based communication facility
  - `simulator` - A software simulator for testing
  - `relay` - A relay satellite or communication node

  ## Status

  - `offline` - Target is not communicating
  - `online` - Target is actively communicating
  - `standby` - Target is available but not actively communicating
  - `fault` - Target has a detected fault condition

  ## Circuit Breaker

  Implements the circuit breaker pattern for command safety:
  - `closed` - Normal operation, commands flow through
  - `open` - Failure threshold exceeded, commands blocked
  - `half_open` - Testing if target has recovered

  ## Usage

      # Create a new target
      {:ok, target} = Target.new(%{
        mission_id: "mission-uuid",
        definition_set_id: "definition-set-uuid",
        name: "SAT-1",
        identifier: "SAT_001",
        type: :spacecraft
      })

      # Open circuit breaker after failures
      {:ok, target} = Target.open_circuit_breaker(target)

      # Close circuit breaker after recovery
      {:ok, target} = Target.close_circuit_breaker(target)
  """

  alias Cadence.Time, as: CadenceTime

  @type target_type :: :spacecraft | :ground_station | :simulator | :relay
  @type target_status :: :offline | :online | :standby | :fault
  @type circuit_breaker_status :: :closed | :open | :half_open

  @type t :: %__MODULE__{
          id: String.t() | nil,
          mission_id: String.t(),
          definition_set_id: String.t(),
          bucket_id: String.t() | nil,
          name: String.t(),
          identifier: String.t(),
          scid: non_neg_integer() | nil,
          type: target_type(),
          status: target_status(),
          config: map(),
          metadata: map(),
          active_limit_set: String.t(),
          circuit_breaker_status: circuit_breaker_status(),
          circuit_breaker_failures: non_neg_integer(),
          circuit_breaker_opened_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:mission_id, :definition_set_id, :name, :identifier, :type]

  defstruct [
    :id,
    :mission_id,
    :definition_set_id,
    :bucket_id,
    :name,
    :identifier,
    :scid,
    :type,
    :circuit_breaker_opened_at,
    :inserted_at,
    :updated_at,
    status: :offline,
    config: %{},
    metadata: %{},
    active_limit_set: "NOMINAL",
    circuit_breaker_status: :closed,
    circuit_breaker_failures: 0
  ]

  @valid_types [:spacecraft, :ground_station, :simulator, :relay]
  @valid_statuses [:offline, :online, :standby, :fault]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new target with the given attributes.

  Returns `{:ok, target}` if valid, `{:error, reason}` otherwise.

  ## Required Attributes

  - `:mission_id` - The mission this target belongs to
  - `:definition_set_id` - The C&T database definition set
  - `:name` - Human-readable name
  - `:identifier` - Unique identifier within mission (e.g., "SAT_001")
  - `:type` - Target type atom

  ## Optional Attributes

  - `:id` - UUID (generated if not provided)
  - `:status` - Initial status (default: `:offline`)
  - `:config` - Configuration map
  - `:metadata` - Metadata map
  - `:active_limit_set` - Active limit set name (default: "NOMINAL")
  - `:bucket_id` - Associated bucket for hierarchical grouping
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, mission_id} <- validate_required(attrs, :mission_id),
         {:ok, definition_set_id} <- validate_required(attrs, :definition_set_id),
         {:ok, name} <- validate_required(attrs, :name),
         {:ok, identifier} <- validate_identifier(attrs),
         {:ok, type} <- validate_type(attrs),
         {:ok, scid} <- validate_scid(attrs, type) do
      target = %__MODULE__{
        id: Map.get(attrs, :id),
        mission_id: mission_id,
        definition_set_id: definition_set_id,
        bucket_id: Map.get(attrs, :bucket_id),
        name: name,
        identifier: identifier,
        scid: scid,
        type: type,
        status: Map.get(attrs, :status, :offline) |> normalize_status(),
        config: Map.get(attrs, :config, %{}),
        metadata: Map.get(attrs, :metadata, %{}),
        active_limit_set: Map.get(attrs, :active_limit_set, "NOMINAL"),
        circuit_breaker_status: :closed,
        circuit_breaker_failures: 0,
        circuit_breaker_opened_at: nil,
        inserted_at: Map.get(attrs, :inserted_at),
        updated_at: Map.get(attrs, :updated_at)
      }

      {:ok, target}
    end
  end

  @doc """
  Updates a target with the given attributes.

  Only allows updating certain fields (not mission_id, definition_set_id, or identifier).
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = target, attrs) when is_map(attrs) do
    {:ok, target}
    |> maybe_update_name(attrs)
    |> maybe_update_status(attrs)
    |> maybe_update_config(attrs)
    |> maybe_update_metadata(attrs)
    |> maybe_update_active_limit_set(attrs)
    |> maybe_update_bucket_id(attrs)
    |> maybe_update_definition_set_id(attrs)
    |> maybe_update_scid(attrs)
  end

  # ===========================================================================
  # Circuit Breaker Operations
  # ===========================================================================

  @doc """
  Opens the circuit breaker for a target after command failures.

  When open, commands should not be sent to this target.
  """
  @spec open_circuit_breaker(t()) :: {:ok, t()}
  def open_circuit_breaker(%__MODULE__{} = target) do
    {:ok,
     %{
       target
       | circuit_breaker_status: :open,
         circuit_breaker_opened_at: CadenceTime.now()
     }}
  end

  @doc """
  Closes the circuit breaker, resetting failure count.

  Called when the target has recovered and can accept commands again.
  """
  @spec close_circuit_breaker(t()) :: {:ok, t()}
  def close_circuit_breaker(%__MODULE__{} = target) do
    {:ok,
     %{
       target
       | circuit_breaker_status: :closed,
         circuit_breaker_failures: 0,
         circuit_breaker_opened_at: nil
     }}
  end

  @doc """
  Sets the circuit breaker to half-open for testing recovery.

  In half-open state, a single command is allowed through to test
  if the target has recovered.
  """
  @spec half_open_circuit_breaker(t()) :: {:ok, t()}
  def half_open_circuit_breaker(%__MODULE__{} = target) do
    {:ok, %{target | circuit_breaker_status: :half_open}}
  end

  @doc """
  Increments the failure count for circuit breaker logic.

  Returns the updated target. The caller should check if the failure
  threshold is exceeded and open the circuit breaker if needed.
  """
  @spec increment_failures(t()) :: {:ok, t()}
  def increment_failures(%__MODULE__{circuit_breaker_failures: failures} = target) do
    {:ok, %{target | circuit_breaker_failures: failures + 1}}
  end

  @doc """
  Resets the failure count without changing circuit breaker status.
  """
  @spec reset_failures(t()) :: {:ok, t()}
  def reset_failures(%__MODULE__{} = target) do
    {:ok, %{target | circuit_breaker_failures: 0}}
  end

  # ===========================================================================
  # Status Operations
  # ===========================================================================

  @doc """
  Sets the target status.
  """
  @spec set_status(t(), target_status()) :: {:ok, t()} | {:error, {:invalid_status, term()}}
  def set_status(%__MODULE__{} = target, status) when status in @valid_statuses do
    {:ok, %{target | status: status}}
  end

  def set_status(_target, status), do: {:error, {:invalid_status, status}}

  @doc """
  Sets the target to online status.
  """
  @spec go_online(t()) :: {:ok, t()}
  def go_online(%__MODULE__{} = target), do: {:ok, %{target | status: :online}}

  @doc """
  Sets the target to offline status.
  """
  @spec go_offline(t()) :: {:ok, t()}
  def go_offline(%__MODULE__{} = target), do: {:ok, %{target | status: :offline}}

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns true if the circuit breaker is open (blocking commands).
  """
  @spec circuit_breaker_open?(t()) :: boolean()
  def circuit_breaker_open?(%__MODULE__{circuit_breaker_status: :open}), do: true
  def circuit_breaker_open?(_), do: false

  @doc """
  Returns true if the circuit breaker is closed (allowing commands).
  """
  @spec circuit_breaker_closed?(t()) :: boolean()
  def circuit_breaker_closed?(%__MODULE__{circuit_breaker_status: :closed}), do: true
  def circuit_breaker_closed?(_), do: false

  @doc """
  Returns true if the target is online.
  """
  @spec online?(t()) :: boolean()
  def online?(%__MODULE__{status: :online}), do: true
  def online?(_), do: false

  @doc """
  Returns true if the target can receive commands.

  A target can receive commands if:
  - It's online (or standby)
  - The circuit breaker is not open
  """
  @spec can_command?(t()) :: boolean()
  def can_command?(%__MODULE__{status: status, circuit_breaker_status: cb_status}) do
    status in [:online, :standby] and cb_status != :open
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp validate_required(attrs, field) do
    case Map.get(attrs, field) do
      nil -> {:error, {:required, field}}
      "" -> {:error, {:required, field}}
      value -> {:ok, value}
    end
  end

  defp validate_identifier(attrs) do
    case Map.get(attrs, :identifier) do
      nil ->
        {:error, {:required, :identifier}}

      identifier when is_binary(identifier) ->
        if Regex.match?(~r/^[A-Z0-9_-]+$/, identifier) do
          {:ok, identifier}
        else
          {:error, {:invalid_identifier, identifier}}
        end

      identifier ->
        {:error, {:invalid_identifier, identifier}}
    end
  end

  defp validate_type(attrs) do
    type = Map.get(attrs, :type) |> normalize_type()

    if type in @valid_types do
      {:ok, type}
    else
      {:error, {:invalid_type, type}}
    end
  end

  defp validate_scid(attrs, type) when is_map(attrs) do
    scid = Map.get(attrs, :scid)

    case validate_scid_value(scid, type) do
      :ok -> {:ok, scid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_scid_value(nil, :spacecraft), do: {:error, {:missing, :scid}}
  defp validate_scid_value(nil, _type), do: :ok

  defp validate_scid_value(scid, _type) when is_integer(scid) and scid >= 0 and scid < 1024,
    do: :ok

  defp validate_scid_value(scid, _type), do: {:error, {:invalid, :scid, scid}}

  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type("spacecraft"), do: :spacecraft
  defp normalize_type("ground_station"), do: :ground_station
  defp normalize_type("simulator"), do: :simulator
  defp normalize_type("relay"), do: :relay
  defp normalize_type(other), do: other

  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status("offline"), do: :offline
  defp normalize_status("online"), do: :online
  defp normalize_status("standby"), do: :standby
  defp normalize_status("fault"), do: :fault
  defp normalize_status(_), do: :offline

  defp maybe_update_name({:ok, target}, attrs) do
    case Map.get(attrs, :name) do
      nil -> {:ok, target}
      "" -> {:error, {:required, :name}}
      name -> {:ok, %{target | name: name}}
    end
  end

  defp maybe_update_name(error, _), do: error

  defp maybe_update_status({:ok, target}, attrs) do
    case Map.get(attrs, :status) do
      nil -> {:ok, target}
      status -> set_status(target, normalize_status(status))
    end
  end

  defp maybe_update_status(error, _), do: error

  defp maybe_update_config({:ok, target}, attrs) do
    case Map.get(attrs, :config) do
      nil -> {:ok, target}
      config when is_map(config) -> {:ok, %{target | config: config}}
      _ -> {:error, {:invalid, :config}}
    end
  end

  defp maybe_update_config(error, _), do: error

  defp maybe_update_metadata({:ok, target}, attrs) do
    case Map.get(attrs, :metadata) do
      nil -> {:ok, target}
      metadata when is_map(metadata) -> {:ok, %{target | metadata: metadata}}
      _ -> {:error, {:invalid, :metadata}}
    end
  end

  defp maybe_update_metadata(error, _), do: error

  defp maybe_update_active_limit_set({:ok, target}, attrs) do
    case Map.get(attrs, :active_limit_set) do
      nil -> {:ok, target}
      limit_set when is_binary(limit_set) -> {:ok, %{target | active_limit_set: limit_set}}
      _ -> {:error, {:invalid, :active_limit_set}}
    end
  end

  defp maybe_update_active_limit_set(error, _), do: error

  defp maybe_update_bucket_id({:ok, target}, attrs) do
    case Map.get(attrs, :bucket_id) do
      nil -> {:ok, target}
      bucket_id -> {:ok, %{target | bucket_id: bucket_id}}
    end
  end

  defp maybe_update_bucket_id(error, _), do: error

  defp maybe_update_definition_set_id({:ok, target}, attrs) do
    case Map.get(attrs, :definition_set_id) do
      nil -> {:ok, target}
      definition_set_id -> {:ok, %{target | definition_set_id: definition_set_id}}
    end
  end

  defp maybe_update_definition_set_id(error, _), do: error

  defp maybe_update_scid({:ok, target}, attrs) do
    case Map.fetch(attrs, :scid) do
      :error ->
        {:ok, target}

      {:ok, scid} ->
        case validate_scid_value(scid, target.type) do
          :ok -> {:ok, %{target | scid: scid}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp maybe_update_scid(error, _), do: error
end

# Bucketable protocol implementation for hierarchical organization
defimpl Cadence.Buckets.Bucketable, for: Cadence.Domain.Targeting.Entities.Target do
  @moduledoc false

  @doc """
  Targets are organized under :target bucket type.
  """
  def bucket_type(_), do: :target

  @doc """
  Stable identifier for database storage.
  """
  def bucketable_type(_), do: :target

  @doc """
  Uses the target's name for the bucket name.
  """
  def bucket_name(target), do: target.name

  @doc """
  Targets are persistent, not time-bounded.
  """
  def bucket_started_at(_), do: nil

  @doc """
  Targets are persistent, not time-bounded.
  """
  def bucket_ended_at(_), do: nil

  @doc """
  Returns the parent bucket ID.

  Targets can be organized under a TargetGroup bucket (via bucket_id field)
  or directly under a Mission.
  """
  def parent_bucket_id(target), do: target.bucket_id

  @doc """
  Returns target metadata for the bucket.
  """
  def bucket_metadata(target), do: target.metadata || %{}
end
