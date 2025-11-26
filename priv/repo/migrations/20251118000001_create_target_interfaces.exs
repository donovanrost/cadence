defmodule Cadence.Repo.Migrations.CreateTargetInterfaces do
  use Ecto.Migration

  def change do
    create table(:target_interfaces, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :target_id, references(:targets, type: :uuid, on_delete: :delete_all), null: false
      add :interface_id, references(:interfaces, type: :uuid, on_delete: :delete_all), null: false

      add :direction, :text, null: false

      timestamps()
    end

    # Ensure direction is valid
    create constraint(:target_interfaces, :direction_must_be_valid,
             check: "direction IN ('read', 'write', 'read_write')"
           )

    # Index for looking up interfaces by target
    create index(:target_interfaces, [:target_id])

    # Index for looking up targets by interface
    create index(:target_interfaces, [:interface_id])

    # Prevent duplicate target-interface mappings
    create unique_index(:target_interfaces, [:target_id, :interface_id])
  end
end
