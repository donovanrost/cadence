defmodule Cadence.MissionModels.EffectiveRevisionRow do
  @moduledoc false
  # "This composition at this authored head, by this compiler version" -> its revision (D1, #541).
  # Unique on the composition, head (NULL-safe) and compiler version, and on revision_id (M2). The
  # version is the revision's own (composite FK); immutable by trigger.
  use Ecto.Schema

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_model_effective_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:composition_id, :string)
    field(:authored_head, :string)
    field(:compiler_version, :string)
    field(:revision_id, :string)

    timestamps()
  end
end
