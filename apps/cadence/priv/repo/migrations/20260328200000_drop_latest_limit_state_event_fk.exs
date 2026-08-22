defmodule Cadence.Repo.Migrations.DropLatestLimitStateEventFk do
  use Ecto.Migration

  def change do
    drop constraint(
           :telemetry_latest_limit_states,
           :telemetry_latest_limit_states_limit_event_id_fkey
         )
  end
end
