defmodule Cadence.Reads.DurableReceiptCacheTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Reads.DurableReceiptCache

  setup do
    key = {:cache_test, System.unique_integer([:positive])}
    saved = Application.get_env(:cadence, :durable_receipts_ttl_ms)
    Application.put_env(:cadence, :durable_receipts_ttl_ms, 60_000)

    on_exit(fn ->
      DurableReceiptCache.forget(key)

      if saved,
        do: Application.put_env(:cadence, :durable_receipts_ttl_ms, saved),
        else: Application.delete_env(:cadence, :durable_receipts_ttl_ms)
    end)

    %{key: key}
  end

  defp counting_fetch(counter, receipts) do
    fn ->
      :counters.add(counter, 1, 1)
      {:ok, receipts}
    end
  end

  test "the first read asks the store, later reads use the answer, and nothing goes to :persistent_term",
       %{key: key} do
    counter = :counters.new(1, [])
    fetch = counting_fetch(counter, %{"sc-1" => ~U[2026-11-27 12:00:00Z]})

    assert %{telemetry: :ok, receipts: %{"sc-1" => _}} = DurableReceiptCache.get(key, fetch)
    assert %{telemetry: :ok} = DurableReceiptCache.get(key, fetch)
    assert :counters.get(counter, 1) == 1

    assert [{^key, _at, _read_at, nil, %{telemetry: :ok}}] = :ets.lookup(DurableReceiptCache, key)
    assert :persistent_term.get({DurableReceiptCache, key}, :none) == :none
  end

  test "a store that fails is a degraded answer, and a key nobody has read for long is swept away",
       %{key: key} do
    assert %{telemetry: :degraded, receipts: receipts} =
             DurableReceiptCache.get(key, fn -> {:error, :down} end)

    assert receipts == %{}

    # Read long ago: the sweep forgets it.
    :ets.update_element(
      DurableReceiptCache,
      key,
      {3, System.monotonic_time(:millisecond) - 3_600_000}
    )

    send(DurableReceiptCache, :sweep)
    _ = :sys.get_state(DurableReceiptCache)

    assert :ets.lookup(DurableReceiptCache, key) == []
  end

  test "a read keeps its key alive: the sweep leaves a key read just now", %{key: key} do
    fetch = fn -> {:ok, %{}} end
    DurableReceiptCache.get(key, fetch)
    DurableReceiptCache.get(key, fetch)

    send(DurableReceiptCache, :sweep)
    _ = :sys.get_state(DurableReceiptCache)

    assert [{^key, _, _, _, _}] = :ets.lookup(DurableReceiptCache, key)
  end

  test "a fetch that raises, exits or throws answers :degraded and does not reach the reader", %{
    key: key
  } do
    for {fetch, tag} <- [
          {fn -> raise "the store blew up" end, :raise},
          {fn -> exit(:the_store_died) end, :exit},
          {fn -> throw(:the_store_threw) end, :throw}
        ] do
      assert %{telemetry: :degraded, receipts: %{}} =
               DurableReceiptCache.get({key, tag}, fetch)

      DurableReceiptCache.forget({key, tag})
    end

    # The reader is still alive, and not linked to any of those tasks.
    assert Process.alive?(self())
    assert %{telemetry: :ok} = DurableReceiptCache.get(key, fn -> {:ok, %{}} end)
  end

  test "a refresh in the background is a child of the cache's task supervisor, not a bare task",
       %{key: key} do
    parent = self()

    # TTL 1 ms: the second read finds the answer expired and refreshes it in the background.
    Application.put_env(:cadence, :durable_receipts_ttl_ms, 1)
    DurableReceiptCache.get(key, fn -> {:ok, %{}} end)
    Process.sleep(5)

    DurableReceiptCache.get(key, fn ->
      send(parent, {:refresh, Process.info(self(), :dictionary)})
      {:ok, %{}}
    end)

    assert_receive {:refresh, {:dictionary, dictionary}}, 2_000
    refute dictionary[:"$callers"] == nil

    supervisor = Process.whereis(Cadence.Reads.DurableReceiptCache.Tasks)
    assert is_pid(supervisor)
  end
end
