defmodule Cadence.Repo.Migrations.CreateTelemetryObservationIdentityStates do
  use Ecto.Migration

  def change do
    create table(:telemetry_observation_identity_states, primary_key: false) do
      add(:observation_identity_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:realm, :string, null: false)
      add(:replay_run_id, :string)
      add(:data_source_id, :string)
      add(:binding_id, :string)
      add(:observable_id, :string, null: false)
      add(:point_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:canonical_observation_id, :string)
      add(:canonical_sample_id, :string)
      add(:canonical_revision, :integer)
      add(:latest_observation_id, :string, null: false)
      add(:latest_sample_id, :string, null: false)
      add(:latest_revision, :integer, null: false)
      add(:validity_state, :string, null: false)
      add(:canonical_count, :integer, null: false, default: 0)
      add(:duplicate_count, :integer, null: false, default: 0)
      add(:conflict_count, :integer, null: false, default: 0)
      add(:superseded_count, :integer, null: false, default: 0)
      add(:advisory_count, :integer, null: false, default: 0)
      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
      add(:decision_reason, :string)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :telemetry_observation_identity_states,
        [
          :mission_id,
          :realm,
          :observable_id
        ], name: :telemetry_observation_identity_states_scope_idx)
    )

    create(
      index(:telemetry_observation_identity_states, [:mission_id, :validity_state],
        name: :telemetry_observation_identity_states_validity_idx
      )
    )

    create(
      index(:telemetry_observation_identity_states, [:organization_id, :mission_id, :replay_run_id],
        name: :telemetry_observation_identity_states_replay_idx
      )
    )
  end
end
