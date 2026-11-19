defmodule Cadence.Configuration.RevisionEntryRow do
  @moduledoc "One entity changed by a revision, with its before and after documents."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:entry_id, :string, autogenerate: false}
  schema "mission_config_revision_entries" do
    field(:revision_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:revision_number, :integer)
    field(:position, :integer)
    field(:kind, :string)
    field(:entity_id, :string)
    field(:op, :string)
    field(:before, :map)
    field(:after, :map)
    field(:paths, {:array, :string}, default: [])
  end
end
