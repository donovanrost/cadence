defmodule Cadence.Repo.Migrations.CreateMdbStreams do
  use Ecto.Migration

  def change do
    create table(:mdb_streams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :definition_set_id, references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text

      # Stream type: telemetry, command, bidirectional
      add :stream_type, :string, null: false

      # Framing protocol
      add :framing_protocol, :string, null: false

      # Framing configuration
      add :sync_pattern, :binary
      add :frame_length, :integer
      add :length_field_offset, :integer
      add :length_field_size, :integer
      add :delimiter, :binary

      # Custom framing
      add :custom_framer_module, :string
      add :custom_framer_config, :map, default: %{}

      # Error detection
      add :error_detection, :string
      add :error_detection_offset, :integer
      add :error_detection_polynomial, :integer

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_streams, [:organization_id])
    create index(:mdb_streams, [:mission_id])
    create index(:mdb_streams, [:definition_set_id])
    create unique_index(:mdb_streams, [:definition_set_id, :name], name: :mdb_streams_definition_set_name_index)
  end
end
