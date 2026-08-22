defmodule Cadence.Repo.Migrations.AddExecutionVersionToProcedureExecutions do
  use Ecto.Migration

  def change do
    alter table(:procedure_executions) do
      add :execution_version, :string, default: "v1"
    end

    # Index for efficient filtering in cleanup worker
    create index(:procedure_executions, [:execution_version])
  end
end
