defmodule Cadence.Runtime.ReplayConflicts.Row do
  @moduledoc "One tripped unit's record (#99 follow-up): see `Cadence.Runtime.ReplayConflicts`."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "replay_id_conflicts" do
    field(:mission_id, :string)
    field(:path, :string)
    field(:unit_key, :string)
    field(:effect_kind, :string)
    field(:effect_id, :string)
    field(:partition_id, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:provider_binding_id, :string)
    field(:stream_key, :string)
    field(:partition_stopped, :boolean, default: false)
    field(:stopped_while, :string)
    field(:first_seen_at, :utc_datetime_usec)
    field(:last_conflict_at, :utc_datetime_usec)
    field(:conflict_count, :integer, default: 1)
    field(:buffer_retained_bytes, :integer)
    field(:buffer_max_bytes, :integer)
    field(:buffer_full_count, :integer)
    field(:buffer_sampled_at, :utc_datetime_usec)
    field(:dropping_since, :utc_datetime_usec)
    field(:acknowledged_at, :utc_datetime_usec)
    field(:acknowledged_by, :map)
    field(:acknowledged_note, :string)
    field(:resolved_at, :utc_datetime_usec)
    timestamps()
  end
end
