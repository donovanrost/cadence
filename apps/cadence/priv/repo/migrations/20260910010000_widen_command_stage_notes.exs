defmodule Cadence.Repo.Migrations.WidenCommandStageNotes do
  use Ecto.Migration

  def up do
    alter table(:command_stages) do
      modify(:description, :text)
    end

    alter table(:staged_command_items) do
      modify(:notes, :text)
    end
  end

  def down do
    # PostgreSQL rejects oversized existing values rather than truncating notes.
    alter table(:command_stages) do
      modify(:description, :string)
    end

    alter table(:staged_command_items) do
      modify(:notes, :string)
    end
  end
end
