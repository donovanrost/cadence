defmodule Cadence.Recordings.Recordables.AlarmValueUpdated do
  @moduledoc """
  Recordable for when an alarm's trigger value changes while still in violation.

  This tracks value changes during an active alarm without creating
  separate alarm events.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alarm_value_updateds" do
    field :trigger_value, :float
    field :previous_value, :float

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:trigger_value, :previous_value])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmValueUpdated do
  def recording_type(_), do: "AlarmValueUpdated"
  def aggregate_type(_), do: "Alarm"
  def title(r), do: "Value: #{r.trigger_value}"
  def status(_), do: "active"
  def severity(_), do: nil
end
