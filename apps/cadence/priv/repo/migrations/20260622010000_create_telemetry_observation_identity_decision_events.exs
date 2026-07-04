defmodule Cadence.Repo.Migrations.CreateTelemetryObservationIdentityDecisionEvents do
  use Ecto.Migration

  def change do
    create table(:telemetry_observation_identity_decision_events, primary_key: false) do
      add(:decision_event_id, :string, primary_key: true)
      add(:observation_identity_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:realm, :string, null: false)
      add(:replay_run_id, :string)
      add(:data_source_id, :string)
      add(:binding_id, :string)
      add(:observable_id, :string, null: false)
      add(:point_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:decision, :string, null: false)
      add(:decision_reason, :string, null: false)
      add(:actor_id, :string)
      add(:actor_kind, :string)
      add(:evidence_ref, :map, null: false, default: %{})
      add(:previous_state, :map, null: false)
      add(:new_state, :map, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :telemetry_observation_identity_decision_events,
        [:organization_id, :mission_id, :observation_identity_id, :occurred_at],
        name: :telemetry_identity_decision_events_identity_idx
      )
    )

    create(
      index(
        :telemetry_observation_identity_decision_events,
        [:organization_id, :mission_id, :occurred_at],
        name: :telemetry_identity_decision_events_scope_idx
      )
    )

    create(
      index(
        :telemetry_observation_identity_decision_events,
        [:organization_id, :mission_id, :replay_run_id],
        name: :telemetry_identity_decision_events_replay_idx
      )
    )
  end
end
