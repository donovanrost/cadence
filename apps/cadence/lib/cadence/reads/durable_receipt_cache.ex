defmodule Cadence.Reads.DurableReceiptCache do
  @moduledoc """
  The durable history store's answer to "when was this heard", for the reads that fill in what a
  node's live current-value store does not hold (Fleet's per-spacecraft receipts, #798; a
  spacecraft's per-point receipts, #143).

  The history store (QuestDB in production) can hang and is a query against a time-series store, so
  it is not asked on every read: the first read of a key waits for it (so a restart never reports
  something heard as never heard), later reads use the last answer, refreshed in the background once
  it is `fleet_durable_receipts_ttl_ms` old (60 s; 0 asks every time). A slow or failed store
  (`fleet_durable_receipts_timeout_ms`, 3 s) answers `telemetry: :degraded`, kept for 5 s only, so
  a recovered store is picked up soon.

  The caller's `fetch` returns `{:ok, receipts}` or an error; the cache answers
  `%{receipts: receipts, telemetry: :ok | :degraded}`.
  """

  @durable_timeout_ms 3_000
  @durable_ttl_ms 60_000
  @degraded_ttl_ms 5_000

  @type answer :: %{receipts: map(), telemetry: :ok | :degraded}

  @spec get(term(), (-> {:ok, map()} | term())) :: answer()
  def get(key, fetch) when is_function(fetch, 0) do
    now = System.monotonic_time(:millisecond)

    case {ttl_ms(), :persistent_term.get({__MODULE__, key}, nil)} do
      {0, _cached} ->
        ask(fetch)

      {_ttl, nil} ->
        fetch |> ask() |> remember(key, now)

      {ttl, %{value: value} = cached} ->
        if expired?(cached, ttl, now), do: refresh(key, fetch, cached, now)
        value
    end
  end

  # A good answer lives the TTL; a degraded one (the store did not answer) only a few seconds.
  defp expired?(%{at: at, value: %{telemetry: :ok}}, ttl, now), do: now - at >= ttl
  defp expired?(%{at: at}, ttl, now), do: now - at >= min(ttl, @degraded_ttl_ms)

  defp remember(value, key, now) do
    :persistent_term.put({__MODULE__, key}, %{at: now, value: value, refreshing_since: nil})
    value
  end

  # One refresh at a time per key, off the read's path.
  defp refresh(key, fetch, cached, now) do
    unless is_integer(cached.refreshing_since) and now - cached.refreshing_since < 10_000 do
      :persistent_term.put({__MODULE__, key}, %{cached | refreshing_since: now})

      Task.start(fn ->
        fetch |> ask() |> remember(key, System.monotonic_time(:millisecond))
      end)
    end

    :ok
  end

  defp ask(fetch) do
    task = Task.async(fetch)

    case Task.yield(task, timeout_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, receipts}} -> %{receipts: receipts, telemetry: :ok}
      _unavailable_or_slow -> %{receipts: %{}, telemetry: :degraded}
    end
  end

  defp ttl_ms, do: Application.get_env(:cadence, :fleet_durable_receipts_ttl_ms, @durable_ttl_ms)

  defp timeout_ms,
    do: Application.get_env(:cadence, :fleet_durable_receipts_timeout_ms, @durable_timeout_ms)
end
