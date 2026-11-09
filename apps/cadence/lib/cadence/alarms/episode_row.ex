defmodule Cadence.Alarms.EpisodeRow do
  @moduledoc "One excursion of one subject out of limits, from first crossing until back in limits."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:episode_id, :string, autogenerate: false}
  schema "alarm_episodes" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:spacecraft_scope_id, :string)
    field(:source, :string)
    field(:subject_key, :string)
    field(:parameter_ref, :string)
    field(:point_name, :string)
    field(:context, :map, default: %{})
    field(:severity, :string)
    field(:peak_severity, :string)
    field(:source_state, :string)
    field(:state, :string)
    field(:opened_at, :utc_datetime_usec)
    field(:opened_by_ref, :string)
    field(:first_value, :map)
    field(:last_value, :map)
    field(:last_observed_at, :utc_datetime_usec)
    field(:last_evaluated_at, :utc_datetime_usec)
    field(:cleared_at, :utc_datetime_usec)
    field(:cleared_by_ref, :string)
    field(:cleared_unacknowledged, :boolean, default: false)
    field(:acknowledged_at, :utc_datetime_usec)
    field(:acknowledged_by, :map)
    field(:assignee, :map)
    field(:assigned_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec)
  end
end
