defmodule Cadence.Recordings.Recordables.AlarmTriggered do
  @moduledoc """
  Recordable for when an alarm is triggered.

  This is the "rich" recordable for alarms - it contains all the context
  about what caused the alarm and its initial severity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alarm_triggereds" do
    field :alarm_type, :string
    field :severity, :string
    field :source_type, :string
    field :source_id, :string
    field :message, :string
    field :trigger_value, :float
    field :limit_state, :string
    field :alarm_rule_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @required_fields [:alarm_type, :severity, :source_type, :source_id]
  @optional_fields [:message, :trigger_value, :limit_state, :alarm_rule_id]

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmTriggered do
  def recording_type(_), do: "AlarmTriggered"
  def aggregate_type(_), do: "Alarm"
  def title(r), do: r.message || "Alarm Triggered"
  def status(_), do: "active"
  def severity(r), do: r.severity
end
