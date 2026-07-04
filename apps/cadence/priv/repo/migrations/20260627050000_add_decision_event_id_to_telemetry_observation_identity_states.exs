defmodule Cadence.Repo.Migrations.AddDecisionEventIdToTelemetryObservationIdentityStates do
  use Ecto.Migration

  def change do
    alter table(:telemetry_observation_identity_states) do
      add(:decision_event_id, :string)
    end
  end
end
