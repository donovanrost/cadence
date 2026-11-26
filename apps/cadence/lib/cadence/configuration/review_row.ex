defmodule Cadence.Configuration.ReviewRow do
  @moduledoc "A decision on a change set: a reviewer's, or a direct apply's not_required (append-only)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:review_id, :string, autogenerate: false}
  schema "mission_config_reviews" do
    field(:change_set_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:decision, :string)
    field(:actor, :map)
    field(:comment, :string)
    field(:decided_at, :utc_datetime_usec)
    # #117 step 2 (DECISIONS #112): the four-eyes record's required fields.
    field(:subject_version, :integer)
    field(:subject_digest, :string)
    field(:policy_document, :map)
    field(:separated_from, {:array, :string}, default: [])
    field(:admin_mode, :boolean)
  end
end
