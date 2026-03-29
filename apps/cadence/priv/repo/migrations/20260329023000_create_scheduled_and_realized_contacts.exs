defmodule Cadence.Repo.Migrations.CreateScheduledAndRealizedContacts do
  use Ecto.Migration

  def change do
    create table(:scheduled_contacts, primary_key: false) do
      add :scheduled_contact_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :source_endpoint_refs, {:array, :string}, null: false, default: []
      add :path_documents, :map, null: false, default: %{}
      add :starts_at, :utc_datetime_usec, null: false
      add :ends_at, :utc_datetime_usec
      add :provider_contact_ref, :string
      add :lifecycle_state, :string, null: false
      add :realized_contact_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:scheduled_contacts, [:mission_id, :scheduled_contact_id],
             name: :scheduled_contacts_scope_idx
           )

    create index(:scheduled_contacts, [:mission_id, :starts_at])
    create index(:scheduled_contacts, [:mission_id, :lifecycle_state])

    create table(:realized_contacts, primary_key: false) do
      add :realized_contact_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :scheduled_contact_id, :string
      add :source_endpoint_refs, {:array, :string}, null: false, default: []
      add :path_documents, :map, null: false, default: %{}
      add :clock_mode, :string, null: false
      add :initial_time, :utc_datetime_usec
      add :lifecycle_state, :string, null: false
      add :realized_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:realized_contacts, [:mission_id, :realized_contact_id],
             name: :realized_contacts_scope_idx
           )

    create index(:realized_contacts, [:mission_id, :scheduled_contact_id])
    create index(:realized_contacts, [:mission_id, :lifecycle_state])
  end
end
