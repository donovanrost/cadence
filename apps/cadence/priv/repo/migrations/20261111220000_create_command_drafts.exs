defmodule Cadence.Repo.Migrations.CreateCommandDrafts do
  use Ecto.Migration

  # Compose's current draft (director, BACKLOG ac293f6c): one per user per mission, overwritten by
  # autosave, inert (never queued, released or shown to anyone else).
  def change do
    create table(:command_drafts, primary_key: false) do
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:user_id, :string, null: false)
      add(:revision, :integer, null: false)
      add(:document, :map, null: false)
      add(:catalog_revision_id, :string)
      add(:saved_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:command_drafts, [:organization_id, :mission_id, :user_id],
        name: :command_drafts_owner_index
      )
    )
  end
end
