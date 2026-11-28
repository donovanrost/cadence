defmodule Cadence.Repo.Migrations.DropCommandStages do
  use Ecto.Migration

  # #708: a command is requested only as a command group's member, so the stage workbench is gone
  # (its REST endpoints, domain and submit). No data moves: a stage held drafts that never became
  # requests, and an existing database is dropped and reseeded.
  def up do
    drop(table(:staged_command_items))
    drop(table(:command_stages))
  end

  def down do
    raise Ecto.MigrationError, "the stage workbench is deleted (#708); it cannot be restored"
  end
end
