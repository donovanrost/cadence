defmodule Cadence.Repo.Migrations.CreatePacketDefinitions do
  use Ecto.Migration

  def change do
    create table(:packet_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy scoping
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Packet identification
      add :name, :string, null: false
      add :description, :text

      # CCSDS/Packet fields for identification
      add :apid, :integer
      add :packet_id, :integer
      add :packet_type, :string

      # Protocol and framing information
      add :is_big_endian, :boolean, default: true
      add :has_sync_pattern, :boolean, default: false
      add :sync_pattern, :binary
      add :fixed_length, :integer

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:packet_definitions, [:organization_id])
    create index(:packet_definitions, [:mission_id])
    create index(:packet_definitions, [:apid])
    # Note: unique constraint on (definition_set_id, name) is created in create_definition_sets migration
  end
end
