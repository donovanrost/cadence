defmodule Cadence.Repo.Migrations.FixCommandDefinitionsUniqueIndex do
  @moduledoc """
  Drops the mission-level unique index on command_definitions.

  Command definitions are now versioned per DefinitionSet, so uniqueness
  should be enforced at the definition_set level, not the mission level.
  This allows the same command name to exist across multiple versions.
  """
  use Ecto.Migration

  def change do
    # Drop the old mission-level unique constraint
    drop_if_exists unique_index(:command_definitions, [:mission_id, :name])
  end
end
