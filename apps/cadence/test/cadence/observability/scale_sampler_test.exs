defmodule Cadence.Observability.ScaleSamplerTest do
  use ExUnit.Case, async: false

  alias Cadence.Observability.ScaleSampler
  alias Cadence.Observability.ScaleSampler.Stats
  alias Mix.Tasks.Cadence.Scale.Run

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

  defmodule Slow do
    @moduledoc false
    use GenServer
    @impl true
    def init(state), do: {:ok, state}
    @impl true
    def handle_info(:block, state) do
      Process.sleep(500)
      {:noreply, state}
    end

    def handle_info(_message, state), do: {:noreply, state}
  end

  describe "Mailboxes" do
    test "groups backlogged processes by module: count, sum and max" do
      {:ok, a} = GenServer.start(Slow, nil)
      {:ok, b} = GenServer.start(Slow, nil)
      for pid <- [a, b], do: send(pid, :block)
      for _ <- 1..3, do: send(a, :queued)
      send(b, :queued)
      Process.sleep(20)

      %{by_module: by_module, top: top} = ScaleSampler.Mailboxes.sample([Slow], 3)
      assert %{processes: 2, sum: 4, max: 3} = by_module[inspect(Slow)]
      assert [%{len: 3, module: module} | _] = top
      assert module == inspect(Slow)
    end

    test "QuestDB probes use the given exec; nil when it fails" do
      exec = fn
        "select sequencerTxn" <> _ -> {:ok, %{"dataset" => [[3, false], [1, true]]}}
        "select sum(diskSize)" <> _ -> {:ok, %{"dataset" => [[2048, 10]]}}
      end

      assert ScaleSampler.Storage.questdb_wal_lag(exec) == %{sum: 4, max: 3, suspended: 1}

      assert ScaleSampler.Storage.questdb_tables(exec, ["t"]) == %{
               "t" => %{bytes: 2048, rows: 10}
             }

      assert ScaleSampler.Storage.questdb_wal_lag(fn _sql -> {:error, :down} end) == nil
    end

    test "a QuestDB that hangs answers nil within the bound, not after its retries" do
      slow = fn _sql ->
        Process.sleep(5_000)
        {:ok, %{"dataset" => []}}
      end

      {us, result} = :timer.tc(fn -> ScaleSampler.Storage.questdb_wal_lag(slow) end)
      assert result == nil
      assert us < 1_500_000
    end

    test "Storage.deltas subtracts start from end, nil where a side is missing" do
      start = %{"a" => %{rows: 10, bytes: 100}, "b" => nil}
      finish = %{"a" => %{rows: 15, bytes: 160}, "b" => %{rows: 1, bytes: 1}}

      assert ScaleSampler.Storage.deltas(start, finish) == %{
               "a" => %{rows: 5, bytes: 60},
               "b" => nil
             }
    end
  end

  describe "Host" do
    alias Cadence.Observability.ScaleSampler.Host

    test "parses macOS and Linux load and swap, and counts agents" do
      assert Host.parse_load("{ 6.35 12.87 21.90 }") == [6.35, 12.87, 21.9]
      assert Host.parse_load("0.52 0.58 0.59 1/389 12345\n") == [0.52, 0.58, 0.59]
      assert Host.parse_macos_swap("total = 9216.00M  used = 8028.50M  free = 1187.50M") == 8028.5
      assert Host.parse_macos_swap("total = 2.00G  used = 1.50G  free = 0.50G") == 1536.0
      assert Host.parse_linux_swap("SwapTotal:  2097152 kB\nSwapFree:   1048576 kB\n") == 1024.0

      ps = """
      /Users/x/.local/bin/claude --model opus
      node /Users/x/.local/share/mise/installs/node/26/bin/codex.js -s workspace-write
      codex
      /usr/bin/vim claude-notes.md
      """

      assert Host.count_agents(ps) == 3
    end
  end

  describe "the runner's defaults" do
    test "every default mailbox module exists and runs as a process" do
      for module <- Run.default_modules() do
        assert Code.ensure_loaded?(module), "#{inspect(module)} doesn't exist"
        assert function_exported?(module, :init, 1), "#{inspect(module)} isn't a process module"
      end
    end
  end

  describe "lifetime" do
    setup do
      out = Path.join(System.tmp_dir!(), "scale-#{System.unique_integer([:positive])}.jsonl")
      on_exit(fn -> File.rm(out) end)
      %{out: out}
    end

    test "stops when its runner goes down", %{out: out} do
      owner = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, pid} = ScaleSampler.start(out: out, max_ms: 60_000, postgres: false, owner: owner)
      ref = Process.monitor(pid)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end

    test "stops at its deadline", %{out: out} do
      {:ok, pid} = ScaleSampler.start(out: out, max_ms: 50, postgres: false)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end

    test "a second start while one runs is refused, not a crash", %{out: out} do
      {:ok, pid} = ScaleSampler.start(out: out, max_ms: 60_000, postgres: false)

      assert {:error, {:already_started, ^pid}} =
               ScaleSampler.start(out: out <> ".2", max_ms: 60_000, postgres: false)

      {:ok, _summary} = ScaleSampler.stop()
    end
  end

  describe "sampling" do
    setup do
      out = Path.join(System.tmp_dir!(), "scale-#{System.unique_integer([:positive])}.jsonl")
      on_exit(fn -> File.rm(out) end)
      %{out: out}
    end

    test "aggregates ingest events per second, omitting missing measurements", %{out: out} do
      {:ok, _pid} =
        ScaleSampler.start(
          out: out,
          interval_ms: 60_000,
          max_ms: 60_000,
          postgres: false,
          modules: [Slow]
        )

      batch = [:cadence, :ingest, :batch, :stop]
      meta = %{path_id: "path-1", mission_id: "m"}
      :telemetry.execute(batch, %{entries: 2, frames: 4, bytes: 100, duration_us: 30}, meta)

      :telemetry.execute(batch, %{entries: 1, frames: 2, bytes: 50, duration_us: 10}, %{
        path_id: "path-2"
      })

      # A batch acknowledged after a restart omits its measurements (#686): counted, not zeroed.
      :telemetry.execute(batch, %{}, meta)
      :telemetry.execute([:cadence, :ingest, :journal, :backlog], %{bytes: 900}, meta)

      assert {:ok, %{seconds: 1, metrics: metrics, meta: meta, storage: storage}} =
               ScaleSampler.stop()

      assert %{node: _, otp: _, schedulers: _} = meta
      assert storage == %{postgres: %{}, questdb: %{}}
      assert metrics["ingest.batches"].max == 3
      assert metrics["ingest.frames"].max == 6
      assert metrics["ingest.bytes"].max == 150
      assert metrics["ingest.paths"].max == 2
      assert metrics["ingest.duration_us.max"].max == 30
      assert metrics["ingest.backlog_bytes_max"].max == 900
      assert metrics["beam.processes"].max > 0

      [line] = out |> File.read!() |> String.split("\n", trim: true)

      assert %{
               "ingest" => %{"frames" => 6},
               "mailboxes" => %{"top" => _, "by_module" => by_module}
             } =
               Jason.decode!(line)

      assert Map.has_key?(by_module, inspect(Slow))
    end

    test "detaches its handlers when stopped", %{out: out} do
      {:ok, _pid} =
        ScaleSampler.start(
          out: out,
          interval_ms: 60_000,
          max_ms: 60_000,
          postgres: false,
          modules: [Slow]
        )

      {:ok, _summary} = ScaleSampler.stop()

      handlers = :telemetry.list_handlers([:cadence, :ingest, :batch, :stop])
      refute Enum.any?(handlers, &String.starts_with?(&1.id, "cadence-scale-sampler-"))
    end
  end
end
