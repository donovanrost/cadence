defmodule Cadence.Repo.Migrations.CreateMdbContainers do
  use Ecto.Migration

  def change do
    create table(:mdb_containers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :definition_set_id, references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text
      add :short_description, :string

      # Inheritance
      add :base_container_ref, :string
      add :abstract, :boolean, default: false

      # Identification criteria (MatchCriteria embedded JSON)
      add :restriction_criteria, :map

      # Common identification fields (shortcuts for CCSDS)
      add :apid, :integer
      add :packet_type, :integer

      # Packet structure
      add :byte_order, :string, default: "big_endian"

      # Sync pattern
      add :sync_pattern, :binary
      add :sync_pattern_offset_bits, :integer

      # Size information
      add :size_in_bits, :integer
      add :max_size_in_bits, :integer

      # Rate information
      add :expected_rate_hz, :float
      add :rate_tolerance_percent, :float

      # Processing hints
      add :allow_short, :boolean, default: false
      add :hidden, :boolean, default: false

      # Stream association
      add :stream_id, references(:mdb_streams, type: :binary_id, on_delete: :nilify_all)

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_containers, [:organization_id])
    create index(:mdb_containers, [:mission_id])
    create index(:mdb_containers, [:definition_set_id])
    create index(:mdb_containers, [:stream_id])
    create index(:mdb_containers, [:apid])
    create unique_index(:mdb_containers, [:definition_set_id, :name], name: :mdb_containers_definition_set_name_index)
  end
end
