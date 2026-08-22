defmodule Cadence.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Scoping - who receives this notification
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      # Notification type and content
      add :type, :string, null: false
      add :title, :string, null: false
      add :body, :text
      add :severity, :string, default: "info"

      # Related resource for navigation
      add :resource_type, :string
      add :resource_id, :binary_id
      add :action_url, :string

      # Metadata for rendering
      add :metadata, :map, default: %{}

      # Actor who triggered the notification
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # State tracking
      add :read_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      add :email_sent_at, :utc_datetime_usec

      # Link to originating outbox event for traceability
      add :outbox_event_id, references(:outbox_events, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # User's unread notifications (for bell icon count)
    create index(:notifications, [:user_id, :inserted_at],
             where: "read_at IS NULL AND archived_at IS NULL",
             name: :notifications_user_unread_idx
           )

    # User's notification inbox (paginated list)
    create index(:notifications, [:user_id, :inserted_at],
             where: "archived_at IS NULL",
             name: :notifications_user_inbox_idx
           )

    # Mission-scoped notifications
    create index(:notifications, [:mission_id, :inserted_at], where: "archived_at IS NULL")

    # Lookup by resource for deduplication
    create index(:notifications, [:user_id, :resource_type, :resource_id, :type])

    # Email batch processing
    create index(:notifications, [:user_id, :inserted_at],
             where: "email_sent_at IS NULL AND archived_at IS NULL",
             name: :notifications_pending_email_idx
           )
  end
end
