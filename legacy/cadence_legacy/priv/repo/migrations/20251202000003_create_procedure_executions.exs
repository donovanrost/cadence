defmodule Cadence.Repo.Migrations.CreateProcedureExecutions do
  use Ecto.Migration

  def change do
    create table(:procedure_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :parameters, :map, default: %{}

      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      add :current_step_index, :integer, default: 0
      add :checkpoint_state, :binary

      add :error_message, :text
      add :error_step_index, :integer

      add :triggered_by, :string, null: false, default: "manual"
      add :trigger_event_id, :binary_id

      add :procedure_id, references(:procedures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_id, references(:targets, type: :binary_id, on_delete: :nilify_all)

      add :triggered_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_executions, [:procedure_id])
    create index(:procedure_executions, [:procedure_version_id])
    create index(:procedure_executions, [:organization_id])
    create index(:procedure_executions, [:mission_id])
    create index(:procedure_executions, [:target_id])
    create index(:procedure_executions, [:status])
    create index(:procedure_executions, [:triggered_by])
    create index(:procedure_executions, [:started_at])
  end
end
