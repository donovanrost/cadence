defmodule Cadence.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add(:notification_id, :string, primary_key: true)

      add(:user_id, references(:users, column: :user_id, type: :string, on_delete: :delete_all),
        null: false
      )

      add(:kind, :string, null: false)
      add(:title, :string, null: false)
      add(:body, :string)
      add(:action_url, :string)
      add(:metadata, :map, null: false, default: %{})
      add(:read_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:notifications, [:user_id, :inserted_at]))
    create(index(:notifications, [:user_id, :read_at]))
  end
end
