defmodule Cadence.Reads.DurableReceiptCache do
  @moduledoc """
  The durable history store's answer to "when was this heard", for the reads that fill in what a
  node's live current-value store does not hold (Fleet's per-spacecraft receipts, #798; a
  spacecraft's per-point receipts, #143).

  The history store (QuestDB in production) can hang and is a query against a time-series store, so
  it is not asked on every read: the first read of a key waits for it (so a restart never reports
  something heard as never heard), later reads use the last answer, refreshed in the background once
  it is `durable_receipts_ttl_ms` old (60 s; 0 asks every time). A slow or failed store
  (`durable_receipts_timeout_ms`, 3 s) answers `telemetry: :degraded`, kept for 5 s only, so
  a recovered store is picked up soon.

  The answers live in an ETS table owned by this supervised process (a refresh is one `insert`;
  `:persistent_term` would scan every process on each update, and these change every minute per
  spacecraft viewed). A key nobody has read for ten times the TTL (at least ten minutes) is swept
  away, so the table is bounded by what is being looked at, not by everything ever looked at.
  Without the process (a unit test that does not start the application) every read asks the store.

  **A fetch that raises or exits answers `:degraded` too**, for any fetch, not only one that
  returns `{:error, _}`: it runs in a task under `Cadence.Reads.DurableReceiptCache.Tasks` (not
  linked to the reader) and the background refreshes run there as well, so they stop with the tree.
  A key nobody has cached yet asks the store once per concurrent reader until the first answer is
  stored (fine at these read rates; a spacecraft page several operators open right after a restart
  asks once each).

  The settings are `durable_receipts_ttl_ms` and `durable_receipts_timeout_ms`; the old
  `fleet_durable_receipts_*` names are still read when the new ones are not set.

  The caller's `fetch` returns `{:ok, receipts}` or an error; the cache answers
  `%{receipts: receipts, telemetry: :ok | :degraded}`.
  """

  use GenServer

  @table __MODULE__
  @durable_timeout_ms 3_000
  @durable_ttl_ms 60_000
  @degraded_ttl_ms 5_000
  @sweep_ms 300_000
  @min_keep_ms 600_000

  @type answer :: %{receipts: map(), telemetry: :ok | :degraded}

  @tasks Cadence.Reads.DurableReceiptCache.Tasks

  # The cache's process, with the supervisor of the tasks that ask the store (one rest-for-one
  # unit under the application: the tasks go when the cache does).
  def child_spec(opts) do
    %{
      id: __MODULE__,
      type: :supervisor,
      start:
        {Supervisor, :start_link,
         [
           [{Task.Supervisor, name: @tasks}, owner(opts)],
           [strategy: :one_for_all, name: Cadence.Reads.DurableReceiptCache.Supervisor]
         ]}
    }
  end

  defp owner(opts), do: %{id: :owner, start: {__MODULE__, :start_link, [opts]}}

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(System.monotonic_time(:millisecond))
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @spec get(term(), (-> {:ok, map()} | term())) :: answer()
  def get(key, fetch) when is_function(fetch, 0) do
    now = System.monotonic_time(:millisecond)

    case {ttl_ms(), lookup(key)} do
      {0, _cached} ->
        ask(fetch)

      {_ttl, nil} ->
        fetch |> ask() |> remember(key, now)

      {ttl, %{value: value} = cached} ->
        if expired?(cached, ttl, now), do: refresh(key, fetch, cached, now)
        touch(key, now)
        value
    end
  end

  @doc "Forgets a key (tests)."
  @spec forget(term()) :: :ok
  def forget(key) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, key)
    :ok
  end

  # An entry is `{key, at, read_at, refreshing_since, value}`: the times are updated in place (a
  # read does not copy the receipts back into the table).
  defp lookup(key) do
    if :ets.whereis(@table) == :undefined do
      nil
    else
      case :ets.lookup(@table, key) do
        [{^key, at, read_at, refreshing_since, value}] ->
          %{at: at, read_at: read_at, refreshing_since: refreshing_since, value: value}

        [] ->
          nil
      end
    end
  end

  defp store(key, %{at: at, read_at: read_at, refreshing_since: since, value: value}) do
    if :ets.whereis(@table) != :undefined,
      do: :ets.insert(@table, {key, at, read_at, since, value})

    :ok
  end

  # A good answer lives the TTL; a degraded one (the store did not answer) only a few seconds.
  defp expired?(%{at: at, value: %{telemetry: :ok}}, ttl, now), do: now - at >= ttl
  defp expired?(%{at: at}, ttl, now), do: now - at >= min(ttl, @degraded_ttl_ms)

  defp remember(value, key, now) do
    store(key, %{at: now, read_at: now, value: value, refreshing_since: nil})
    value
  end

  # What was read last, for the sweep.
  defp touch(key, now) do
    if :ets.whereis(@table) != :undefined, do: :ets.update_element(@table, key, {3, now})
    :ok
  end

  # One refresh at a time per key, off the read's path.
  defp refresh(key, fetch, cached, now) do
    unless is_integer(cached.refreshing_since) and now - cached.refreshing_since < 10_000 do
      store(key, %{cached | refreshing_since: now})

      Task.Supervisor.start_child(@tasks, fn ->
        fetch |> ask() |> remember(key, System.monotonic_time(:millisecond))
      end)
    end

    :ok
  end

  # The fetch runs in a task of its own, not linked to the reader, and whatever it does (return an
  # error, raise, exit, take too long) is a degraded answer, never a crash of the request.
  defp ask(fetch) do
    if Process.whereis(@tasks) == nil,
      do: ask_inline(fetch),
      else: ask_in_task(fetch)
  end

  defp ask_in_task(fetch) do
    task = Task.Supervisor.async_nolink(@tasks, fn -> guarded(fetch) end)

    case Task.yield(task, timeout_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, receipts}} -> %{receipts: receipts, telemetry: :ok}
      _unavailable_slow_or_crashed -> %{receipts: %{}, telemetry: :degraded}
    end
  end

  # Without the supervisor (a unit test without the application): the same, in a bare task.
  defp ask_inline(fetch) do
    task = Task.async(fn -> guarded(fetch) end)

    case Task.yield(task, timeout_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, receipts}} -> %{receipts: receipts, telemetry: :ok}
      _unavailable_or_slow -> %{receipts: %{}, telemetry: :degraded}
    end
  end

  defp guarded(fetch) do
    fetch.()
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp sweep(now) do
    keep = max(ttl_ms() * 10, @min_keep_ms)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1", :_, :_}, [{:<, :"$1", now - keep}], [true]}
    ])
  end

  defp ttl_ms,
    do: setting(:durable_receipts_ttl_ms, :fleet_durable_receipts_ttl_ms, @durable_ttl_ms)

  defp timeout_ms,
    do:
      setting(
        :durable_receipts_timeout_ms,
        :fleet_durable_receipts_timeout_ms,
        @durable_timeout_ms
      )

  # The new name, else the old one (`fleet_durable_receipts_*`), else the default.
  defp setting(name, old_name, default),
    do: Application.get_env(:cadence, name, Application.get_env(:cadence, old_name, default))
end
