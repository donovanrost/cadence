defmodule Cadence.Repo.Migrations.CreateSemanticMonitoringObservations do
  use Ecto.Migration

  def change do
    create table(:semantic_monitoring_evaluations, primary_key: false) do
      add(:evaluation_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, references(:missions, column: :mission_id, type: :string), null: false)
      add(:spacecraft_id, :string)
      add(:parameter_id, :string, null: false)
      add(:policy_id, :string, null: false)
      add(:update_id, :string, null: false)
      add(:mission_model_revision_id, :string, null: false)
      add(:runtime_plan_id, :string, null: false)
      add(:evaluated_state, :string, null: false)
      add(:effective_state, :string, null: false)
      add(:previous_state, :string)
      add(:transitioned, :boolean, null: false, default: false)
      add(:matched_context, :string)
      add(:violation_count, :integer, null: false, default: 0)
      add(:conformance_count, :integer, null: false, default: 0)
      add(:generation_time, :utc_datetime_usec)
      add(:receipt_time, :utc_datetime_usec, null: false)
      add(:evaluation_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:semantic_monitoring_evaluations, [:policy_id, :update_id]))

    create(
      index(:semantic_monitoring_evaluations, [:organization_id, :mission_id, :receipt_time])
    )

    create(index(:semantic_monitoring_evaluations, [:mission_id, :parameter_id, :receipt_time]))

    create table(:semantic_alarm_transitions, primary_key: false) do
      add(:transition_id, :string, primary_key: true)

      add(
        :evaluation_id,
        references(:semantic_monitoring_evaluations,
          column: :evaluation_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:parameter_id, :string, null: false)
      add(:policy_id, :string, null: false)
      add(:from_state, :string, null: false)
      add(:to_state, :string, null: false)
      add(:receipt_time, :utc_datetime_usec, null: false)
      add(:transition_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:semantic_alarm_transitions, [:organization_id, :mission_id, :receipt_time]))
    create(index(:semantic_alarm_transitions, [:mission_id, :parameter_id, :receipt_time]))

    create table(:semantic_latest_alarm_states) do
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:spacecraft_scope_id, :string, null: false, default: "")
      add(:spacecraft_id, :string)
      add(:parameter_id, :string, null: false)
      add(:policy_id, :string, null: false)
      add(:evaluation_id, :string, null: false)
      add(:transition_id, :string)
      add(:effective_state, :string, null: false)
      add(:receipt_time, :utc_datetime_usec, null: false)
      add(:state_document, :map, null: false, default: %{"value" => %{}})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :semantic_latest_alarm_states,
        [:mission_id, :spacecraft_scope_id, :parameter_id, :policy_id],
        name: :semantic_latest_alarm_states_scope_idx
      )
    )

    create table(:semantic_alarm_acknowledgements, primary_key: false) do
      add(:acknowledgement_id, :string, primary_key: true)

      add(
        :transition_id,
        references(:semantic_alarm_transitions,
          column: :transition_id,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:actor, :map, null: false, default: %{"value" => %{}})
      add(:note, :text)
      add(:acknowledged_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:semantic_alarm_acknowledgements, [:transition_id, :acknowledged_at]))
  end
end
