defmodule CadenceSimulator.Provider.Store do
  @moduledoc """
  Durable store for provider scenarios, run snapshots, provider resources, and events.

  The store intentionally uses DETS so the simulator remains an external peer
  and does not acquire a runtime dependency on Cadence's database.

  Writes are visible in ETS immediately. Dirty keys are copied to DETS and
  synced in batches. A clean shutdown and `flush/0` persist pending changes.
  An abrupt exit can lose writes since the last batch.

  Sequence numbers and fault counters are atomic ETS counters.
  """

  use GenServer

  @table :cadence_simulator_provider_store
  @mirror :cadence_simulator_provider_store_mirror

  @resource_kinds [:scenario, :run, :reservation, :delivery_profile, :opportunity, :contact]
  @sequence_key {:metadata, :event_sequence}
  @flush_interval_ms 25
  @scheduled_kinds [:run, :reservation, :contact]

  @type resource_kind ::
          :scenario | :run | :reservation | :delivery_profile | :opportunity | :contact

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(resource_kind(), map()) :: {:ok, map()}
  def put(kind, %{"id" => id} = resource) when kind in @resource_kinds do
    key = {kind, id}
    objects = [{key, resource}, {{:dirty, key}, true}]

    objects =
      if kind in @scheduled_kinds, do: [{{:schedule_change, key}, true} | objects], else: objects

    true = :ets.insert(@mirror, objects)
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

    key = {:event, sequence}

    true =
      :ets.insert(@mirror, [
        {key, stored_event},
        {{:dirty, key}, true},
        {{:dirty, @sequence_key}, true}
      ])

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
      true = :ets.insert(@mirror, {{:dirty, key}, true})
      true
    else
      false
    end
  end

  @doc false
  def schedule_generation do
    :ets.lookup_element(@mirror, {:schedule, :generation}, 2)
  end

  @doc false
  def take_schedule_changes, do: take_marked(:schedule_change)

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
        reset_schedule_generation()
        schedule_flush()
        {:ok, @table}

      {:error, reason} ->
        {:stop, {:provider_store_open_failed, path, reason}}
    end
  end

  @impl true
  def handle_call(:clear, _from, table) do
    true = :ets.delete_all_objects(@mirror)
    reset_schedule_generation()
    :ok = :dets.delete_all_objects(table)
    :ok = :dets.sync(table)
    {:reply, :ok, table}
  end

  def handle_call(:flush, _from, table) do
    :ok = persist_batch(table)
    {:reply, :ok, table}
  end

  @impl true
  def handle_info(:flush, table) do
    :ok = persist_batch(table)
    schedule_flush()
    {:noreply, table}
  end

  @impl true
  def terminate(_reason, table) do
    :ok = persist_batch(table)
    :dets.close(table)
  end

  defp reset_schedule_generation do
    true = :ets.insert(@mirror, {{:schedule, :generation}, make_ref()})
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)

  defp persist_batch(table) do
    objects = Enum.flat_map(take_marked(:dirty), &:ets.lookup(@mirror, &1))

    case objects do
      [] ->
        :ok

      [_ | _] ->
        :ok = :dets.insert(table, objects)
        :dets.sync(table)
    end
  end

  defp take_marked(marker), do: take_marked(marker, :ets.next(@mirror, {marker, 0}), [])

  defp take_marked(marker, {marker, key} = tagged, keys) do
    keys =
      case :ets.take(@mirror, tagged) do
        [_] -> [key | keys]
        [] -> keys
      end

    take_marked(marker, :ets.next(@mirror, tagged), keys)
  end

  defp take_marked(_marker, _next, keys), do: keys

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
