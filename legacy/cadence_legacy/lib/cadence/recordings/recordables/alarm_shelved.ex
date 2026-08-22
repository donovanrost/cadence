defmodule Cadence.Recordings.Recordables.AlarmShelved do
  @moduledoc """
  Recordable for when an alarm is shelved (temporarily silenced).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "alarm_shelveds" do
    field :shelve_until, :utc_datetime_usec
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:shelve_until, :reason])
  end
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmShelved do
  def recording_type(_), do: "AlarmShelved"
  def aggregate_type(_), do: "Alarm"
  def title(_), do: "Alarm Shelved"
  def status(_), do: "shelved"
  def severity(_), do: nil
end
