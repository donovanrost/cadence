defmodule Cadence.Catalog.ChangeSetSpacecraft.Row do
  @moduledoc "One spacecraft changed by a change set's generation at a revision."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "activation_change_set_spacecraft" do
    field(:mission_id, :string, primary_key: true)
    field(:change_set_id, :string, primary_key: true)
    field(:revision, :integer, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:organization_id, :string)
  end
end
