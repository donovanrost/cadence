defmodule Cadence.Reads.DurableReceiptCacheTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Reads.DurableReceiptCache

  setup do
    key = {:cache_test, System.unique_integer([:positive])}
    saved = Application.get_env(:cadence, :fleet_durable_receipts_ttl_ms)
    Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, 60_000)

    on_exit(fn ->
      DurableReceiptCache.forget(key)

      if saved,
        do: Application.put_env(:cadence, :fleet_durable_receipts_ttl_ms, saved),
        else: Application.delete_env(:cadence, :fleet_durable_receipts_ttl_ms)
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
end
