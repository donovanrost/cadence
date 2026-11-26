defmodule Mix.Tasks.Cadence.Scale.Run do
  @moduledoc """
  Records a per-second scorecard of a running Cadence node while a fleet-scale load runs
  (#717, epic #217).

      mix cadence.scale.run --duration 600 --label peak-1000 [--node cadence_3] [--module Mod]

  Connects to the worktree's node (`cadence_<CADENCE_DEV_SLOT>`, cookie `CADENCE_ERLANG_COOKIE`,
  both set by `dev/stack env`), starts `Cadence.Observability.ScaleSampler` there, waits
  `--duration` seconds and stops it. The node writes one JSON line per second to
  `var/scale/<utc>-<label>.jsonl`; this task writes the run summary (p50/p99/max of every
  per-second metric) beside it as `.summary.json` and prints the headline numbers.

  `--module` (repeatable) replaces the watched mailbox modules (default: telemetry's #686 list,
  `ScaleSampler.Mailboxes.default_modules/0`); per module the summary has processes with a
  backlog, sum and max, plus the 5 busiest processes overall. The summary also records the git
  sha, the node's settings (pool size, journal) and per-table Postgres and QuestDB growth.
  The load itself (the fleet seed and the simulator) is started separately.
  """

  use Mix.Task

  alias Cadence.Telemetry.Storage.QuestDB.RestClient

  @shortdoc "Record a per-second scorecard of a running node under load"

  @switches [node: :string, duration: :integer, label: :string, module: :keep, out: :string]

  # Telemetry's #686 list: singletons and per-mission processes on the ingest path.
  @default_modules [
    # The archive writers, one per mission since #733 (FileSystem.Writer is only the front).
    Cadence.Protocol.RecordArchive.FileSystem.Writer.Mission,
    Cadence.Platform.EventBus,
    Cadence.Dashboards.RuntimeFactConsumer,
    Cadence.Dashboards.RuntimeCache,
    Cadence.Runtime.CapabilityRegistry,
    Cadence.Runtime.MissionCoordinator
  ]

  @doc "The mailbox modules watched by default (telemetry's #686 list)."
  def default_modules, do: @default_modules

  @headline [
    "ecto.queue_ms.p99",
    "ecto.query_ms.p99",
    "ingest.frames",
    "ingest.journal_lag_ms.p99",
    "ingest.paths",
    "beam.run_queue",
    "beam.scheduler_utilization",
    "storage.postgres_wal_bytes",
    "storage.questdb_wal_lag.max",
    "host.swap_used_mb",
    "host.agents"
  ]

  @impl true
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: @switches)
    duration = Keyword.get(opts, :duration) || Mix.raise("--duration <seconds> is required")
    if duration < 1, do: Mix.raise("--duration must be positive")

    node = connect!(Keyword.get(opts, :node) || default_node())
    sample(node, opts, fn -> wait(duration) end)
    :ok
  end

  @doc false
  def sample(node, opts, workload) do
    duration = Keyword.fetch!(opts, :duration)
    label = Keyword.get(opts, :label, "run")
    out = Path.expand(Keyword.get(opts, :out) || default_out(label))
    modules = opts |> Keyword.get_values(:module) |> Enum.map(&Module.concat([&1]))

    sampler_opts = [
      out: out,
      # The sampler stops if this task dies, and in any case shortly after the run should end.
      owner: self(),
      max_ms: duration * 1_000 + 120_000,
      modules: if(modules == [], do: @default_modules, else: modules),
      questdb_exec: &RestClient.exec/1
    ]

    case rpc!(node, :start, [sampler_opts]) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        Mix.raise(
          "A scale sampler is already running on #{node}. It stops when its runner exits or at " <>
            "its deadline; wait for it, or stop it with " <>
            "`:rpc.call(:\"#{node}\", Cadence.Observability.ScaleSampler, :stop, [])`."
        )

      {:error, reason} ->
        Mix.raise("Could not start the sampler on #{node}: #{inspect(reason)}")
    end

    Mix.shell().info("Sampling #{node} for #{duration} s into #{out}")

    result =
      try do
        workload.()
      catch
        kind, reason ->
          :rpc.call(node, Cadence.Observability.ScaleSampler, :stop, [], 60_000)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

    {:ok, summary} = rpc!(node, :stop, [])
    {summary, path} = write_summary(summary, out)
    {summary, path, result}
  end

  defp write_summary(summary, out) do
    summary = put_in(summary, [:meta, :git_sha], git_sha())

    summary_path = Path.rootname(out, ".jsonl") <> ".summary.json"
    File.write!(summary_path, Jason.encode_to_iodata!(summary, pretty: true))
    print(summary, summary_path)
    {summary, summary_path}
  end

  defp default_out(label) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    Path.expand("var/scale/#{stamp}-#{label}.jsonl", repo_root())
  end

  defp repo_root, do: Path.expand("../../../../..", __DIR__)

  defp git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: repo_root(), stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _not_a_checkout -> nil
    end
  end

  defp default_node do
    case System.get_env("CADENCE_DEV_SLOT") do
      nil -> "cadence"
      slot -> "cadence_#{slot}"
    end
  end

  @doc false
  def connect!(name) do
    {:ok, host} = :inet.gethostname()
    target = if String.contains?(name, "@"), do: name, else: "#{name}@#{host}"

    unless Node.alive?() do
      case Node.start(:"scale_#{System.pid()}@#{host}", :shortnames) do
        {:ok, _pid} -> :ok
        {:error, reason} -> Mix.raise("Could not start distribution: #{inspect(reason)}")
      end
    end

    case System.get_env("CADENCE_ERLANG_COOKIE") || System.get_env("CADENCE_NODE_COOKIE") do
      nil -> :ok
      cookie -> Node.set_cookie(String.to_atom(cookie))
    end

    use_stack_loopback(name, host)
    target = String.to_atom(target)

    unless Node.connect(target) == true,
      do: Mix.raise("Could not connect to #{target}; is the stack up (dev/stack status)?")

    target
  end

  defp use_stack_loopback(name, host) do
    if System.get_env("CADENCE_DEV_SLOT") != nil and not String.contains?(name, "@") do
      # dev/stack binds distribution to loopback even if DNS resolves this host elsewhere.
      :ok = :inet_db.add_host({127, 0, 0, 1}, [host])
      :ok = :inet_db.set_lookup([:file, :native])
    end
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

  defp print(%{seconds: seconds, metrics: metrics, storage: storage}, path) do
    Mix.shell().info(
      "\n#{seconds} rows sampled. Per-row p50 / p99 / max (counts are per row; a row covers about 1 s only on an idle host):"
    )

    for key <- @headline, stats = metrics[key], stats != nil do
      Mix.shell().info(
        "  #{String.pad_trailing(key, 30)} #{stats.p50} / #{stats.p99} / #{stats.max}"
      )
    end

    for {db, tables} <- storage, {table, delta} <- tables, delta != nil do
      Mix.shell().info("  #{db} #{table}: #{inspect(delta)}")
    end

    Mix.shell().info("Summary: #{path}")
  end
end
