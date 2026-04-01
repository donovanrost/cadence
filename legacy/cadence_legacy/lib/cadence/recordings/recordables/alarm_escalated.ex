defmodule Cadence.Recordings.Recordables.AlarmEscalated do
  @moduledoc """
  Recordable for when an alarm severity increases.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alarm_escalateds" do
    field :previous_severity, :string
    field :new_severity, :string
    field :trigger_value, :float

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:previous_severity, :new_severity, :trigger_value])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmEscalated do
  def recording_type(_), do: "AlarmEscalated"
  def aggregate_type(_), do: "Alarm"
  def title(r), do: "Escalated: #{r.previous_severity} -> #{r.new_severity}"
  def status(_), do: "active"
  def severity(r), do: r.new_severity
end
