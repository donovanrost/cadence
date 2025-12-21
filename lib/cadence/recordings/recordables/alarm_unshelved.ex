defmodule Cadence.Recordings.Recordables.AlarmUnshelved do
  @moduledoc """
  Recordable for when an alarm is unshelved (reactivated).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @unshelve_types ["manual", "timeout"]

  schema "alarm_unshelveds" do
    field :unshelve_type, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:unshelve_type])
    |> validate_inclusion(:unshelve_type, @unshelve_types)
  end

  def unshelve_types, do: @unshelve_types
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmUnshelved do
  def recording_type(_), do: "AlarmUnshelved"
  def aggregate_type(_), do: "Alarm"
  def title(r), do: "Unshelved (#{r.unshelve_type || "unknown"})"
  def status(_), do: "active"
  def severity(_), do: nil
end
