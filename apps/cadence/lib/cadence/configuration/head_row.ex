defmodule Cadence.Configuration.HeadRow do
  @moduledoc "Current mission configuration revision pointer. Row-locked by every apply."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:mission_id, :string, autogenerate: false}
  schema "mission_config_heads" do
    field(:organization_id, :string)
    field(:revision_number, :integer)
    field(:revision_id, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
