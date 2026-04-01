defmodule Cadence.Repo.Migrations.CreateProcedureLogs do
  use Ecto.Migration

  def change do
    create table(:procedure_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timestamp, :utc_datetime_usec, null: false
      add :level, :string, null: false, default: "info"
      add :message, :text, null: false
      add :step_index, :integer
      add :metadata, :map, default: %{}

      add :execution_id,
          references(:procedure_executions, type: :binary_id, on_delete: :delete_all),
          null: false
    end

    create index(:procedure_logs, [:execution_id])
    create index(:procedure_logs, [:execution_id, :timestamp])
    create index(:procedure_logs, [:level])
  end
end
