defmodule Cadence.Repo.Migrations.AddTargetQueueProcessingIndex do
  use Ecto.Migration

  @doc """
  Adds an optimized index for target-scoped command queue processing.

  The new target-scoped command system (TargetQueue + TargetDispatcher) processes
  commands per-target rather than per-mission. This composite index supports
  efficient queue queries filtered by target_id.

  Query pattern:
    SELECT * FROM command_queue_entries
    WHERE target_id = ?
      AND status = 'pending'
      AND (scheduled_at IS NULL OR scheduled_at <= NOW())
    ORDER BY priority ASC, sequence_number ASC
    LIMIT 1
  """
  def change do
    # Index for target-scoped queue processing
    # Supports efficient per-target command retrieval in priority order
    create index(
             :command_queue_entries,
             [:target_id, :status, :priority, :sequence_number],
             name: :command_queue_entries_target_processing
           )
  end
end
