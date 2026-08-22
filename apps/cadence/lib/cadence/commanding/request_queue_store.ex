defmodule Cadence.Commanding.RequestQueueStore do
  @moduledoc """
  Persists control-owned command queue entries and their lifecycle transitions.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandRequest,
    CommandRequestRow,
    LifecyclePolicy,
    RequestStore
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
    with {:ok, %CommandRequestRow{} = request_row} <-
           RequestStore.fetch_request_row(organization_id, mission_id, command_request_id),
         :ok <- LifecyclePolicy.ensure_request_queueable(request_row),
         :ok <- LifecyclePolicy.ensure_request_not_expired(request_row),
         :ok <- ensure_request_not_already_queued(organization_id, mission_id, command_request_id) do
      queue_entry =
        CommandQueueEntry.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          command_request_id: command_request_id,
          source_endpoint_ref: request_row.source_endpoint_ref,
          queue_lane_key: request_row.source_endpoint_ref,
          priority: request_row.priority,
          queue_sequence: System.unique_integer([:positive, :monotonic]),
          not_before: request_row.not_before,
          expires_at: request_row.expires_at,
          lifecycle_state: :pending,
          enqueued_by: enqueued_by,
          enqueued_at: Keyword.get(opts, :enqueued_at, DateTime.utc_now()),
          metadata: Keyword.get(opts, :metadata, %{})
        })

      multi =
        Multi.new()
        |> Multi.insert(:queue_entry, CommandQueueEntryRow.changeset(queue_entry))
        |> Multi.update(
          :command_request,
          CommandRequestRow.lifecycle_changeset(request_row, :queued)
        )

      case Repo.transaction(multi) do
        {:ok, %{queue_entry: queue_entry_row, command_request: updated_request_row}} ->
          {:ok,
           %{
             queue_entry: CommandQueueEntryRow.to_domain(queue_entry_row),
             command_request: CommandRequestRow.to_domain(updated_request_row)
           }}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
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

  @spec requeue_release_pending() :: non_neg_integer()
  def requeue_release_pending do
    {updated_count, _rows} =
      CommandQueueEntryRow
      |> where([row], row.lifecycle_state == "release_pending")
      |> Repo.update_all(set: [lifecycle_state: "pending"])

    updated_count
  end

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

  @spec claim_for_release(struct()) :: {:ok, struct()} | {:error, term()}
  def claim_for_release(%CommandQueueEntryRow{} = queue_entry_row) do
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

  @spec restore_pending(struct()) :: :ok
  def restore_pending(%CommandQueueEntryRow{} = queue_entry_row) do
    _ =
      queue_entry_row
      |> CommandQueueEntryRow.lifecycle_changeset(:pending)
      |> Repo.update()

    :ok
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
