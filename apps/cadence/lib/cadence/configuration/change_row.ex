defmodule Cadence.Configuration.ChangeRow do
  @moduledoc "One staged unit as a user sees it, e.g. \"50 new spacecraft (Block 2)\"."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @states ~w(staged withdrawn discarded applied)

  @primary_key {:change_id, :string, autogenerate: false}
  schema "mission_config_changes" do
    field(:change_set_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:author, :map)
    field(:author_key, :string)
    field(:staged_at, :utc_datetime_usec)
    field(:summary, :string)
    field(:source, :map, default: %{})
    field(:state, :string)
    field(:position, :integer)
    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states
end
