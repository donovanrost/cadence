defmodule Cadence.SpacecraftStore.OverrideRow do
  @moduledoc "One spacecraft's override of one profile path."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  schema "spacecraft_config_overrides" do
    field(:mission_id, :string, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:path, :string, primary_key: true)
    field(:organization_id, :string)
    field(:value, :map)
    field(:reason, :string)
    field(:set_by, :map)
    field(:set_in_revision, :integer)
    field(:set_at, :utc_datetime_usec)
  end
end
