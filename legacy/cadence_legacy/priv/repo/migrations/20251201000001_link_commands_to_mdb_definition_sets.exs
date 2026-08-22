defmodule Cadence.Repo.Migrations.LinkCommandsToMdbDefinitionSets do
  @moduledoc """
  Updates command_definitions to reference mdb_definition_sets instead of the
  old definition_sets table.

  This aligns commands with the new MissionDatabase catalog model.

  Note: Any existing command_definitions with definition_set_id values pointing
  to the old definition_sets table will have their definition_set_id cleared,
  as there's no automatic mapping between the old and new tables.
  """
  use Ecto.Migration

  def up do
    # Drop the old foreign key constraint
    execute "ALTER TABLE command_definitions DROP CONSTRAINT IF EXISTS command_definitions_definition_set_id_fkey"

    # Clear any existing definition_set_id values that reference the old table
    # These will need to be re-associated with mdb_definition_sets manually
    execute "UPDATE command_definitions SET definition_set_id = NULL WHERE definition_set_id IS NOT NULL"

    # Add the new foreign key constraint to mdb_definition_sets
    execute """
    ALTER TABLE command_definitions
    ADD CONSTRAINT command_definitions_definition_set_id_fkey
    FOREIGN KEY (definition_set_id)
    REFERENCES mdb_definition_sets(id)
    ON DELETE SET NULL
    """
  end

  def down do
    # Drop the new foreign key constraint
    execute "ALTER TABLE command_definitions DROP CONSTRAINT IF EXISTS command_definitions_definition_set_id_fkey"

    # Clear definition_set_id values (can't restore old references)
    execute "UPDATE command_definitions SET definition_set_id = NULL WHERE definition_set_id IS NOT NULL"

    # Restore the old foreign key constraint to definition_sets
    execute """
    ALTER TABLE command_definitions
    ADD CONSTRAINT command_definitions_definition_set_id_fkey
    FOREIGN KEY (definition_set_id)
    REFERENCES definition_sets(id)
    ON DELETE SET NULL
    """
  end
end
