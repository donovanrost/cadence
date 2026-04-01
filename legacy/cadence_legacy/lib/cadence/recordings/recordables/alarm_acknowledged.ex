defmodule Cadence.Recordings.Recordables.AlarmAcknowledged do
  @moduledoc """
  Recordable for when an alarm is acknowledged.

  Minimal recordable - the actor is captured in the recording itself.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alarm_acknowledgeds" do
    field :note, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:note])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmAcknowledged do
  def recording_type(_), do: "AlarmAcknowledged"
  def aggregate_type(_), do: "Alarm"
  def title(_), do: "Alarm Acknowledged"
  def status(_), do: "acknowledged"
  def severity(_), do: nil
end
