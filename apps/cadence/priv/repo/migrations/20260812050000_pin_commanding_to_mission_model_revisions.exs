defmodule Cadence.Repo.Migrations.PinCommandingToMissionModelRevisions do
  use Ecto.Migration

  def up do
    drop_if_exists(
      index(:staged_command_items, [:organization_id, :mission_id, :command_snapshot_id])
    )

    rename(table(:staged_command_items), :command_snapshot_id, to: :mission_model_revision_id)
    rename(table(:command_requests), :command_snapshot_id, to: :mission_model_revision_id)
    rename(table(:command_release_attempts), :command_snapshot_id, to: :mission_model_revision_id)

    rename(table(:command_verifier_instances), :command_snapshot_id,
      to: :mission_model_revision_id
    )

    rename(table(:application_packet_bindings), :telemetry_snapshot_id,
      to: :mission_model_revision_id
    )

    create(
      index(:staged_command_items, [:organization_id, :mission_id, :mission_model_revision_id])
    )

    alter table(:catalog_revisions) do
      remove(:telemetry_snapshot_id)
      remove(:command_snapshot_id)
    end

    alter table(:catalog_import_runs) do
      remove(:snapshot_id)
    end

    drop(table(:catalog_command_snapshots))
    drop(table(:catalog_telemetry_snapshots))
  end

  def down do
    raise "removing the retired catalog snapshot model is irreversible"
  end
end
