defmodule Cadence.MissionModels.AuthoredVersionRow do
  @moduledoc false
  # One version of the mission's authored monitoring layer (ADR-020 P3 M1, #451): the layer, and
  # the applied change set and ledger revision that approved it. Append-only by trigger.
  use Ecto.Schema

  @primary_key false

  schema "mission_model_authored_versions" do
    field(:organization_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:version, :integer, primary_key: true)
    field(:layer_id, :string)
    field(:change_set_id, :string)
    field(:revision_number, :integer)
    field(:decided_at, :utc_datetime_usec)
  end
end
