defmodule Cadence.Commanding.RequestQueueStore do
  @moduledoc """
  Persists control-owned command queue entries and their lifecycle transitions.
  """

  import Ecto.Query

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandRequest,
    CommandRequestRow,
    LifecyclePolicy,
    QueueLaneLock,
    QueueLaneSequence
  }

  alias Cadence.Repo

  @spec enqueue_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{command_request: CommandRequest.t(), queue_entry: CommandQueueEntry.t()}}
          | {:error, term()}
  def enqueue_request(
        organization_id,
        mission_id,
        command_request_id,
        enqueued_by,
        opts
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(enqueued_by) and is_list(opts) do
    Repo.transaction(fn ->
      with {:ok, request_row} <- lock_request(organization_id, mission_id, command_request_id),
           :ok <- LifecyclePolicy.ensure_request_queueable(request_row),
           :ok <- LifecyclePolicy.ensure_request_not_expired(request_row),
           :ok <-
             ensure_request_not_already_queued(organization_id, mission_id, command_request_id),
           {:ok, sequence} <- QueueLaneSequence.next(request_row),
           :ok <- LifecyclePolicy.ensure_request_not_expired(request_row),
           :ok <- validate_request(request_row, opts),
           {:ok, queue_row} <- insert_queue_entry(request_row, sequence, enqueued_by, opts),
           {:ok, updated_request_row} <-
             Repo.update(CommandRequestRow.lifecycle_changeset(request_row, :queued)) do
        %{
          queue_entry: CommandQueueEntryRow.to_domain(queue_row),
          command_request: CommandRequestRow.to_domain(updated_request_row)
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp lock_request(organization_id, mission_id, command_request_id) do
    row =
      CommandRequestRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_request_id == ^command_request_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()

    case row do
      nil -> {:error, :command_request_not_found}
      %CommandRequestRow{} -> {:ok, row}
    end
  end

  defp validate_request(row, opts) do
    case Keyword.get(opts, :before_enqueue) do
      nil -> :ok
      check when is_function(check, 1) -> check.(CommandRequestRow.to_domain(row))
      _ -> {:error, :invalid_queue_precondition}
    end
  end

  defp insert_queue_entry(request_row, sequence, enqueued_by, opts) do
    CommandQueueEntry.new(%{
      organization_id: request_row.organization_id,
      mission_id: request_row.mission_id,
      command_request_id: request_row.command_request_id,
      source_endpoint_ref: request_row.source_endpoint_ref,
      queue_lane_key: request_row.source_endpoint_ref,
      priority: request_row.priority,
      queue_sequence: sequence,
      not_before: request_row.not_before,
      expires_at: request_row.expires_at,
      lifecycle_state: :pending,
      enqueued_by: enqueued_by,
      enqueued_at: Keyword.get(opts, :enqueued_at, DateTime.utc_now()),
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> CommandQueueEntryRow.changeset()
    |> Repo.insert()
  end

  @spec fetch_queue_entry(binary(), binary(), binary()) ::
          {:ok, CommandQueueEntry.t()} | {:error, term()}
  def fetch_queue_entry(organization_id, mission_id, command_queue_entry_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) do
    with {:ok, %CommandQueueEntryRow{} = row} <-
           fetch_queue_entry_row(organization_id, mission_id, command_queue_entry_id) do
      {:ok, CommandQueueEntryRow.to_domain(row)}
    end
  end

  @spec list_queue_entries(binary(), binary(), keyword()) :: [CommandQueueEntry.t()]
  def list_queue_entries(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandQueueEntryRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:queue_lane_key, Keyword.get(opts, :queue_lane_key))
    |> maybe_filter_equals(:lifecycle_state, normalized_filter(opts, :lifecycle_state))
    |> order_by([row],
      asc: row.queue_lane_key,
      asc: row.priority,
      asc: row.queue_sequence,
      asc: row.command_queue_entry_id
    )
    |> Repo.all()
    |> Enum.map(&CommandQueueEntryRow.to_domain/1)
  end

  @spec list_pending_lanes(keyword()) :: [
          %{organization_id: binary(), mission_id: binary(), queue_lane_key: binary()}
        ]
  def list_pending_lanes(opts) when is_list(opts) do
    CommandQueueEntryRow
    |> where([row], row.lifecycle_state == "pending")
    |> maybe_filter_equals(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter_equals(:mission_id, Keyword.get(opts, :mission_id))
    |> distinct([row], [row.organization_id, row.mission_id, row.queue_lane_key])
    |> order_by([row], asc: row.organization_id, asc: row.mission_id, asc: row.queue_lane_key)
    |> select([row], %{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      queue_lane_key: row.queue_lane_key
    })
    |> Repo.all()
  end

  @spec pending_target_lanes(binary() | nil, binary(), [binary()]) :: [
          %{organization_id: binary(), mission_id: binary(), queue_lane_key: binary()}
        ]
  def pending_target_lanes(nil, mission_id, lane_keys) do
    CommandQueueEntryRow
    |> where([row], row.mission_id == ^mission_id)
    |> pending_target_lanes_query(lane_keys)
  end

  def pending_target_lanes(organization_id, mission_id, lane_keys)
      when is_binary(organization_id) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> pending_target_lanes_query(lane_keys)
  end

  @doc """
  Retains incomplete release claims across dispatcher restarts.

  Missing completion evidence does not prove that transmission did not occur.
  This compatibility entry performs no automatic requeue; the exact attempt
  must be resolved before its lane can be released.
  """
  @spec requeue_release_pending() :: non_neg_integer()
  def requeue_release_pending, do: 0

  @spec fetch_queue_entry_row(binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, term()}
  def fetch_queue_entry_row(organization_id, mission_id, command_queue_entry_id) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_queue_entry_id: command_queue_entry_id
         ) do
      nil -> {:error, :command_queue_entry_not_found}
      %CommandQueueEntryRow{} = row -> {:ok, row}
    end
  end

  @spec ensure_lane_not_in_flight(binary(), binary(), binary()) :: :ok | {:error, term()}
  def ensure_lane_not_in_flight(organization_id, mission_id, queue_lane_key)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           queue_lane_key: queue_lane_key,
           lifecycle_state: "release_pending"
         ) do
      nil ->
        :ok

      %CommandQueueEntryRow{} ->
        {:error, {:command_queue_lane_release_pending, queue_lane_key}}
    end
  end

  @spec ensure_entry_is_next_release_candidate(struct(), DateTime.t()) ::
          :ok | {:error, term()}
  def ensure_entry_is_next_release_candidate(
        %CommandQueueEntryRow{} = queue_entry_row,
        %DateTime{} = attempted_at
      ) do
    case next_release_candidate(
           queue_entry_row.organization_id,
           queue_entry_row.mission_id,
           queue_entry_row.queue_lane_key,
           attempted_at
         ) do
      nil ->
        {:error, {:command_queue_lane_empty, queue_entry_row.queue_lane_key}}

      %CommandQueueEntryRow{command_queue_entry_id: queue_entry_id}
      when queue_entry_id == queue_entry_row.command_queue_entry_id ->
        :ok

      %CommandQueueEntryRow{} = next_queue_entry_row ->
        {:error,
         {:command_queue_entry_not_next_for_release, queue_entry_row.command_queue_entry_id,
          next_queue_entry_row.command_queue_entry_id}}
    end
  end

  @spec next_dispatch_candidate(binary(), binary(), binary(), DateTime.t()) ::
          {:ok, struct()} | {:error, term()}
  def next_dispatch_candidate(
        organization_id,
        mission_id,
        queue_lane_key,
        %DateTime{} = attempted_at
      ) do
    case next_release_candidate(organization_id, mission_id, queue_lane_key, attempted_at) do
      %CommandQueueEntryRow{} = queue_entry_row ->
        {:ok, queue_entry_row}

      nil ->
        case next_pending_not_before(organization_id, mission_id, queue_lane_key, attempted_at) do
          %DateTime{} = not_before ->
            {:error, {:command_queue_lane_waiting_for_not_before, queue_lane_key, not_before}}

          nil ->
            {:error, :command_queue_lane_empty}
        end
    end
  end

  @doc "Rechecks queue order, occupancy and the prepared request under the request and lane locks."
  @spec claim_for_release(struct(), keyword()) :: {:ok, struct()} | {:error, term()}
  def claim_for_release(%CommandQueueEntryRow{} = expected_queue, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, request} <-
             lock_request(
               expected_queue.organization_id,
               expected_queue.mission_id,
               expected_queue.command_request_id
             ),
           :ok <-
             QueueLaneLock.acquire(
               expected_queue.organization_id,
               expected_queue.mission_id,
               expected_queue.queue_lane_key
             ),
           {:ok, queue} <-
             fetch_queue_entry_row(
               expected_queue.organization_id,
               expected_queue.mission_id,
               expected_queue.command_queue_entry_id
             ),
           attempted_at = Keyword.get_lazy(opts, :attempted_at, &DateTime.utc_now/0),
           :ok <- LifecyclePolicy.ensure_queue_entry_releaseable(queue, attempted_at),
           :ok <- LifecyclePolicy.ensure_request_releasable(request),
           :ok <- LifecyclePolicy.ensure_request_not_expired(request),
           :ok <- release_basis_matches(queue, expected_queue, request, opts),
           :ok <-
             ensure_lane_not_in_flight(
               queue.organization_id,
               queue.mission_id,
               queue.queue_lane_key
             ),
           :ok <- ensure_entry_is_next_release_candidate(queue, attempted_at),
           {:ok, claimed} <- update_release_claim(queue) do
        claimed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp release_basis_matches(queue, expected_queue, request, opts) do
    expected_request = Keyword.get(opts, :expected_request, request)

    if is_nil(queue.active_release_attempt_id) and
         queue.active_release_attempt_id == expected_queue.active_release_attempt_id and
         CommandQueueEntryRow.to_domain(queue) == CommandQueueEntryRow.to_domain(expected_queue) and
         match?(%CommandRequestRow{}, expected_request) and
         CommandRequestRow.to_domain(request) == CommandRequestRow.to_domain(expected_request),
       do: :ok,
       else: {:error, :command_release_basis_changed}
  end

  defp update_release_claim(queue_entry_row) do
    {updated_count, _rows} =
      CommandQueueEntryRow
      |> where(
        [row],
        row.organization_id == ^queue_entry_row.organization_id and
          row.mission_id == ^queue_entry_row.mission_id and
          row.command_queue_entry_id == ^queue_entry_row.command_queue_entry_id and
          row.lifecycle_state == "pending"
      )
      |> Repo.update_all(set: [lifecycle_state: "release_pending"])

    if updated_count == 1 do
      fetch_queue_entry_row(
        queue_entry_row.organization_id,
        queue_entry_row.mission_id,
        queue_entry_row.command_queue_entry_id
      )
    else
      {:error,
       {:command_queue_entry_not_releasable, queue_entry_row.command_queue_entry_id,
        queue_entry_row.lifecycle_state}}
    end
  end

  defp pending_target_lanes_query(query, lane_keys) when is_list(lane_keys) do
    query
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], row.queue_lane_key in ^lane_keys)
    |> distinct([row], [row.organization_id, row.mission_id, row.queue_lane_key])
    |> order_by([row], asc: row.organization_id, asc: row.mission_id, asc: row.queue_lane_key)
    |> select([row], %{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      queue_lane_key: row.queue_lane_key
    })
    |> Repo.all()
  end

  defp ensure_request_not_already_queued(organization_id, mission_id, command_request_id) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> :ok
      %CommandQueueEntryRow{} -> {:error, {:command_request_already_queued, command_request_id}}
    end
  end

  defp next_release_candidate(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       )
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    pending_release_candidates_query(organization_id, mission_id, queue_lane_key, attempted_at)
    |> order_by([row],
      asc: row.priority,
      asc: row.queue_sequence,
      asc: row.command_queue_entry_id
    )
    |> limit(1)
    |> Repo.one()
  end

  defp pending_release_candidates_query(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       ) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id)
    |> where([row], row.mission_id == ^mission_id)
    |> where([row], row.queue_lane_key == ^queue_lane_key)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], is_nil(row.not_before) or row.not_before <= ^attempted_at)
    |> where([row], is_nil(row.expires_at) or row.expires_at >= ^attempted_at)
  end

  defp next_pending_not_before(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       ) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id)
    |> where([row], row.mission_id == ^mission_id)
    |> where([row], row.queue_lane_key == ^queue_lane_key)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], not is_nil(row.not_before) and row.not_before > ^attempted_at)
    |> where([row], is_nil(row.expires_at) or row.expires_at >= ^attempted_at)
    |> order_by([row], asc: row.not_before, asc: row.queue_sequence)
    |> select([row], row.not_before)
    |> limit(1)
    |> Repo.one()
  end

  defp normalized_filter(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end
end
