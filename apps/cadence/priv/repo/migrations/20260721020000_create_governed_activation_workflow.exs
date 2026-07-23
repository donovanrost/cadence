defmodule Cadence.Repo.Migrations.CreateGovernedActivationWorkflow do
  use Ecto.Migration

  def up do
    create table(:activation_requests, primary_key: false) do
      add(:activation_request_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:binding_set_id, :string, null: false)
      add(:binding_set_version, :integer, null: false)
      add(:binding_set_content_sha256, :string, null: false)
      add(:change_class, :string, null: false)
      add(:state, :string, null: false)
      add(:requester_actor_kind, :string, null: false)
      add(:requester_actor_id, :string, null: false)
      add(:requester_actor_document, :map, null: false, default: %{})
      add(:policy_document, :map, null: false, default: %{})
      add(:requested_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:activation_requests, [:organization_id, :mission_id, :requested_at],
        name: :activation_requests_scope_idx
      )
    )

    create(
      constraint(:activation_requests, :activation_requests_state_check,
        check: "state IN ('approval_pending', 'approved', 'rejected')"
      )
    )

    create table(:activation_decisions, primary_key: false) do
      add(:activation_decision_id, :string, primary_key: true)

      add(
        :activation_request_id,
        references(:activation_requests,
          column: :activation_request_id,
          type: :string,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:decision, :string, null: false)
      add(:actor_kind, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:actor_document, :map, null: false, default: %{})
      add(:reason, :text, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:activation_decisions, [:activation_request_id, :decided_at],
        name: :activation_decisions_request_idx
      )
    )

    create(
      constraint(:activation_decisions, :activation_decisions_decision_check,
        check: "decision IN ('approved', 'rejected')"
      )
    )

    create table(:activation_executions, primary_key: false) do
      add(:activation_execution_id, :string, primary_key: true)

      add(
        :activation_request_id,
        references(:activation_requests,
          column: :activation_request_id,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:status, :string, null: false)
      add(:executor_actor_document, :map, null: false, default: %{})
      add(:activation_id, :string)
      add(:generation, :bigint)
      add(:binding_set_content_sha256, :string, null: false)
      add(:error_document, :map, null: false, default: %{})
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:activation_executions, [:activation_request_id],
        name: :activation_executions_request_idx
      )
    )

    create(
      constraint(:activation_executions, :activation_executions_status_check,
        check: "status IN ('in_progress', 'succeeded', 'failed')"
      )
    )

    alter table(:mission_binding_set_activations) do
      add(
        :activation_request_id,
        references(:activation_requests,
          column: :activation_request_id,
          type: :string,
          on_delete: :restrict
        )
      )
    end

    alter table(:mission_active_binding_sets) do
      add(
        :activation_request_id,
        references(:activation_requests,
          column: :activation_request_id,
          type: :string,
          on_delete: :restrict
        )
      )
    end

    create(
      unique_index(:mission_binding_set_activations, [:activation_request_id],
        where: "activation_request_id IS NOT NULL",
        name: :mission_binding_set_activations_request_idx
      )
    )

    execute("""
    ALTER TABLE activation_requests
    ADD CONSTRAINT activation_requests_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    alter table(:mission_active_binding_sets) do
      remove(:activation_request_id)
    end

    drop_if_exists(
      index(:mission_binding_set_activations, [:activation_request_id],
        name: :mission_binding_set_activations_request_idx
      )
    )

    alter table(:mission_binding_set_activations) do
      remove(:activation_request_id)
    end

    execute("""
    ALTER TABLE activation_requests
    DROP CONSTRAINT IF EXISTS activation_requests_org_mission_fk
    """)

    drop(table(:activation_executions))
    drop(table(:activation_decisions))
    drop(table(:activation_requests))
  end
end
