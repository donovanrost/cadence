defmodule Cadence.Alarms.Alarm do
  @moduledoc """
  An alarm record representing an anomalous condition that requires attention.

  ## Lifecycle

  Alarms follow this state machine:

      ┌─────────┐    violation    ┌─────────┐    user action    ┌──────────────┐
      │ (none)  │ ──────────────► │ ACTIVE  │ ─────────────────► │ ACKNOWLEDGED │
      └─────────┘                 └─────────┘                    └──────────────┘
                                       │                               │
                                       │ recovery                      │ recovery
                                       ▼                               ▼
                                  ┌─────────┐                    ┌──────────┐
                                  │ CLEARED │◄───────────────────│ CLEARED  │
                                  └─────────┘                    └──────────┘

                                       │
                                  user action
                                       ▼
                                  ┌─────────┐
                                  │ SHELVED │ (temporarily silenced)
                                  └─────────┘

  ## Status Values

  - `:active` - Alarm condition is present and not acknowledged
  - `:acknowledged` - User has acknowledged but condition persists
  - `:shelved` - Temporarily silenced until `shelved_until` time
  - `:cleared` - Condition has resolved (terminal state)

  ## Deduplication

  Only one active/acknowledged/shelved alarm per source exists at a time.
  If a user clears an alarm and the condition recurs, a new alarm is created.

  ## Example

      %Alarm{
        alarm_type: "telemetry_limit",
        severity: :critical,
        status: :active,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp",
        limit_state: :red,
        current_value: 105.2,
        message: "HEALTH.cpu_temp exceeded RED threshold (105.2°C)"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Organizations.Organization
  alias Cadence.Missions.Mission
  alias Cadence.Targets.Target
  alias Cadence.Accounts.User
  alias Cadence.Alarms.AlarmRule

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @status_values [:active, :acknowledged, :shelved, :cleared]
  @severity_values [:info, :warning, :critical]
  @limit_state_values [:yellow, :red, :blue]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          organization_id: Ecto.UUID.t(),
          mission_id: Ecto.UUID.t(),
          target_id: Ecto.UUID.t() | nil,
          alarm_rule_id: Ecto.UUID.t() | nil,
          alarm_type: String.t(),
          severity: :info | :warning | :critical,
          status: :active | :acknowledged | :shelved | :cleared,
          source_type: String.t(),
          source_id: String.t(),
          limit_state: :yellow | :red | :blue | nil,
          current_value: float() | nil,
          message: String.t() | nil,
          triggered_at: DateTime.t(),
          cleared_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "alarms" do
    belongs_to :organization, Organization
    belongs_to :mission, Mission
    belongs_to :target, Target
    belongs_to :alarm_rule, AlarmRule

    # Classification
    field :alarm_type, :string
    field :severity, Ecto.Enum, values: @severity_values
    field :status, Ecto.Enum, values: @status_values, default: :active

    # Source identification
    field :source_type, :string
    field :source_id, :string

    # Telemetry-specific state
    field :limit_state, Ecto.Enum, values: @limit_state_values
    field :current_value, :float
    field :message, :string

    # Acknowledgment
    belongs_to :acknowledged_by, User, foreign_key: :acknowledged_by_id
    field :acknowledged_at, :utc_datetime
    field :acknowledgment_note, :string

    # Shelving
    belongs_to :shelved_by, User, foreign_key: :shelved_by_id
    field :shelved_at, :utc_datetime
    field :shelved_until, :utc_datetime
    field :shelve_reason, :string

    # Lifecycle
    field :triggered_at, :utc_datetime_usec
    field :cleared_at, :utc_datetime_usec
    field :last_value_at, :utc_datetime_usec

    # Metadata
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new alarm.
  """
  def changeset(alarm, attrs) do
    alarm
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :target_id,
      :alarm_rule_id,
      :alarm_type,
      :severity,
      :status,
      :source_type,
      :source_id,
      :limit_state,
      :current_value,
      :message,
      :triggered_at,
      :metadata
    ])
    |> validate_required([
      :organization_id,
      :mission_id,
      :alarm_type,
      :severity,
      :source_type,
      :source_id,
      :triggered_at
    ])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:target_id)
    |> foreign_key_constraint(:alarm_rule_id)
  end

  @doc """
  Changeset for acknowledging an alarm.
  """
  def acknowledge_changeset(alarm, attrs) do
    alarm
    |> cast(attrs, [:acknowledged_by_id, :acknowledged_at, :acknowledgment_note])
    |> put_change(:status, :acknowledged)
    |> validate_required([:acknowledged_by_id, :acknowledged_at])
  end

  @doc """
  Changeset for shelving an alarm.
  """
  def shelve_changeset(alarm, attrs) do
    alarm
    |> cast(attrs, [:shelved_by_id, :shelved_at, :shelved_until, :shelve_reason])
    |> put_change(:status, :shelved)
    |> validate_required([:shelved_by_id, :shelved_at, :shelved_until])
  end

  @doc """
  Changeset for unshelving an alarm (returns to active or acknowledged).
  """
  def unshelve_changeset(alarm, previous_status) do
    status = if alarm.acknowledged_at, do: :acknowledged, else: :active

    alarm
    |> change()
    |> put_change(:status, previous_status || status)
    |> put_change(:shelved_at, nil)
    |> put_change(:shelved_until, nil)
    |> put_change(:shelve_reason, nil)
  end

  @doc """
  Changeset for clearing an alarm.
  """
  def clear_changeset(alarm, attrs) do
    alarm
    |> cast(attrs, [:cleared_at])
    |> put_change(:status, :cleared)
    |> validate_required([:cleared_at])
  end

  @doc """
  Changeset for updating the current value (while alarm remains active).
  """
  def update_value_changeset(alarm, attrs) do
    alarm
    |> cast(attrs, [:current_value, :limit_state, :last_value_at, :severity, :message])
  end

  @doc """
  Returns true if the alarm is in a non-terminal state.
  """
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: status}) do
    status in [:active, :acknowledged, :shelved]
  end

  @doc """
  Returns true if the alarm is shelved and the shelve period has expired.
  """
  @spec shelve_expired?(t()) :: boolean()
  def shelve_expired?(%__MODULE__{status: :shelved, shelved_until: shelved_until}) do
    DateTime.compare(DateTime.utc_now(), shelved_until) == :gt
  end

  def shelve_expired?(_), do: false

  @doc """
  Returns the list of valid status values.
  """
  def valid_statuses, do: @status_values

  @doc """
  Returns the list of valid severity values.
  """
  def valid_severities, do: @severity_values
end
