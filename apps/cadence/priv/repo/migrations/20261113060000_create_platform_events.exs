defmodule Cadence.Repo.Migrations.CreatePlatformEvents do
  use Ecto.Migration

  # What platform administrators do (console L7, lead): organizations created, cross-org
  # invitations, service identities issued/rotated/revoked, admin mode entered/left.
  # Append-only; never holds a secret.
  def change do
    create table(:platform_events, primary_key: false) do
      add(:platform_event_id, :string, primary_key: true)
      add(:actor_id, :string, null: false)
      add(:action, :string, null: false)
      add(:organization_id, :string)
      add(:target_kind, :string)
      add(:target_id, :string)
      add(:target_label, :string)
      add(:details, :map, null: false, default: %{})
      add(:occurred_at, :utc_datetime_usec, null: false)
    end

    create(index(:platform_events, [:occurred_at]))
    create(index(:platform_events, [:organization_id, :occurred_at]))
  end
end
