defmodule Cadence.Repo.Migrations.CreateContactCommandActions do
  use Ecto.Migration

  def change do
    create table(:contact_command_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mission_id,
          references(:missions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :contact_id,
          references(:contacts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :gate, :string, null: false, default: "uplink_ready"
      add :order, :integer, null: false, default: 0
      add :state, :string, null: false, default: "planned"
      add :command_ref, :map, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:contact_command_actions, [:mission_id, :contact_id])
    create index(:contact_command_actions, [:contact_id, :gate, :order])
    create index(:contact_command_actions, [:mission_id, :state])
  end
end
