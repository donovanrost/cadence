defmodule Cadence.Repo.Migrations.IndexDurableCommandQueueLaneSequence do
  use Ecto.Migration

  def change do
    create(
      index(
        :command_queue_entries,
        [:organization_id, :mission_id, :queue_lane_key, :queue_sequence],
        name: :command_queue_entries_lane_sequence_idx
      )
    )
  end
end
