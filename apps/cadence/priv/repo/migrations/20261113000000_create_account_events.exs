defmodule Cadence.Repo.Migrations.CreateAccountEvents do
  use Ecto.Migration

  # Account changes a person makes to their own sign-in (password changed, sessions signed out),
  # for the organization audit (director, api-ops). Append-only; never holds a secret.
  def change do
    create table(:account_events, primary_key: false) do
      add(:account_event_id, :string, primary_key: true)
      add(:user_id, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:action, :string, null: false)
      add(:details, :map, null: false, default: %{})
      add(:occurred_at, :utc_datetime_usec, null: false)
    end

    create(index(:account_events, [:user_id, :occurred_at]))
  end
end
