defmodule Cadence.Observability.RepoTracingOverheadTest do
  @moduledoc """
  Repo tracing must cost the same per query whatever the calling process keeps in its process
  dictionary.

  OpentelemetryEcto 1.2.0's query handler looked up the trace context with
  `OpentelemetryProcessPropagator.fetch_ctx(self())`, i.e. `process_info(self(), :dictionary)`: a
  copy of the WHOLE dictionary on every query, and again (plus the caller's) when no context was
  set. A process holding a large memo paid O(dictionary) per query: 77 % of the CPU of a
  configuration apply in domain's profile (11-15). This test fails if per-query cost grows with
  the dictionary again.

  Set CADENCE_BENCH_PRINT=1 to print the medians.
  """
  use Cadence.DataCase, async: false

  @queries 200
  @payload_key {__MODULE__, :payload}

  test "per-query repo cost does not grow with the process dictionary" do
    warm_up()
    empty = median_query_us()

    # ~100k map entries of small terms: copying them is what a dictionary scan pays for.
    Process.put(@payload_key, Map.new(1..100_000, &{&1, {&1, &1}}))

    try do
      large = median_query_us()

      if System.get_env("CADENCE_BENCH_PRINT"),
        do: IO.puts("repo query median: #{empty} µs (empty dictionary), #{large} µs (large)")

      assert large <= empty * 3 + 200,
             "median per query #{large} µs with a ~100k-entry process dictionary vs #{empty} µs " <>
               "without: repo tracing scales with the process dictionary"
    after
      Process.delete(@payload_key)
    end
  end

  defp warm_up, do: for(_ <- 1..20, do: Repo.query!("SELECT 1"))

  defp median_query_us do
    1..@queries
    |> Enum.map(fn _ -> elem(:timer.tc(fn -> Repo.query!("SELECT 1") end), 0) end)
    |> Enum.sort()
    |> Enum.at(div(@queries, 2))
  end
end
