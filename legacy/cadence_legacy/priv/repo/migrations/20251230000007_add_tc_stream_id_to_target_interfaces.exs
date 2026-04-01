defmodule Cadence.Repo.Migrations.AddTcStreamIdToTargetInterfaces do
  use Ecto.Migration

  def up do
    alter table(:target_interfaces) do
      add :tc_stream_id, :string
    end

    execute("""
    UPDATE target_interfaces
    SET tc_stream_id = target_id::text
    WHERE tc_stream_id IS NULL
    """)
  end

  def down do
    alter table(:target_interfaces) do
      remove :tc_stream_id
    end
  end
end
