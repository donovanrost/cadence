defmodule Cadence.Commanding.LaneDispatcher.Summary do
  @moduledoc "What a lane dispatcher reports: its drain summary and its last dispatch result."

  @doc "A drain's quiescence summary."
  @spec quiescence(atom(), non_neg_integer(), DateTime.t() | nil) :: map()
  def quiescence(status, released_count, next_not_before \\ nil) do
    %{released_count: released_count, status: status, next_not_before: next_not_before}
  end

  @doc "The dispatch result as `status/2` reports it: the outcome, without the release payload."
  @spec result(term()) :: term()
  def result({:ok, _release_result}), do: :released
  def result({:error, :command_queue_lane_empty}), do: :empty

  def result({:error, {:command_queue_lane_waiting_for_not_before, _entry, not_before}}),
    do: {:waiting_for_not_before, not_before}

  def result({:error, {:command_queue_lane_no_release_target, source_endpoint_ref, _}}),
    do: {:no_release_target, source_endpoint_ref}

  def result({:error, {:command_release_refused, attempt_id, reason}}),
    do: {:release_refused, attempt_id, reason}

  def result({:error, reason}), do: {:error, reason}
end
