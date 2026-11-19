defmodule Cadence.Jobs.OutcomeResolutionRow do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:item_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "job_outcome_resolutions" do
    field(:job_id, :string)
    field(:attempt, :integer)
    field(:mission_id, :string)
    field(:job_type, :string)
    field(:action, :string)
    field(:actor, :map)
    field(:note, :string)
    field(:resolved_at, :utc_datetime_usec)

    timestamps()
  end

  @fields [
    :item_id,
    :job_id,
    :attempt,
    :mission_id,
    :job_type,
    :action,
    :actor,
    :note,
    :resolved_at
  ]

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(@fields -- [:note])
    |> validate_inclusion(:action, ["retried", "closed"])
    |> unique_constraint(:item_id, name: :job_outcome_resolutions_pkey)
  end
end
