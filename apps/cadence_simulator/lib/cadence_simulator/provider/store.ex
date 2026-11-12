defmodule CadenceSimulator.Provider.Store do
  @moduledoc """
  Durable store for provider scenarios, run snapshots, provider resources, and events.

  The store intentionally uses DETS so the simulator remains an external peer
  and does not acquire a runtime dependency on Cadence's database.

  Reads go to an ETS mirror in the calling process, never through this process (qa #46).
  The Orchestrator reads on every 100 ms tick. When each list scanned the DETS file
  inside this one process, a load spike queued calls past their 5 s timeout and crashed
  the Orchestrator mid-pass, which orphans uplink peers.

  * A write lands in ETS at once, so every reader sees it. The caller then waits, at
    most `@persist_timeout_ms`, for this process to copy the key's current ETS value to
    DETS and sync. It copies the value, not the message, so DETS converges on ETS
    whatever order writers race in.
  * Durability: a write that returned normally is on disk. One whose wait timed out
    (logged) is still queued here and persists when this process catches up; a crash
    before then loses it. A clean stop flushes the whole mirror.
  * Sequence numbers and fault counters are atomic ETS counters.
  """

  use GenServer

  require Logger

  @table :cadence_simulator_provider_store
  @mirror :cadence_simulator_provider_store_mirror

  @resource_kinds [:scenario, :run, :reservation, :delivery_profile, :opportunity, :contact]
  @sequence_key {:metadata, :event_sequence}
  @persist_timeout_ms 1_000

  @type resource_kind ::
          :scenario | :run | :reservation | :delivery_profile | :opportunity | :contact

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(resource_kind(), map()) :: {:ok, map()}
  def put(kind, %{"id" => id} = resource) when kind in @resource_kinds do
    true = :ets.insert(@mirror, {{kind, id}, resource})
    persist([{kind, id}])
    {:ok, resource}
  end

  @spec fetch(resource_kind(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(kind, id) when kind in @resource_kinds and is_binary(id) do
    case :ets.lookup(@mirror, {kind, id}) do
      [{{^kind, ^id}, resource}] -> {:ok, resource}
      [] -> {:error, :not_found}
    end
  end

  @spec list(resource_kind()) :: [map()]
  def list(kind) when kind in @resource_kinds do
    @mirror
    |> :ets.select([{{{kind, :_}, :"$1"}, [], [:"$1"]}])
    |> Enum.sort_by(&Map.get(&1, "created_at", ""), :desc)
  end

  @spec append_event(map()) :: {:ok, map()}
  def append_event(event) when is_map(event) do
    sequence = :ets.update_counter(@mirror, @sequence_key, 1, {@sequence_key, 0})

    stored_event =
      event
      |> Map.put("id", "event-#{sequence}")
      |> Map.put("sequence", sequence)
      |> Map.put_new("occurred_at", DateTime.utc_now() |> DateTime.to_iso8601())

    true = :ets.insert(@mirror, {{:event, sequence}, stored_event})
    persist([{:event, sequence}, @sequence_key])
    {:ok, stored_event}
  end

  @spec events(non_neg_integer(), pos_integer()) :: %{
          data: [map()],
          next_cursor: non_neg_integer()
        }
  def events(cursor \\ 0, limit \\ 100)
      when is_integer(cursor) and cursor >= 0 and is_integer(limit) and limit > 0 do
    data = cursor |> events_after() |> Stream.take(min(limit, 500)) |> Enum.to_list()
    %{data: data, next_cursor: data |> List.last() |> event_sequence_or(cursor)}
  end

  @spec events_for_run(binary(), non_neg_integer(), pos_integer()) :: %{
          data: [map()],
          next_cursor: non_neg_integer()
        }
  def events_for_run(run_id, cursor \\ 0, limit \\ 100)
      when is_binary(run_id) and is_integer(cursor) and cursor >= 0 and is_integer(limit) and
             limit > 0 do
    data =
      cursor
      |> events_after()
      |> Stream.filter(&(&1["run_id"] == run_id))
      |> Stream.take(min(limit, 500))
      |> Enum.to_list()

    # With no event for this run, skip past every event already scanned.
    next_cursor =
      case List.last(data) do
        nil -> last_event_sequence(cursor)
        event -> event["sequence"]
      end

    %{data: data, next_cursor: next_cursor}
  end

  @doc "Atomically consumes one occurrence of a durable, run-scoped fault counter."
  @spec consume_fault(binary(), binary(), non_neg_integer()) :: boolean()
  def consume_fault(run_id, fault, limit)
      when is_binary(run_id) and is_binary(fault) and is_integer(limit) and limit >= 0 do
    key = {:fault_counter, run_id, fault}

    # One atomic step: read the count, then add 1 capped at `limit`.
    [consumed, _capped] =
      :ets.update_counter(@mirror, key, [{2, 0}, {2, 1, limit, limit}], {key, 0})

    if consumed < limit do
      persist([key])
      true
    else
      false
    end
  end

  @doc false
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc false
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)
    :ok = File.mkdir_p(Path.dirname(path))

    case :dets.open_file(@table, type: :set, file: String.to_charlist(path)) do
      {:ok, @table} ->
        mirror =
          :ets.new(@mirror, [
            :ordered_set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: true
          ])

        @mirror = :dets.to_ets(@table, mirror)
        {:ok, %{table: @table, path: path}}

      {:error, reason} ->
        {:stop, {:provider_store_open_failed, path, reason}}
    end
  end

  @impl true
  def handle_call({:persist, keys}, _from, state) do
    Enum.each(keys, &persist_key(state.table, &1))
    :ok = :dets.sync(state.table)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    true = :ets.delete_all_objects(@mirror)
    :ok = :dets.delete_all_objects(state.table)
    :ok = :dets.sync(state.table)
    {:reply, :ok, state}
  end

  # Persists queued before this call are already handled, in order.
  def handle_call(:flush, _from, state) do
    :ok = :dets.sync(state.table)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Persist whatever is still queued: the mirror holds every write.
    @table = :ets.to_dets(@mirror, state.table)
    :dets.close(state.table)
  end

  # The write is already visible in ETS. If this process is too slow to answer, the
  # request stays queued and persists later; the caller isn't held up or crashed.
  defp persist(keys) do
    GenServer.call(__MODULE__, {:persist, keys}, @persist_timeout_ms)
  catch
    :exit, {:timeout, _call} ->
      Logger.warning(
        "provider store: persisting #{inspect(keys)} is queued past #{@persist_timeout_ms} ms"
      )
  end

  defp persist_key(table, key) do
    case :ets.lookup(@mirror, key) do
      [object] -> :ok = :dets.insert(table, object)
      [] -> :ok = :dets.delete(table, key)
    end
  end

  # Events after `cursor`, in sequence order, read lazily in chunks.
  defp events_after(cursor) do
    match_spec = [{{{:event, :"$1"}, :"$2"}, [{:>, :"$1", cursor}], [:"$2"]}]

    Stream.resource(
      fn -> :ets.select(@mirror, match_spec, 200) end,
      fn
        :"$end_of_table" -> {:halt, :done}
        {events, continuation} -> {events, :ets.select(continuation)}
      end,
      fn _acc -> :ok end
    )
  end

  # The newest event's sequence when it's past `cursor`.
  defp last_event_sequence(cursor) do
    case :ets.prev(@mirror, {:event, :infinity}) do
      {:event, sequence} when is_integer(sequence) and sequence > cursor -> sequence
      _other -> cursor
    end
  end

  defp event_sequence_or(nil, fallback), do: fallback
  defp event_sequence_or(event, _fallback), do: event["sequence"]
end
