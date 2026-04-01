defmodule Cadence.Repo.Migrations.CleanupLegacyCommandTables do
  use Ecto.Migration

  @moduledoc """
  Cleanup legacy command system tables.

  This migration removes the old CommandDefinition/CommandParameter tables
  and updates CommandLog to reference MetaCommand instead.

  Commands are now stored in mdb_meta_commands (MetaCommand) with arguments
  in mdb_arguments (Argument), both part of the MissionDatabase system.
  """

  def up do
    # 1. Update command_logs table (if it exists - table was removed in recordings migration)
    execute """
    DO $$
    BEGIN
      -- Only process if command_logs table exists
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'command_logs'
      ) THEN
        -- Drop old FK to command_definitions if it exists
        IF EXISTS (
          SELECT 1 FROM information_schema.table_constraints
          WHERE constraint_name = 'command_logs_command_definition_id_fkey'
          AND table_name = 'command_logs'
        ) THEN
          ALTER TABLE command_logs DROP CONSTRAINT command_logs_command_definition_id_fkey;
        END IF;

        -- Drop the old column if it exists
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'command_logs' AND column_name = 'command_definition_id'
        ) THEN
          ALTER TABLE command_logs DROP COLUMN command_definition_id;
        END IF;

        -- Add new FK to meta_commands if not exists
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'command_logs' AND column_name = 'meta_command_id'
        ) THEN
          ALTER TABLE command_logs ADD COLUMN meta_command_id uuid REFERENCES mdb_meta_commands(id) ON DELETE SET NULL;
        END IF;
      END IF;
    END $$;
    """

    # Create index only if table exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'command_logs'
      ) THEN
        IF NOT EXISTS (
          SELECT 1 FROM pg_indexes
          WHERE tablename = 'command_logs' AND indexname = 'command_logs_meta_command_id_index'
        ) THEN
          CREATE INDEX command_logs_meta_command_id_index ON command_logs(meta_command_id);
        END IF;
      END IF;
    END $$;
    """

    # 2. Update command_queue_entries table
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'command_queue_entries_command_definition_id_fkey'
        AND table_name = 'command_queue_entries'
      ) THEN
        ALTER TABLE command_queue_entries DROP CONSTRAINT command_queue_entries_command_definition_id_fkey;
      END IF;
    END $$;
    """

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'command_queue_entries' AND column_name = 'command_definition_id'
      ) THEN
        ALTER TABLE command_queue_entries DROP COLUMN command_definition_id;
      END IF;
    END $$;
    """

    # 3. Drop legacy tables (if they exist)
    drop_if_exists table(:command_parameters)
    drop_if_exists table(:command_definitions)

    # 4. Handle packet_definitions FK to definition_sets
    # First drop old FK if it exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'packet_definitions_definition_set_id_fkey'
        AND table_name = 'packet_definitions'
      ) THEN
        ALTER TABLE packet_definitions DROP CONSTRAINT packet_definitions_definition_set_id_fkey;
      END IF;
    END $$;
    """

    # Add new FK to mdb_definition_sets if the column exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'packet_definitions' AND column_name = 'definition_set_id'
      ) THEN
        -- Only add FK if mdb_definition_sets table exists
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mdb_definition_sets') THEN
          ALTER TABLE packet_definitions
          ADD CONSTRAINT packet_definitions_definition_set_id_fkey
          FOREIGN KEY (definition_set_id) REFERENCES mdb_definition_sets(id) ON DELETE SET NULL;
        END IF;
      END IF;
    END $$;
    """

    # 5. Drop old definition_sets table
    drop_if_exists table(:definition_sets)
  end

  def down do
    # This is a destructive migration - data cannot be recovered
    # The down migration recreates empty tables for schema compatibility

    # Recreate definition_sets table
    create_if_not_exists table(:definition_sets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :version, :string, null: false
      add :description, :text
      add :is_active, :boolean, default: false
      add :published_at, :utc_datetime
      timestamps()
    end

    # Recreate command_definitions table
    create_if_not_exists table(:command_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :nilify_all)

      add :definition_set_id,
          references(:mdb_definition_sets, type: :binary_id, on_delete: :cascade)

      add :name, :string, null: false
      add :description, :text
      add :opcode, :integer
      add :is_hazardous, :boolean, default: false
      add :requires_confirmation, :boolean, default: false
      add :hazard_description, :text
      add :allowed_phases, {:array, :string}, default: []
      add :has_verification, :boolean, default: false
      add :verification_item, :string
      add :verification_timeout_ms, :integer
      timestamps()
    end

    # Recreate command_parameters table
    create_if_not_exists table(:command_parameters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :command_definition_id,
          references(:command_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text
      add :data_type, :string, null: false
      add :bit_offset, :integer, null: false
      add :bit_length, :integer, null: false
      add :endianness, :string, default: "big"
      add :default_value, :string
      add :min_value, :decimal
      add :max_value, :decimal
      add :valid_values, {:array, :string}, default: []
      add :units, :string
      add :required, :boolean, default: true
      add :sequence, :integer
      timestamps()
    end

    # Note: We don't recreate the command_definition_id columns on command_logs
    # or command_queue_entries since the data would be lost anyway
  end
end
