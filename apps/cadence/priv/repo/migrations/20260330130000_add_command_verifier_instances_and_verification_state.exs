defmodule Cadence.Repo.Migrations.AddCommandVerifierInstancesAndVerificationState do
  use Ecto.Migration

  def change do
    alter table(:command_requests) do
      add :verification_state, :string
    end

    alter table(:command_release_attempts) do
      add :verification_state, :string
    end

    create table(:command_verifier_instances, primary_key: false) do
      add :command_verifier_instance_id, :string, primary_key: true
      add :organization_id, :string
      add :mission_id, :string, null: false
      add :command_request_id, :string, null: false
      add :command_release_attempt_id, :string, null: false
      add :source_endpoint_ref, :string, null: false
      add :command_snapshot_id, :string, null: false
      add :command_id, :string, null: false
      add :command_name, :string
      add :verifier_id, :string, null: false
      add :verifier_name, :string, null: false
      add :phase, :string, null: false
      add :severity, :string
      add :success_criteria_document, :map, null: false, default: %{}
      add :failure_criteria_document, :map, null: false, default: %{}
      add :delay_until, :utc_datetime_usec
      add :timeout_at, :utc_datetime_usec
      add :lifecycle_state, :string, null: false
      add :matched_sample_id, :string
      add :matched_at, :utc_datetime_usec
      add :failure_reason, :text
      add :metadata_document, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_verifier_instances, [:mission_id, :command_verifier_instance_id],
             name: :command_verifier_instances_scope_idx
           )

    create index(
             :command_verifier_instances,
             [:organization_id, :mission_id, :command_request_id],
             name: :command_verifier_instances_request_org_scope_idx
           )

    create index(
             :command_verifier_instances,
             [:organization_id, :mission_id, :command_release_attempt_id],
             name: :command_verifier_instances_release_org_scope_idx
           )

    create index(
             :command_verifier_instances,
             [:organization_id, :mission_id, :source_endpoint_ref, :lifecycle_state],
             name: :command_verifier_instances_lane_state_org_scope_idx
           )

    create index(
             :command_verifier_instances,
             [:organization_id, :mission_id, :lifecycle_state, :timeout_at],
             name: :command_verifier_instances_timeout_org_scope_idx
           )
  end
end
