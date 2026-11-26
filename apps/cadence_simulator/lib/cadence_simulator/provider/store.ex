defmodule CadenceSimulator.Provider.Store do
  @moduledoc """
  ETS store for provider scenarios, runs, resources, and events.

  Writes are visible immediately. The store publishes a verified snapshot after
  changes on a one-second timer and on clean shutdown. A restart loads the last
  atomically published snapshot.
  """

  use GenServer

  require Logger

  @mirror :cadence_simulator_provider_store_mirror
  @metadata :cadence_simulator_provider_store_metadata
  @resource_kinds [:scenario, :run, :reservation, :delivery_profile, :opportunity, :contact]
  @scheduled_kinds [:run, :reservation, :contact]
  @sequence_key {:metadata, :event_sequence}
  @dirty_key {:snapshot, :dirty}
  @snapshot_interval_ms 1_000

  @type resource_kind ::
          :scenario | :run | :reservation | :delivery_profile | :opportunity | :contact

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(resource_kind(), map()) :: {:ok, map()}
  def put(kind, %{"id" => id} = resource) when kind in @resource_kinds do
    key = {kind, id}
    objects = [{key, resource}, {@dirty_key, true}]

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
        {@dirty_key, true}
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
      true = :ets.insert(@mirror, {@dirty_key, true})
      true
    else
      false
    end
  end

  @doc false
  def schedule_generation do
    :ets.lookup_element(@metadata, :schedule_generation, 2)
  end

  @doc false
  def take_schedule_changes do
    for key <- marked_keys(:schedule_change),
        :ets.take(@mirror, {:schedule_change, key}) != [],
        do: key
  end

  @doc false
  def diagnostics do
    memory_words = :ets.info(@mirror, :memory)

    %{
      mirror_entries: :ets.info(@mirror, :size),
      mirror_memory_words: memory_words,
      mirror_memory_bytes: memory_words * :erlang.system_info(:wordsize),
      snapshot_pending: :ets.member(@mirror, @dirty_key),
      event_count: count_keys(:event)
    }
  end

  @doc false
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc false
  @spec flush() :: :ok | {:error, term()}
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)
    :ok = File.mkdir_p(Path.dirname(path))

    case load_snapshot(path) do
      {:ok, @mirror} ->
        :ets.delete(@mirror, @dirty_key)
        :ets.select_delete(@mirror, [{{{:schedule_change, :_}, :_}, [], [true]}])
        restore_event_sequence()
        :ets.new(@metadata, [:named_table])
        reset_schedule_generation()
        schedule_snapshot()
        {:ok, %{path: path, snapshot_observer: opts[:snapshot_observer]}}

      {:ok, unexpected_table} ->
        {:stop, {:provider_store_unexpected_table, path, unexpected_table}}

      {:error, reason} ->
        {:stop, {:provider_store_open_failed, path, reason}}
    end
  end

  defp load_snapshot(path) do
    case File.stat(path) do
      {:ok, _stat} ->
        :ets.file2tab(String.to_charlist(path), verify: true)

      {:error, :enoent} ->
        {:ok,
         :ets.new(@mirror, [
           :ordered_set,
           :public,
           :named_table,
           read_concurrency: true,
           write_concurrency: true
         ])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    true = :ets.delete_all_objects(@mirror)
    reset_schedule_generation()
    true = :ets.insert(@mirror, {@dirty_key, true})
    {:reply, persist_pending(state), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, persist_pending(state), state}
  end

  @impl true
  def handle_info(:snapshot, state) do
    persist_pending(state)
    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    started = now_us()
    result = persist_pending(state)

    observe(
      state.snapshot_observer,
      {:provider_store_terminated, %{persist_us: now_us() - started}}
    )

    result
  end

  defp restore_event_sequence do
    sequence = :ets.update_counter(@mirror, @sequence_key, 0, {@sequence_key, 0})
    true = :ets.insert(@mirror, {@sequence_key, last_event_sequence(sequence)})
  end

  defp reset_schedule_generation do
    true = :ets.insert(@metadata, {:schedule_generation, make_ref()})
  end

  defp schedule_snapshot, do: Process.send_after(self(), :snapshot, @snapshot_interval_ms)

  defp persist_pending(state) do
    case :ets.take(@mirror, @dirty_key) do
      [] -> :ok
      [_marker] -> persist_snapshot(state)
    end
  end

  defp persist_snapshot(state) do
    case publish_snapshot(state) do
      :ok ->
        :ok

      {:error, reason} = error ->
        true = :ets.insert(@mirror, {@dirty_key, true})
        Logger.warning("provider store snapshot failed: #{inspect(reason)}")
        error
    end
  end

  defp publish_snapshot(state) do
    tmp = state.path <> ".tmp"
    started = now_us()

    # A writer can set the dirty flag while the dump runs. The next timer will
    # publish those writes even if some were already visited by this dump.
    with :ok <-
           :ets.tab2file(@mirror, String.to_charlist(tmp),
             extended_info: [:object_count, :md5sum],
             sync: true
           ),
         written = now_us(),
         :ok <- File.rename(tmp, state.path) do
      renamed = now_us()

      observe(state.snapshot_observer, {
        :provider_store_snapshot,
        %{
          write_us: written - started,
          rename_us: renamed - written,
          duration_us: renamed - started
        }
      })
    end
  end

  defp marked_keys(marker) do
    Stream.unfold(:ets.next(@mirror, {marker, 0}), fn
      {^marker, key} = tagged -> {key, :ets.next(@mirror, tagged)}
      _other -> nil
    end)
  end

  defp count_keys(kind), do: :ets.select_count(@mirror, [{{{kind, :_}, :_}, [], [true]}])

  defp observe(nil, _sample), do: :ok

  defp observe(pid, message) do
    send(pid, message)
    :ok
  end

  defp now_us, do: System.monotonic_time(:microsecond)

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
