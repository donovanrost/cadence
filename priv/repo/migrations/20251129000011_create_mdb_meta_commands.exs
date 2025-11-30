defmodule Cadence.Repo.Migrations.CreateMdbMetaCommands do
  use Ecto.Migration

  def change do
    create table(:mdb_meta_commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :definition_set_id, references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text
      add :short_description, :string

      # Inheritance
      add :base_command_ref, :string
      add :abstract, :boolean, default: false

      # Identification
      add :opcode, :integer

      # Safety classification (XTCE Significance)
      add :significance, :string, default: "none"
      add :significance_reason, :text

      # OpenC3-style hazard flags
      add :is_hazardous, :boolean, default: false
      add :hazard_description, :text
      add :requires_confirmation, :boolean, default: false
      add :is_restricted, :boolean, default: false

      # Operational constraints
      add :allowed_phases, {:array, :string}, default: []
      add :disabled, :boolean, default: false
      add :disabled_reason, :text

      # Encoding configuration
      add :encoding_format, :string
      add :encoding_config, :map, default: %{}

      # Interlock (embedded JSON)
      add :interlock, :map

      # Related items
      add :related_telemetry_items, {:array, :string}, default: []
      add :related_screen, :string
      add :expected_response_container, :string

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_meta_commands, [:organization_id])
    create index(:mdb_meta_commands, [:mission_id])
    create index(:mdb_meta_commands, [:definition_set_id])
    create index(:mdb_meta_commands, [:opcode])
    create unique_index(:mdb_meta_commands, [:definition_set_id, :name], name: :mdb_meta_commands_definition_set_name_index)
  end
end
