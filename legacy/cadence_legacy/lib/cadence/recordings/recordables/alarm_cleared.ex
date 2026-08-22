defmodule Cadence.Recordings.Recordables.AlarmCleared do
  @moduledoc """
  Recordable for when an alarm is cleared.

  Captures whether the clear was automatic (condition resolved)
  or manual (operator action).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @clear_types ["automatic", "manual"]

  schema "alarm_cleareds" do
    field :clear_type, :string
    field :final_value, :float

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(recordable, attrs) do
    recordable
    |> cast(attrs, [:clear_type, :final_value])
    |> validate_inclusion(:clear_type, @clear_types)
  end

  def clear_types, do: @clear_types
end

defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.AlarmCleared do
  def recording_type(_), do: "AlarmCleared"
  def aggregate_type(_), do: "Alarm"
  def title(r), do: "Cleared (#{r.clear_type || "unknown"})"
  def status(_), do: "cleared"
  def severity(_), do: nil
end
