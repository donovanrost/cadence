defmodule Cadence.Repo.Migrations.ConvertQueueEntryStatusToEnum do
  @moduledoc """
  Converts command_queue_entries.status from string to PostgreSQL enum.

  The enum values are ordered for efficient sorting:
  executing (0) -> pending (1) -> failed (2) -> completed (3) -> cancelled (4) -> expired (5)

  This allows simple ORDER BY status instead of CASE fragments.
  """
  use Ecto.Migration

  def up do
    # 1. Create the PostgreSQL enum type with values in sort order
    execute """
    CREATE TYPE queue_entry_status AS ENUM (
      'executing',
      'pending',
      'failed',
      'completed',
      'cancelled',
      'expired'
    )
    """

    # 2. Drop indexes that include the status column
    drop_if_exists index(:command_queue_entries, [:mission_id, :status, :priority, :sequence_number])
    drop_if_exists index(:command_queue_entries, [:target_id, :status])
    drop_if_exists index(:command_queue_entries, [:mission_id, :status, :scheduled_at])
    drop_if_exists index(:command_queue_entries, [:status, :expires_at])
    drop_if_exists index(:command_queue_entries, [:user_id, :status])

    # 3. Drop the default before converting
    execute "ALTER TABLE command_queue_entries ALTER COLUMN status DROP DEFAULT"

    # 4. Convert the column from string to enum
    execute """
    ALTER TABLE command_queue_entries
    ALTER COLUMN status TYPE queue_entry_status
    USING status::queue_entry_status
    """

    # 5. Set new default using enum type
    execute "ALTER TABLE command_queue_entries ALTER COLUMN status SET DEFAULT 'pending'::queue_entry_status"

    # 6. Recreate indexes with the enum column
    create index(:command_queue_entries, [:mission_id, :status, :priority, :sequence_number])
    create index(:command_queue_entries, [:target_id, :status])

    create index(:command_queue_entries, [:mission_id, :status, :scheduled_at],
             where: "scheduled_at IS NOT NULL"
           )

    create index(:command_queue_entries, [:status, :expires_at], where: "expires_at IS NOT NULL")
    create index(:command_queue_entries, [:user_id, :status])
  end

  def down do
    # 1. Drop indexes
    drop_if_exists index(:command_queue_entries, [:mission_id, :status, :priority, :sequence_number])
    drop_if_exists index(:command_queue_entries, [:target_id, :status])
    drop_if_exists index(:command_queue_entries, [:mission_id, :status, :scheduled_at])
    drop_if_exists index(:command_queue_entries, [:status, :expires_at])
    drop_if_exists index(:command_queue_entries, [:user_id, :status])

    # 2. Convert back to string
    execute """
    ALTER TABLE command_queue_entries
    ALTER COLUMN status TYPE varchar(255)
    USING status::text
    """

    # 3. Set default back to string
    execute """
    ALTER TABLE command_queue_entries
    ALTER COLUMN status SET DEFAULT 'pending'
    """

    # 4. Drop the enum type
    execute "DROP TYPE queue_entry_status"

    # 5. Recreate original indexes
    create index(:command_queue_entries, [:mission_id, :status, :priority, :sequence_number])
    create index(:command_queue_entries, [:target_id, :status])

    create index(:command_queue_entries, [:mission_id, :status, :scheduled_at],
             where: "scheduled_at IS NOT NULL"
           )

    create index(:command_queue_entries, [:status, :expires_at], where: "expires_at IS NOT NULL")
    create index(:command_queue_entries, [:user_id, :status])
  end
end
