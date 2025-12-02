defmodule Cadence.Repo.Migrations.CreateOutboxEvents do
  use Ecto.Migration

  def change do
    create table(:outbox_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Hierarchical scoping - org_id always present for tenant isolation
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      # Event identification
      add :event_type, :string, null: false
      add :aggregate_type, :string, null: false
      add :aggregate_id, :binary_id, null: false

      # Actor tracking for audit trail
      add :actor_id, :binary_id
      add :actor_type, :string  # "user", "system", "api_key"

      # Event payload
      add :payload, :map, default: %{}

      # Processing state
      add :processed_at, :utc_datetime_usec

      # Failure tracking
      add :attempts, :integer, default: 0, null: false
      add :last_error, :text
      add :last_attempted_at, :utc_datetime_usec
      add :dead_lettered_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Primary index for polling unprocessed events (mission-scoped)
    create index(:outbox_events, [:mission_id, :inserted_at],
             where: "processed_at IS NULL AND dead_lettered_at IS NULL",
             name: :outbox_events_mission_pending_idx)

    # Index for polling unprocessed organization-level events
    create index(:outbox_events, [:organization_id, :inserted_at],
             where: "mission_id IS NULL AND processed_at IS NULL AND dead_lettered_at IS NULL",
             name: :outbox_events_org_pending_idx)

    # General unprocessed events index (for global processor)
    create index(:outbox_events, [:inserted_at],
             where: "processed_at IS NULL AND dead_lettered_at IS NULL",
             name: :outbox_events_pending_idx)

    # Dead letter review
    create index(:outbox_events, [:dead_lettered_at],
             where: "dead_lettered_at IS NOT NULL",
             name: :outbox_events_dead_letter_idx)

    # Lookup by aggregate (for idempotency checks, event sourcing queries)
    create index(:outbox_events, [:aggregate_type, :aggregate_id, :inserted_at])

    # Organization-wide event history (for audit log queries)
    create index(:outbox_events, [:organization_id, :inserted_at])
  end
end
