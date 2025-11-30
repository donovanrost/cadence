defmodule Cadence.Alarms.AlarmEvent do
  @moduledoc """
  Audit log entry for alarm state changes.

  Every change to an alarm is recorded as an event, providing a complete
  audit trail of the alarm's lifecycle.

  ## Event Types

  - `:triggered` - Alarm was created from a violation
  - `:escalated` - Severity increased (e.g., yellow → red)
  - `:deescalated` - Severity decreased (e.g., red → yellow)
  - `:acknowledged` - User acknowledged the alarm
  - `:cleared` - Alarm condition resolved (automatic or manual)
  - `:shelved` - User temporarily silenced the alarm
  - `:unshelved` - Alarm was reactivated (manual or timeout)
  - `:value_updated` - Telemetry value changed while still in violation

  ## State Snapshots

  `previous_state` and `new_state` capture the alarm's state before and after
  the event, enabling full reconstruction of alarm history.

  ## Example

      %AlarmEvent{
        alarm_id: "abc-123",
        event_type: :acknowledged,
        user_id: "user-456",
        note: "Investigating thermal anomaly",
        previous_state: %{"status" => "active"},
        new_state: %{"status" => "acknowledged"}
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Alarms.Alarm
  alias Cadence.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types [
    :triggered,
    :escalated,
    :deescalated,
    :acknowledged,
    :cleared,
    :shelved,
    :unshelved,
    :value_updated
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          alarm_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t() | nil,
          event_type: atom(),
          previous_state: map() | nil,
          new_state: map() | nil,
          note: String.t() | nil,
          trigger_value: float() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "alarm_events" do
    belongs_to :alarm, Alarm
    belongs_to :user, User

    field :event_type, Ecto.Enum, values: @event_types
    field :previous_state, :map
    field :new_state, :map
    field :note, :string
    field :trigger_value, :float

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new alarm event.
  """
  def changeset(alarm_event, attrs) do
    alarm_event
    |> cast(attrs, [
      :alarm_id,
      :user_id,
      :event_type,
      :previous_state,
      :new_state,
      :note,
      :trigger_value
    ])
    |> validate_required([:alarm_id, :event_type])
    |> foreign_key_constraint(:alarm_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates an event struct for a triggered alarm.
  """
  @spec triggered(Alarm.t(), float() | nil) :: map()
  def triggered(%Alarm{} = alarm, trigger_value \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :triggered,
      new_state: alarm_state_snapshot(alarm),
      trigger_value: trigger_value
    }
  end

  @doc """
  Creates an event struct for an escalation.
  """
  @spec escalated(Alarm.t(), map(), float() | nil) :: map()
  def escalated(%Alarm{} = alarm, previous_state, trigger_value \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :escalated,
      previous_state: previous_state,
      new_state: alarm_state_snapshot(alarm),
      trigger_value: trigger_value
    }
  end

  @doc """
  Creates an event struct for a deescalation.
  """
  @spec deescalated(Alarm.t(), map(), float() | nil) :: map()
  def deescalated(%Alarm{} = alarm, previous_state, trigger_value \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :deescalated,
      previous_state: previous_state,
      new_state: alarm_state_snapshot(alarm),
      trigger_value: trigger_value
    }
  end

  @doc """
  Creates an event struct for an acknowledgment.
  """
  @spec acknowledged(Alarm.t(), String.t(), String.t() | nil) :: map()
  def acknowledged(%Alarm{} = alarm, user_id, note \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :acknowledged,
      user_id: user_id,
      previous_state: %{"status" => "active"},
      new_state: alarm_state_snapshot(alarm),
      note: note
    }
  end

  @doc """
  Creates an event struct for clearing an alarm.
  """
  @spec cleared(Alarm.t(), map(), String.t() | nil) :: map()
  def cleared(%Alarm{} = alarm, previous_state, user_id \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :cleared,
      user_id: user_id,
      previous_state: previous_state,
      new_state: alarm_state_snapshot(alarm)
    }
  end

  @doc """
  Creates an event struct for shelving an alarm.
  """
  @spec shelved(Alarm.t(), String.t(), String.t() | nil) :: map()
  def shelved(%Alarm{} = alarm, user_id, reason \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :shelved,
      user_id: user_id,
      previous_state: %{"status" => to_string(alarm.status)},
      new_state: alarm_state_snapshot(alarm),
      note: reason
    }
  end

  @doc """
  Creates an event struct for unshelving an alarm.
  """
  @spec unshelved(Alarm.t(), map(), String.t() | nil) :: map()
  def unshelved(%Alarm{} = alarm, previous_state, user_id \\ nil) do
    %{
      alarm_id: alarm.id,
      event_type: :unshelved,
      user_id: user_id,
      previous_state: previous_state,
      new_state: alarm_state_snapshot(alarm)
    }
  end

  @doc """
  Creates an event struct for a value update.
  """
  @spec value_updated(Alarm.t(), map(), float()) :: map()
  def value_updated(%Alarm{} = alarm, previous_state, trigger_value) do
    %{
      alarm_id: alarm.id,
      event_type: :value_updated,
      previous_state: previous_state,
      new_state: alarm_state_snapshot(alarm),
      trigger_value: trigger_value
    }
  end

  @doc """
  Returns the list of valid event types.
  """
  def valid_event_types, do: @event_types

  # Private functions

  defp alarm_state_snapshot(%Alarm{} = alarm) do
    %{
      "status" => to_string(alarm.status),
      "severity" => to_string(alarm.severity),
      "limit_state" => alarm.limit_state && to_string(alarm.limit_state),
      "current_value" => alarm.current_value
    }
  end
end
