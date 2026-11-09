defmodule Cadence.Alarms.EpisodeEventRow do
  @moduledoc "Append-only lifecycle event of an alarm episode (the Investigate event log)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @kinds ~w(raised escalated deescalated acknowledged assigned unassigned note handed_off cleared)

  @primary_key {:event_id, :string, autogenerate: false}
  schema "alarm_episode_events" do
    field(:episode_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:kind, :string)
    field(:actor, :map)
    field(:at, :utc_datetime_usec)
    field(:source_ref, :string)
    field(:payload, :map, default: %{})
  end

  def kinds, do: @kinds
end
