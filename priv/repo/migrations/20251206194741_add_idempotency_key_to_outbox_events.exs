defmodule Cadence.Repo.Migrations.AddIdempotencyKeyToOutboxEvents do
  use Ecto.Migration

  def change do
    alter table(:outbox_events) do
      add :idempotency_key, :string
    end

    # Partial unique index - only applies when idempotency_key is not null
    # This allows multiple events without keys but ensures uniqueness when specified
    create unique_index(:outbox_events, [:idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :outbox_events_idempotency_key_unique_index
           )
  end
end
