defmodule Cadence.Repo.Migrations.CreateTargetInterfaces do
  use Ecto.Migration

  def change do
    create table(:target_interfaces, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :target_id, references(:targets, type: :uuid, on_delete: :delete_all), null: false
      add :interface_id, references(:interfaces, type: :uuid, on_delete: :delete_all), null: false

      add :direction, :text, null: false
      add :scid, :integer

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

    # Prevent duplicate SCID assignments within an interface
    create unique_index(:target_interfaces, [:interface_id, :scid],
             where: "scid IS NOT NULL",
             name: :target_interfaces_interface_id_scid_index
           )

    create table(:interface_vcids, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :interface_id, references(:interfaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :target_id, references(:targets, type: :binary_id, on_delete: :delete_all)
      add :vcid, :integer, null: false
      add :lane, :string
      add :qos, :string
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:interface_vcids, [:interface_id])
    create index(:interface_vcids, [:target_id])

    create unique_index(
             :interface_vcids,
             [:interface_id, :target_id, :vcid],
             name: :interface_vcids_interface_id_target_id_vcid_index
           )

    create unique_index(
             :interface_vcids,
             [:interface_id, :vcid],
             where: "target_id IS NULL",
             name: :interface_vcids_interface_id_vcid_default_index
           )
  end
end
