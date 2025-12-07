defmodule Cadence.Repo.Migrations.AddIdempotencyKeyToAutomationExecutions do
  use Ecto.Migration

  def change do
    alter table(:automation_executions) do
      add :idempotency_key, :string
    end

    # Create a unique index for idempotency enforcement
    # This prevents duplicate executions for the same event
    create unique_index(:automation_executions, [:idempotency_key],
             name: :automation_executions_idempotency_key_index,
             where: "idempotency_key IS NOT NULL"
           )
  end
end
