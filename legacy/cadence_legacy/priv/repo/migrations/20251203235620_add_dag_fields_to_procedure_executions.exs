defmodule Cadence.Repo.Migrations.AddDagFieldsToProcedureExecutions do
  use Ecto.Migration

  def change do
    alter table(:procedure_executions) do
      # Trigger context for event-driven executions
      add :trigger_context, :map

      # DAG execution tracking
      add :completed_steps, {:array, :string}, default: []
      add :skipped_steps, {:array, :string}, default: []
      add :failed_steps, {:array, :string}, default: []
      add :blocked_steps, {:array, :string}, default: []
      add :step_results, :map, default: %{}
    end
  end
end
