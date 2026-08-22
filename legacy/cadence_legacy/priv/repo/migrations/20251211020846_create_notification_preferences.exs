defmodule Cadence.Repo.Migrations.CreateNotificationPreferences do
  use Ecto.Migration

  def change do
    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Scoping - user and optionally mission
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all)

      # Notification type this preference applies to
      add :notification_type, :string, null: false

      # Channel preferences
      add :in_app_enabled, :boolean, default: true, null: false
      add :email_enabled, :boolean, default: true, null: false
      add :email_frequency, :string, default: "immediate"

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint: one preference per user/type/mission combo
    # Using coalesce to handle NULL mission_id for global preferences
    execute(
      """
      CREATE UNIQUE INDEX notification_preferences_user_type_mission_idx
      ON notification_preferences (user_id, notification_type, COALESCE(mission_id, '00000000-0000-0000-0000-000000000000'::uuid))
      """,
      "DROP INDEX notification_preferences_user_type_mission_idx"
    )

    # User's global preferences (mission_id is null)
    create index(:notification_preferences, [:user_id],
             where: "mission_id IS NULL",
             name: :notification_preferences_user_global_idx
           )
  end
end
