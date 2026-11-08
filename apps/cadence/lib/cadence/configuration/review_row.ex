defmodule Cadence.Configuration.ReviewRow do
  @moduledoc "A reviewer decision on a change set in review (append-only)."
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
  end
end
