defmodule Cadence.Repo.Migrations.CreateContactActions do
  use Ecto.Migration

  def change do
    create table(:contact_actions, primary_key: false) do
      add :contact_action_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :scheduled_contact_id, :string
      add :realized_contact_id, :string
      add :action_kind, :string, null: false
      add :reason, :string
      add :actor_document, :map, null: false, default: %{}
      add :metadata_document, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:contact_actions, [:mission_id, :contact_action_id],
             name: :contact_actions_scope_idx
           )

    create index(:contact_actions, [:mission_id, :occurred_at])
    create index(:contact_actions, [:mission_id, :scheduled_contact_id])
    create index(:contact_actions, [:mission_id, :realized_contact_id])
    create index(:contact_actions, [:mission_id, :action_kind])
  end
end
