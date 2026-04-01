defmodule Cadence.Domain.Alerting.Entities.Alarm do
  @moduledoc """
  Pure domain entity representing an alarm.

  This entity contains all business logic for alarm lifecycle management,
  completely independent of any persistence or infrastructure concerns.

  ## Lifecycle

  Alarms follow a state machine:
  - `:active` - Alarm triggered, awaiting acknowledgment
  - `:acknowledged` - User acknowledged, condition persists
  - `:shelved` - Temporarily silenced until specified time
  - `:cleared` - Condition resolved (terminal state)

  ## Immutability

  All operations return a new alarm struct rather than mutating in place.
  This makes the entity easy to test and reason about.

  ## Usage

      # Create a new alarm
      {:ok, alarm} = Alarm.new(%{
        id: "uuid",
        organization_id: "org-uuid",
        mission_id: "mission-uuid",
        alarm_type: "telemetry_limit",
        severity: :critical,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp",
        triggered_at: Cadence.Time.now()
      })

      # Acknowledge the alarm
      {:ok, acknowledged} = Alarm.acknowledge(alarm, "user-uuid", "Investigating issue")

      # Shelve for 30 minutes
      {:ok, shelved} = Alarm.shelve(acknowledged, "user-uuid", 30, "Known transient")

      # Clear the alarm
      {:ok, cleared} = Alarm.clear(shelved)
  """

  alias Cadence.Domain.Alerting.ValueObjects.{AlarmStatus, Severity}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          organization_id: String.t(),
          mission_id: String.t(),
          target_id: String.t() | nil,
          alarm_rule_id: String.t() | nil,
          alarm_type: String.t(),
          severity: Severity.t(),
          status: AlarmStatus.t(),
          source_type: String.t(),
          source_id: String.t(),
          source_origin: :rule | :mission_db | :manual,
          limit_state: :yellow | :red | :blue | nil,
          current_value: float() | nil,
          message: String.t() | nil,
          triggered_at: DateTime.t(),
          acknowledged_at: DateTime.t() | nil,
          acknowledged_by_id: String.t() | nil,
          acknowledgment_note: String.t() | nil,
          shelved_at: DateTime.t() | nil,
          shelved_by_id: String.t() | nil,
          shelved_until: DateTime.t() | nil,
          shelve_reason: String.t() | nil,
          cleared_at: DateTime.t() | nil,
          last_value_at: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys [
    :organization_id,
    :mission_id,
    :alarm_type,
    :severity,
    :source_type,
    :source_id,
    :triggered_at
  ]

  defstruct [
    :id,
    :organization_id,
    :mission_id,
    :target_id,
    :alarm_rule_id,
    :alarm_type,
    :severity,
    :status,
    :source_type,
    :source_id,
    :source_origin,
    :limit_state,
    :current_value,
    :message,
    :triggered_at,
    :acknowledged_at,
    :acknowledged_by_id,
    :acknowledgment_note,
    :shelved_at,
    :shelved_by_id,
    :shelved_until,
    :shelve_reason,
    :cleared_at,
    :last_value_at,
    metadata: %{}
  ]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new alarm with the given attributes.

  Returns `{:ok, alarm}` if valid, `{:error, reason}` otherwise.

  ## Required Attributes

  - `:organization_id` - The organization this alarm belongs to
  - `:mission_id` - The mission this alarm is associated with
  - `:alarm_type` - Type of alarm (e.g., "telemetry_limit", "interface_disconnect")
  - `:severity` - `:info`, `:warning`, or `:critical`
  - `:source_type` - Type of source (e.g., "telemetry_item", "interface")
  - `:source_id` - Identifier of the source
  - `:triggered_at` - When the alarm condition was detected

  ## Optional Attributes

  - `:id` - UUID (generated if not provided)
  - `:target_id` - Associated spacecraft/target
  - `:alarm_rule_id` - Rule that triggered this alarm
  - `:message` - Human-readable description
  - `:current_value` - Current value that triggered the alarm
  - `:limit_state` - `:yellow`, `:red`, or `:blue` for limit violations
  - `:metadata` - Additional contextual data
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_severity(attrs),
         :ok <- validate_source_origin(attrs) do
      alarm = %__MODULE__{
        id: Map.get(attrs, :id),
        organization_id: Map.fetch!(attrs, :organization_id),
        mission_id: Map.fetch!(attrs, :mission_id),
        target_id: Map.get(attrs, :target_id),
        alarm_rule_id: Map.get(attrs, :alarm_rule_id),
        alarm_type: Map.fetch!(attrs, :alarm_type),
        severity: Map.fetch!(attrs, :severity),
        status: AlarmStatus.initial(),
        source_type: Map.fetch!(attrs, :source_type),
        source_id: Map.fetch!(attrs, :source_id),
        source_origin: Map.get(attrs, :source_origin, :rule),
        limit_state: Map.get(attrs, :limit_state),
        current_value: Map.get(attrs, :current_value),
        message: Map.get(attrs, :message),
        triggered_at: Map.fetch!(attrs, :triggered_at),
        last_value_at: Map.get(attrs, :last_value_at),
        metadata: Map.get(attrs, :metadata, %{})
      }

      {:ok, alarm}
    end
  end

  # ===========================================================================
  # State Transitions
  # ===========================================================================

  @doc """
  Acknowledges an alarm.

  Transitions the alarm from `:active` or `:shelved` to `:acknowledged`.
  Records who acknowledged it and when, with an optional note.

  ## Parameters

  - `alarm` - The alarm to acknowledge
  - `user_id` - ID of the user acknowledging (nil for system actions)
  - `note` - Optional acknowledgment note

  ## Returns

  - `{:ok, alarm}` - Successfully acknowledged
  - `{:error, {:invalid_transition, from, :acknowledged}}` - Invalid transition
  """
  @spec acknowledge(t(), String.t() | nil, String.t() | nil) ::
          {:ok, t()} | {:error, {:invalid_transition, atom(), atom()}}
  def acknowledge(%__MODULE__{status: status} = alarm, user_id, note \\ nil) do
    with :ok <- AlarmStatus.validate_transition(status, :acknowledged) do
      {:ok,
       %{
         alarm
         | status: :acknowledged,
           acknowledged_at: Cadence.Time.now(),
           acknowledged_by_id: user_id,
           acknowledgment_note: note
       }}
    end
  end

  @doc """
  Shelves an alarm for a specified duration.

  Temporarily silences the alarm until `shelved_until` time.
  When the shelve period expires, the alarm should return to its previous state.

  ## Parameters

  - `alarm` - The alarm to shelve
  - `user_id` - ID of the user shelving (nil for system actions)
  - `duration_minutes` - How long to shelve (in minutes)
  - `reason` - Optional reason for shelving

  ## Returns

  - `{:ok, alarm}` - Successfully shelved
  - `{:error, {:invalid_transition, from, :shelved}}` - Invalid transition
  - `{:error, :invalid_duration}` - Duration must be positive
  """
  @spec shelve(t(), String.t() | nil, pos_integer(), String.t() | nil) ::
          {:ok, t()} | {:error, term()}
  def shelve(%__MODULE__{status: status} = alarm, user_id, duration_minutes, reason \\ nil) do
    with :ok <- validate_duration(duration_minutes),
         :ok <- AlarmStatus.validate_transition(status, :shelved) do
      now = Cadence.Time.now()
      shelved_until = DateTime.add(now, duration_minutes * 60, :second)

      {:ok,
       %{
         alarm
         | status: :shelved,
           shelved_at: now,
           shelved_by_id: user_id,
           shelved_until: shelved_until,
           shelve_reason: reason
       }}
    end
  end

  @doc """
  Unshelves an alarm, returning it to active or acknowledged state.

  The target state depends on whether the alarm was previously acknowledged:
  - If acknowledged_at is set -> returns to `:acknowledged`
  - Otherwise -> returns to `:active`

  ## Parameters

  - `alarm` - The alarm to unshelve
  - `target_status` - Optional explicit target status (`:active` or `:acknowledged`)
  """
  @spec unshelve(t(), AlarmStatus.t() | nil) :: {:ok, t()} | {:error, term()}
  def unshelve(alarm, target_status \\ nil)

  def unshelve(%__MODULE__{status: :shelved} = alarm, target_status) do
    # Determine target status based on acknowledgment history
    status =
      target_status ||
        if alarm.acknowledged_at do
          :acknowledged
        else
          :active
        end

    with :ok <- AlarmStatus.validate_transition(:shelved, status) do
      {:ok,
       %{
         alarm
         | status: status,
           shelved_at: nil,
           shelved_until: nil,
           shelve_reason: nil
       }}
    end
  end

  def unshelve(%__MODULE__{status: status}, _) do
    {:error, {:not_shelved, status}}
  end

  @doc """
  Clears an alarm.

  Transitions to the terminal `:cleared` state, indicating the
  alarm condition has been resolved.

  ## Parameters

  - `alarm` - The alarm to clear
  """
  @spec clear(t()) :: {:ok, t()} | {:error, {:invalid_transition, atom(), atom()}}
  def clear(%__MODULE__{status: status} = alarm) do
    with :ok <- AlarmStatus.validate_transition(status, :cleared) do
      {:ok,
       %{
         alarm
         | status: :cleared,
           cleared_at: Cadence.Time.now()
       }}
    end
  end

  # ===========================================================================
  # Value Updates
  # ===========================================================================

  @doc """
  Updates the current value of an alarm.

  Used when telemetry continues to violate limits - updates the value
  without changing the alarm state.

  Optionally escalates severity if the new value is worse.
  """
  @spec update_value(t(), float(), keyword()) :: {:ok, t()}
  def update_value(%__MODULE__{} = alarm, value, opts \\ []) do
    now = Cadence.Time.now()
    new_severity = Keyword.get(opts, :severity)
    new_limit_state = Keyword.get(opts, :limit_state)
    new_message = Keyword.get(opts, :message)

    alarm =
      alarm
      |> Map.put(:current_value, value)
      |> Map.put(:last_value_at, now)
      |> maybe_update(:severity, new_severity)
      |> maybe_update(:limit_state, new_limit_state)
      |> maybe_update(:message, new_message)

    {:ok, alarm}
  end

  @doc """
  Escalates the severity of an alarm.

  Only allows escalation to a more severe level (info -> warning -> critical).
  """
  @spec escalate(t(), Severity.t()) :: {:ok, t()} | {:error, :cannot_deescalate}
  def escalate(%__MODULE__{severity: current} = alarm, new_severity) do
    if Severity.more_severe?(new_severity, current) do
      {:ok, %{alarm | severity: new_severity}}
    else
      {:error, :cannot_deescalate}
    end
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns true if the alarm is in an active (non-cleared) state.
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}) do
    AlarmStatus.active?(status)
  end

  @doc """
  Returns true if the alarm is in a terminal state.
  """
  @spec cleared?(t()) :: boolean()
  def cleared?(%__MODULE__{status: :cleared}), do: true
  def cleared?(_), do: false

  @doc """
  Returns true if the alarm is shelved and the shelve period has expired.
  """
  @spec shelve_expired?(t()) :: boolean()
  def shelve_expired?(%__MODULE__{status: :shelved, shelved_until: shelved_until})
      when not is_nil(shelved_until) do
    DateTime.compare(Cadence.Time.now(), shelved_until) == :gt
  end

  def shelve_expired?(_), do: false

  @doc """
  Returns true if the alarm is acknowledged (either explicitly or via shelving).
  """
  @spec acknowledged?(t()) :: boolean()
  def acknowledged?(%__MODULE__{acknowledged_at: ack_at}) when not is_nil(ack_at), do: true
  def acknowledged?(_), do: false

  @doc """
  Returns the source identifier as a tuple for matching.
  """
  @spec source_key(t()) :: {String.t(), String.t()}
  def source_key(%__MODULE__{source_type: type, source_id: id}) do
    {type, id}
  end

  @doc """
  Returns how long the alarm has been active (since triggered).
  """
  @spec duration(t()) :: integer()
  def duration(%__MODULE__{triggered_at: triggered_at}) do
    DateTime.diff(Cadence.Time.now(), triggered_at, :second)
  end

  @doc """
  Returns how long until the shelve period expires.

  Returns nil if not shelved or no shelve_until set.
  Returns negative value if already expired.
  """
  @spec shelve_remaining_seconds(t()) :: integer() | nil
  def shelve_remaining_seconds(%__MODULE__{status: :shelved, shelved_until: shelved_until})
      when not is_nil(shelved_until) do
    DateTime.diff(shelved_until, Cadence.Time.now(), :second)
  end

  def shelve_remaining_seconds(_), do: nil

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @required_fields [
    :organization_id,
    :mission_id,
    :alarm_type,
    :severity,
    :source_type,
    :source_id,
    :triggered_at
  ]

  defp validate_required(attrs) do
    missing =
      @required_fields
      |> Enum.filter(fn field -> is_nil(Map.get(attrs, field)) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  defp validate_severity(%{severity: severity}) do
    Severity.validate(severity)
  end

  defp validate_source_origin(%{source_origin: origin})
       when origin in [:rule, :mission_db, :manual] do
    :ok
  end

  defp validate_source_origin(%{source_origin: origin}) do
    {:error, {:invalid_source_origin, origin}}
  end

  defp validate_source_origin(_), do: :ok

  defp validate_duration(minutes) when is_integer(minutes) and minutes > 0, do: :ok
  defp validate_duration(_), do: {:error, :invalid_duration}

  defp maybe_update(alarm, _key, nil), do: alarm
  defp maybe_update(alarm, key, value), do: Map.put(alarm, key, value)
end
