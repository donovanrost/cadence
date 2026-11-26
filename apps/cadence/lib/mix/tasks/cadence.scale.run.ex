defmodule Mix.Tasks.Cadence.Scale.Run do
  @moduledoc """
  Records a per-second scorecard of a running Cadence node while a fleet-scale load runs
  (#717, epic #217).

      mix cadence.scale.run --duration 600 --label peak-1000 [--node cadence_3] [--process Name]

  Connects to the worktree's node (`cadence_<CADENCE_DEV_SLOT>`, cookie `CADENCE_ERLANG_COOKIE`,
  both set by `dev/stack env`), starts `Cadence.Observability.ScaleSampler` there, waits
  `--duration` seconds and stops it. The node writes one JSON line per second to
  `var/scale/<utc>-<label>.jsonl`; this task writes the run summary (p50/p99/max of every
  per-second metric) beside it as `.summary.json` and prints the headline numbers.

  `--process` (repeatable) names registered processes whose mailbox lengths are recorded each
  second, e.g. `--process Cadence.RecordArchive.FileSystem.Writer`. The top 5 mailboxes are
  always recorded. The load itself (the fleet seed and the simulator) is started separately.
  """

  use Mix.Task

  @shortdoc "Record a per-second scorecard of a running node under load"

  @switches [node: :string, duration: :integer, label: :string, process: :keep, out: :string]

  @headline [
    "ecto.queue_ms.p99",
    "ecto.query_ms.p99",
    "ingest.frames",
    "ingest.journal_lag_ms.p99",
    "ingest.paths",
    "beam.run_queue",
    "beam.scheduler_utilization",
    "postgres.wal_bytes"
  ]

  @impl true
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: @switches)
    duration = Keyword.get(opts, :duration) || Mix.raise("--duration <seconds> is required")
    label = Keyword.get(opts, :label, "run")
    out = Keyword.get(opts, :out) || default_out(label)
    processes = opts |> Keyword.get_values(:process) |> Enum.map(&Module.concat([&1]))
    node = connect!(Keyword.get(opts, :node) || default_node())

    {:ok, _pid} = rpc!(node, :start, [[out: out, processes: processes]])
    Mix.shell().info("Sampling #{node} for #{duration} s into #{out}")
    wait(duration)
    {:ok, summary} = rpc!(node, :stop, [])

    summary_path = String.replace_suffix(out, ".jsonl", ".summary.json")
    File.write!(summary_path, Jason.encode_to_iodata!(summary, pretty: true))
    print(summary, summary_path)
  end

  defp default_out(label) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    Path.expand("var/scale/#{stamp}-#{label}.jsonl", repo_root())
  end

  defp repo_root, do: Path.expand("../../../../..", __DIR__)

  defp default_node do
    case System.get_env("CADENCE_DEV_SLOT") do
      nil -> "cadence"
      slot -> "cadence_#{slot}"
    end
  end

  defp connect!(name) do
    {:ok, host} = :inet.gethostname()
    target = if String.contains?(name, "@"), do: name, else: "#{name}@#{host}"

    case Node.start(:"scale_#{System.unique_integer([:positive])}@#{host}", :shortnames) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Could not start distribution: #{inspect(reason)}")
    end

    case System.get_env("CADENCE_ERLANG_COOKIE") || System.get_env("CADENCE_NODE_COOKIE") do
      nil -> :ok
      cookie -> Node.set_cookie(String.to_atom(cookie))
    end

    target = String.to_atom(target)

    unless Node.connect(target) == true,
      do: Mix.raise("Could not connect to #{target}; is the stack up (dev/stack status)?")

    target
  end

  defp rpc!(node, function, args) do
    case :rpc.call(node, Cadence.Observability.ScaleSampler, function, args, 60_000) do
      {:badrpc, reason} ->
        Mix.raise("ScaleSampler.#{function} failed on #{node}: #{inspect(reason)}")

      result ->
        result
    end
  end

  defp wait(seconds) do
    Enum.each(1..seconds, fn second ->
      Process.sleep(1_000)
      if rem(second, 60) == 0, do: Mix.shell().info("  #{second}/#{seconds} s")
    end)
  end

  defp print(%{seconds: seconds, metrics: metrics}, path) do
    Mix.shell().info("\n#{seconds} s sampled. Per-second p50 / p99 / max:")

    for key <- @headline, stats = metrics[key], stats != nil do
      Mix.shell().info(
        "  #{String.pad_trailing(key, 30)} #{stats.p50} / #{stats.p99} / #{stats.max}"
      )
    end

    Mix.shell().info("Summary: #{path}")
  end
end
