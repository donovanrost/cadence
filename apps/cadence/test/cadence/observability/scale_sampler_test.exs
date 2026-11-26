defmodule Cadence.Observability.ScaleSamplerTest do
  use ExUnit.Case, async: false

  alias Cadence.Observability.ScaleSampler
  alias Cadence.Observability.ScaleSampler.Stats

  describe "Stats" do
    test "distribution is nearest-rank p50/p99/max, nil when empty" do
      assert Stats.distribution([]) == %{p50: nil, p99: nil, max: nil}
      assert Stats.distribution(Enum.to_list(1..100)) == %{p50: 50, p99: 99, max: 100}
      assert %{p50: 2.5, max: 2.5} = Stats.distribution([2.5])
    end

    test "summarize takes every numeric leaf across seconds and skips the rest" do
      rows = [
        %{t: "a", ingest: %{frames: 10, duration_us: %{p99: 5, max: nil}}},
        %{t: "b", ingest: %{frames: 30, duration_us: %{p99: 7, max: nil}}}
      ]

      assert %{seconds: 2, metrics: metrics} = Stats.summarize(rows)
      assert metrics["ingest.frames"] == %{p50: 10, p99: 30, max: 30}
      assert metrics["ingest.duration_us.p99"] == %{p50: 5, p99: 7, max: 7}
      refute Map.has_key?(metrics, "t")
      refute Map.has_key?(metrics, "ingest.duration_us.max")
    end
  end

  describe "sampling" do
    setup do
      out = Path.join(System.tmp_dir!(), "scale-#{System.unique_integer([:positive])}.jsonl")
      on_exit(fn -> File.rm(out) end)
      %{out: out}
    end

    test "aggregates ingest events per second, omitting missing measurements", %{out: out} do
      {:ok, _pid} = ScaleSampler.start(out: out, interval_ms: 60_000, postgres: false)

      batch = [:cadence, :ingest, :batch, :stop]
      meta = %{path_id: "path-1", mission_id: "m"}
      :telemetry.execute(batch, %{entries: 2, frames: 4, bytes: 100, duration_us: 30}, meta)

      :telemetry.execute(batch, %{entries: 1, frames: 2, bytes: 50, duration_us: 10}, %{
        path_id: "path-2"
      })

      # A batch acknowledged after a restart omits its measurements (#686): counted, not zeroed.
      :telemetry.execute(batch, %{}, meta)
      :telemetry.execute([:cadence, :ingest, :journal, :backlog], %{bytes: 900}, meta)

      assert {:ok, %{seconds: 1, metrics: metrics}} = ScaleSampler.stop()
      assert metrics["ingest.batches"].max == 3
      assert metrics["ingest.frames"].max == 6
      assert metrics["ingest.bytes"].max == 150
      assert metrics["ingest.paths"].max == 2
      assert metrics["ingest.duration_us.max"].max == 30
      assert metrics["ingest.backlog_bytes_max"].max == 900
      assert metrics["beam.processes"].max > 0

      [line] = out |> File.read!() |> String.split("\n", trim: true)
      assert %{"ingest" => %{"frames" => 6}, "mailboxes" => %{"top" => _}} = Jason.decode!(line)
    end

    test "detaches its handlers when stopped", %{out: out} do
      {:ok, _pid} = ScaleSampler.start(out: out, interval_ms: 60_000, postgres: false)
      {:ok, _summary} = ScaleSampler.stop()

      handlers = :telemetry.list_handlers([:cadence, :ingest, :batch, :stop])
      refute Enum.any?(handlers, &String.starts_with?(&1.id, "cadence-scale-sampler-"))
    end
  end
end
