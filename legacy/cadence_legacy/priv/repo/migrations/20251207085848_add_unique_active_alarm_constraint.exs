defmodule Cadence.Repo.Migrations.AddUniqueActiveAlarmConstraint do
  @moduledoc """
  Adds a unique partial index to prevent duplicate active alarms for the same source.

  This constraint ensures that for any given (mission_id, target_id, source_type, source_id)
  combination, there can only be one alarm in an "active" state (active, acknowledged, or shelved).

  This is critical for preventing race conditions in the alarm creation path where
  concurrent violations could create duplicate alarms.
  """
  use Ecto.Migration

  def change do
    # Create a unique partial index on active alarms
    # This prevents duplicate alarms for the same source while the alarm is still active
    create unique_index(
             :alarms,
             [:mission_id, :target_id, :source_type, :source_id],
             where: "status IN ('active', 'acknowledged', 'shelved')",
             name: :alarms_unique_active_source_idx
           )

    # Also add an index for efficient lookups of active alarms by source
    # This improves the find_active_alarm query performance
    create index(
             :alarms,
             [:mission_id, :target_id, :source_type, :source_id, :status],
             name: :alarms_source_lookup_idx
           )
  end
end
