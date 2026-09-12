defmodule Cadence.Commanding.QueueLaneSequence do
  @moduledoc "Allocates durable lane order while the enqueue transaction retains its lane lock."
  import Ecto.Query
  alias Cadence.Commanding.{CommandQueueEntryRow, QueueLaneLock}
  alias Cadence.Repo

  @maximum_sequence 9_223_372_036_854_775_807

  @spec next(map()) :: {:ok, pos_integer()} | {:error, :command_queue_sequence_exhausted}
  def next(request) do
    :ok =
      QueueLaneLock.acquire(
        request.organization_id,
        request.mission_id,
        request.source_endpoint_ref
      )

    previous =
      CommandQueueEntryRow
      |> where(
        [row],
        row.organization_id == ^request.organization_id and row.mission_id == ^request.mission_id and
          row.queue_lane_key == ^request.source_endpoint_ref
      )
      |> order_by([row], desc: row.queue_sequence)
      |> select([row], row.queue_sequence)
      |> limit(1)
      |> Repo.one()

    case previous do
      nil -> {:ok, 1}
      value when value < @maximum_sequence -> {:ok, value + 1}
      _ -> {:error, :command_queue_sequence_exhausted}
    end
  end
end
