defmodule Cadence.Repo.Migrations.AddDefinitionSetToCommands do
  @moduledoc """
  Links command_definitions to definition_sets.

  This aligns commands with the same versioning model as telemetry packets,
  making the DefinitionSet the atomic unit containing both telemetry and
  command definitions.
  """
  use Ecto.Migration

  def change do
    alter table(:command_definitions) do
      add :definition_set_id,
          references(:definition_sets, type: :binary_id, on_delete: :delete_all)
    end

    create index(:command_definitions, [:definition_set_id])

    # Unique constraint: command name must be unique within a definition set
    create unique_index(:command_definitions, [:definition_set_id, :name],
             where: "definition_set_id IS NOT NULL",
             name: :command_definitions_definition_set_name_index
           )
  end
end
