defmodule Cadence.SemanticObservations.FleetAlarmSummaryRow do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "semantic_fleet_alarm_summaries" do
    field(:organization_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:spacecraft_id, :string, primary_key: true)
    field(:worst_rank, :integer)
    field(:active, :integer)
    field(:last_received_at, :utc_datetime_usec)
    field(:worst_state_id, :integer)
  end
end
