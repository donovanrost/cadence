defmodule Cadence.Configuration.OpRow do
  @moduledoc "One entity operation inside a staged change."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:op_id, :string, autogenerate: false}
  schema "mission_config_ops" do
    field(:change_id, :string)
    field(:change_set_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:position, :integer)
    field(:kind, :string)
    field(:entity_id, :string)
    field(:action, :string)
    field(:payload, :map, default: %{})
    field(:base, :map, default: %{})
    field(:touched_paths, {:array, :string}, default: [])
  end
end
