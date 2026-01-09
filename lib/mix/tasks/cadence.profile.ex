defmodule Mix.Tasks.Cadence.Profile do
  @moduledoc """
  Profiles a running Cadence instance to identify telemetry pipeline bottlenecks.

  This task connects to a running Cadence node and collects performance metrics
  from the telemetry pipeline.

  ## Usage

      # Start the server with a node name first:
      iex --sname cadence -S mix phx.server

      # Then run the profiler in another terminal:
      mix cadence.profile --node cadence --mission-id <uuid>

  ## Options

    * `--node`, `-n` - Name of the running Cadence node (required)
    * `--mission-id`, `-m` - Mission UUID to profile (required)
    * `--duration`, `-d` - Duration in seconds (default: 10)
    * `--interval`, `-i` - Sampling interval in ms (default: 1000)
    * `--queues` - Only show process queue depths
    * `--snapshot` - Single snapshot instead of continuous watch
    * `--analyze` - Show timing analysis (warmup, spikes, trimmed avg)
    * `--debug` - Run diagnostics to debug profiler issues

  ## Examples

      # Watch for 10 seconds with 1-second samples
      mix cadence.profile -n cadence -m a1b2c3d4-...

      # Watch for 30 seconds with 500ms samples
      mix cadence.profile -n cadence -m a1b2c3d4-... -d 30 -i 500

      # Single snapshot
      mix cadence.profile -n cadence -m a1b2c3d4-... --snapshot

      # Just check queue depths
      mix cadence.profile -n cadence -m a1b2c3d4-... --queues
  """

  use Mix.Task

  @shortdoc "Profile a running Cadence telemetry pipeline"

  @default_duration 10
  @default_interval 1000

  @impl Mix.Task
  def run(args) do
    {opts, _remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          node: :string,
          mission_id: :string,
          duration: :integer,
          interval: :integer,
          queues: :boolean,
          snapshot: :boolean,
          analyze: :boolean,
          debug: :boolean,
          help: :boolean
        ],
        aliases: [
          n: :node,
          m: :mission_id,
          d: :duration,
          i: :interval,
          h: :help
        ]
      )

    if opts[:help] || invalid != [] do
      print_help()
      if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")
      System.halt(0)
    end

    # Validate required options
    node_name = validate_node!(opts)
    mission_id = validate_mission_id!(opts)

    # Parse optional config
    config = %{
      node: node_name,
      mission_id: mission_id,
      duration: opts[:duration] || @default_duration,
      interval: opts[:interval] || @default_interval,
      mode: determine_mode(opts)
    }

    # Start distribution on this node
    start_distribution()

    # Connect to target node
    connect_to_node(config.node)

    # Run profiler
    run_profiler(config)
  end

  defp validate_node!(opts) do
    case opts[:node] do
      nil ->
        Mix.raise("Missing required option: --node")

      name ->
        # Append hostname if not already present
        name_str = to_string(name)

        if String.contains?(name_str, "@") do
          String.to_atom(name_str)
        else
          hostname = get_hostname()
          String.to_atom("#{name_str}@#{hostname}")
        end
    end
  end

  defp validate_mission_id!(opts) do
    case opts[:mission_id] do
      nil ->
        Mix.raise("Missing required option: --mission-id")

      id ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> Mix.raise("Invalid mission ID format. Expected UUID, got: #{id}")
        end
    end
  end

  defp determine_mode(opts) do
    cond do
      opts[:debug] -> :debug
      opts[:analyze] -> :analyze
      opts[:snapshot] -> :snapshot
      opts[:queues] -> :queues
      true -> :watch
    end
  end

  defp get_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp start_distribution do
    hostname = get_hostname()
    node_name = :"profiler_#{:rand.uniform(10000)}@#{hostname}"

    case Node.start(node_name, :shortnames) do
      {:ok, _} ->
        Mix.shell().info("Started profiler node: #{node_name}")

      {:error, reason} ->
        Mix.raise("Failed to start distributed node: #{inspect(reason)}")
    end

    # Set cookie to default (assumes same cookie as target)
    # In production, you'd want to configure this
    Node.set_cookie(:cadence)
  end

  defp connect_to_node(target_node) do
    Mix.shell().info("Connecting to #{target_node}...")

    case Node.connect(target_node) do
      true ->
        Mix.shell().info("Connected successfully.\n")

      false ->
        Mix.raise("""
        Failed to connect to #{target_node}.

        Make sure:
        1. The server is running with: iex --sname cadence -S mix phx.server
        2. Both nodes are using the same cookie (default: :cadence)
        3. The node name is correct
        """)

      :ignored ->
        Mix.raise("Local node is not alive. This shouldn't happen.")
    end
  end

  defp run_profiler(config) do
    case config.mode do
      :debug ->
        run_debug(config)

      :analyze ->
        run_analyze(config)

      :snapshot ->
        run_snapshot(config)

      :queues ->
        run_queues(config)

      :watch ->
        run_watch(config)
    end
  end

  defp run_debug(config) do
    Mix.shell().info("Running diagnostics for mission #{config.mission_id}...\n")

    case rpc_call(config.node, Cadence.Telemetry.Profiler, :debug, [config.mission_id]) do
      {:badrpc, reason} ->
        Mix.raise("RPC failed: #{inspect(reason)}")

      :ok ->
        :ok
    end
  end

  defp run_analyze(config) do
    print_analysis_header(config.mission_id)

    case rpc_call(config.node, Cadence.Telemetry.Stats, :get_all_timing_analysis, [
           config.mission_id
         ]) do
      {:badrpc, reason} ->
        Mix.raise("RPC failed: #{inspect(reason)}")

      analysis when is_map(analysis) ->
        print_analysis(analysis)
        print_analysis_legend()

      other ->
        Mix.shell().error("Unexpected result: #{inspect(other)}")
    end
  end

  defp print_analysis_header(mission_id) do
    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║           Timing Analysis: Warmup & Spike Detection           ║
    ╚═══════════════════════════════════════════════════════════════╝

    Mission: #{mission_id}
    """)
  end

  defp print_analysis(analysis) do
    stages_to_show = [:identify, :decom, :convert, :derive, :end_to_end]
    Enum.each(stages_to_show, &maybe_print_stage_analysis(&1, analysis))
  end

  defp maybe_print_stage_analysis(stage, analysis) do
    case Map.get(analysis, stage) do
      %{sample_count: count} = data when count > 0 ->
        print_stage_analysis(stage, data)

      _ ->
        :ok
    end
  end

  defp print_analysis_legend do
    Mix.shell().info("""
    ═══════════════════════════════════════════════════════════════
                              Legend
    ═══════════════════════════════════════════════════════════════
      avg       - Standard average (affected by outliers)
      trimmed   - Average excluding top/bottom 5%
      median    - Middle value (P50)
      warmup    - First 10 samples (may be slow due to JIT/cache)
      spikes    - Samples > 3σ from mean (likely GC pauses)
    """)
  end

  defp print_stage_analysis(stage, data) do
    stage_name = stage |> to_string() |> String.upcase()

    Mix.shell().info("#{stage_name} (#{data.sample_count} samples)")

    Mix.shell().info(
      "  Averages:  avg=#{format_us(data.avg_us)}  trimmed=#{format_us(data.trimmed_avg_us)}  median=#{format_us(data.median_us)}"
    )

    print_warmup_analysis(data)
    print_spike_analysis(data)
    print_outlier_analysis(data)

    Mix.shell().info("")
  end

  defp print_warmup_analysis(%{warmup_samples: warmup_samples} = data)
       when length(warmup_samples) > 0 do
    warmup_str = Enum.map_join(warmup_samples, ", ", &format_us_compact/1)
    Mix.shell().info("  Warmup:    [#{warmup_str}]  avg=#{format_us(data.warmup_avg_us)}")
    print_first_warmup_warning(warmup_samples, data)
    print_warmup_avg_warning(data)
  end

  defp print_warmup_analysis(_data), do: :ok

  defp print_first_warmup_warning(warmup_samples, data) do
    first = List.first(warmup_samples)

    if first && data.avg_us > 0 && first > data.avg_us * 2 do
      Mix.shell().info(
        "  ⚠️  First packet (#{format_us(first)}) is #{Float.round(first / data.avg_us, 1)}x slower than avg"
      )
    end
  end

  defp print_warmup_avg_warning(data) do
    if data.trimmed_avg_us > 0 && data.warmup_avg_us > data.trimmed_avg_us * 1.5 do
      Mix.shell().info(
        "  ⚠️  Warmup period #{Float.round(data.warmup_avg_us / data.trimmed_avg_us, 1)}x slower than steady state"
      )
    end
  end

  defp print_spike_analysis(data) do
    if data.spike_count > 0 do
      spike_pct = Float.round(data.spike_count / data.sample_count * 100, 2)

      Mix.shell().info(
        "  Spikes:    #{data.spike_count} samples (#{spike_pct}%) > #{format_us(data.spike_threshold_us)}"
      )
    end
  end

  defp print_outlier_analysis(data) do
    if data.trimmed_avg_us > 0 &&
         abs(data.avg_us - data.trimmed_avg_us) > data.trimmed_avg_us * 0.1 do
      diff_pct = Float.round((data.avg_us - data.trimmed_avg_us) / data.trimmed_avg_us * 100, 1)

      Mix.shell().info(
        "  📊 Outliers inflate avg by #{diff_pct}% (use trimmed for accurate measurement)"
      )
    end
  end

  defp format_us_compact(us) when is_number(us) do
    if us >= 1000, do: "#{Float.round(us / 1000, 1)}ms", else: "#{round(us)}μs"
  end

  defp format_us_compact(_), do: "-"

  defp run_snapshot(config) do
    Mix.shell().info("Taking snapshot for mission #{config.mission_id}...\n")

    case rpc_call(config.node, Cadence.Telemetry.Profiler, :snapshot, [config.mission_id]) do
      {:badrpc, reason} ->
        Mix.raise("RPC failed: #{inspect(reason)}")

      snapshot ->
        print_snapshot(snapshot, nil)
    end
  end

  defp run_queues(config) do
    Mix.shell().info("Checking process queues for mission #{config.mission_id}...\n")

    case rpc_call(config.node, Cadence.Telemetry.Profiler, :check_queues, [config.mission_id]) do
      {:badrpc, reason} ->
        Mix.raise("RPC failed: #{inspect(reason)}")

      queues ->
        print_queues(queues)
    end
  end

  defp run_watch(config) do
    iterations = div(config.duration * 1000, config.interval)

    Mix.shell().info("""
    ╔═══════════════════════════════════════════════════════════════╗
    ║             Cadence Telemetry Profiler                        ║
    ╚═══════════════════════════════════════════════════════════════╝

    Mission:    #{config.mission_id}
    Duration:   #{config.duration} seconds
    Interval:   #{config.interval}ms
    Samples:    #{iterations}

    ───────────────────────────────────────────────────────────────
    """)

    # Get initial snapshot
    initial = get_snapshot(config)
    print_snapshot(initial, nil)

    # Run sample loop
    final =
      Enum.reduce(1..iterations, initial, fn i, prev ->
        Process.sleep(config.interval)
        current = get_snapshot(config)
        print_snapshot(current, prev)

        if i == iterations do
          print_summary(initial, current, config.duration * 1000)
        end

        current
      end)

    final
  end

  defp get_snapshot(config) do
    case rpc_call(config.node, Cadence.Telemetry.Profiler, :snapshot, [config.mission_id]) do
      {:badrpc, reason} ->
        Mix.shell().error("RPC failed: #{inspect(reason)}")
        %{error: reason}

      snapshot ->
        snapshot
    end
  end

  defp rpc_call(node, module, function, args) do
    :rpc.call(node, module, function, args, 5000)
  end

  defp print_snapshot(snapshot, prev) do
    timestamp = Map.get(snapshot, :timestamp, DateTime.utc_now())
    Mix.shell().info("--- #{Calendar.strftime(timestamp, "%H:%M:%S")} ---")

    print_cvt_stats(snapshot[:cvt])
    print_stats_snapshot(snapshot, prev)
    print_pipeline_v2_snapshot(snapshot[:pipeline_v2])
    print_lanes_snapshot(snapshot[:lanes])
    print_queue_warnings(snapshot[:process_queues] || [])

    Mix.shell().info("")
  end

  defp print_cvt_stats(%{total_entries: entries, memory_bytes: bytes}) do
    Mix.shell().info("CVT: #{entries} entries, #{div(bytes, 1024)} KB")
  end

  defp print_cvt_stats(%{error: e}) do
    Mix.shell().info("CVT: error - #{inspect(e)}")
  end

  defp print_cvt_stats(other) do
    Mix.shell().info("CVT: #{inspect(other)}")
  end

  defp print_lanes_snapshot(%{error: :not_found}), do: :ok

  defp print_lanes_snapshot(
         %{router_queue: router_q, shard_count: shard_count, shards: shards} = lanes
       ) do
    mailbox = Map.get(lanes, :router_mailbox, 0)
    worker_count = Map.get(lanes, :worker_count, shard_count)
    workers = Map.get(lanes, :workers, [])

    mailbox_info = if mailbox > 0, do: ", mailbox=#{mailbox}", else: ""
    worker_info = "workers=#{worker_count}/#{shard_count}"
    Mix.shell().info("Lanes: router_q=#{router_q}#{mailbox_info}, #{worker_info}")

    # Show per-shard stats with worker info
    shards
    |> Enum.take(5)
    |> Enum.each(fn %{shard: shard, counters: counters} ->
      recv = Map.get(counters, :packets_received, 0)
      proc = Map.get(counters, :packets_processed, 0)
      drop = Map.get(counters, :packets_dropped, 0)

      worker = Enum.find(workers, fn w -> w.shard == shard end)
      {pid_str, worker_status} = format_worker_info(worker)

      Mix.shell().info("  shard #{shard} #{pid_str}: recv=#{recv} proc=#{proc} drop=#{drop}#{worker_status}")
    end)
  end

  defp print_lanes_snapshot(_), do: :ok

  defp format_worker_info(nil), do: {"(?)", ""}
  defp format_worker_info(%{alive?: false}), do: {"(DEAD)", ""}

  defp format_worker_info(%{alive?: true, pid: pid, queue_len: q, memory_kb: mem, status: status}) do
    pid_str = "(#{format_pid(pid)})"

    status_icon =
      case status do
        :running -> ""
        :waiting -> ""
        :suspended -> " [SUSP]"
        other -> " [#{other}]"
      end

    worker_status =
      cond do
        q > 0 -> " | #{mem}KB q=#{q}#{status_icon}"
        true -> "#{status_icon}"
      end

    {pid_str, worker_status}
  end

  defp format_pid(pid) when is_pid(pid) do
    pid
    |> :erlang.pid_to_list()
    |> to_string()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
  end

  defp format_pid(_), do: "?"

  defp print_stats_snapshot(
         %{
           stats:
             %{packets_received: _recv, packets_processed: proc, items_processed: items} = stats
         } =
           snapshot,
         prev
       ) do
    # V1 uses packets_failed, V2 uses packets_dropped
    failed = Map.get(stats, :packets_failed) || Map.get(stats, :packets_dropped, 0)
    delta = stats_delta(prev, proc)

    Mix.shell().info("Packets: #{proc} processed#{delta}, #{failed} dropped")
    Mix.shell().info("Items: #{items} processed")

    print_stats_throughput(stats)
    print_stats_timing(stats, snapshot[:percentiles])
    print_stage_errors_snapshot(snapshot[:stage_errors])
  end

  defp print_stats_snapshot(%{stats: %{error: e}}, _prev) do
    Mix.shell().info("Stats: error - #{inspect(e)}")
  end

  defp print_stats_snapshot(%{stats: other}, _prev) do
    Mix.shell().info("Stats: #{inspect(other)}")
  end

  defp print_stats_snapshot(_snapshot, _prev), do: :ok

  defp stats_delta(%{stats: %{packets_processed: prev_proc}}, proc) do
    " (+#{proc - prev_proc}/s)"
  end

  defp stats_delta(_prev, _proc), do: ""

  defp print_stats_throughput(%{packets_per_sec: pps, bytes_per_sec: bps}) when bps > 0 do
    mbps = Float.round(bps * 8 / 1_000_000, 1)
    mb_per_sec = Float.round(bps / 1_000_000, 2)

    Mix.shell().info(
      "Throughput: #{format_number(round(pps))} packets/sec, #{mb_per_sec} MB/sec (#{mbps} Mbps)"
    )
  end

  defp print_stats_throughput(%{packets_per_sec: pps}) when pps > 0 do
    Mix.shell().info("Throughput: #{format_number(round(pps))} packets/sec")
  end

  defp print_stats_throughput(_stats), do: :ok

  defp print_stats_timing(%{timing: timing}, percentiles)
       when is_map(timing) and map_size(timing) > 0 do
    print_timing(timing, percentiles)
  end

  defp print_stats_timing(_stats, _percentiles), do: :ok

  defp print_stage_errors_snapshot(errors) when is_map(errors) and map_size(errors) > 0 do
    print_stage_errors(errors)
  end

  defp print_stage_errors_snapshot(_errors), do: :ok

  defp print_pipeline_v2_snapshot(%{error: :not_found}), do: :ok

  defp print_pipeline_v2_snapshot(
         %{
           router_queue: router_queue,
           partition_count: partition_count
         } = v2
       ) do
    router_q = if is_integer(router_queue), do: router_queue, else: 0
    Mix.shell().info("V2 Pipeline: #{partition_count} partitions, router queue: #{router_q}")

    stage_errors = Map.get(v2, :stage_errors, 0)
    dropped = Map.get(v2, :packets_dropped, 0)

    if stage_errors > 0 or dropped > 0 do
      Mix.shell().info("V2 Errors: #{stage_errors} stage errors, #{dropped} dropped")
    end

    partitions = Map.get(v2, :partitions, %{})
    backed_up_stages = find_backed_up_v2_stages(partitions)

    if length(backed_up_stages) > 0 do
      Mix.shell().info("⚠️  V2 backed up stages:")

      Enum.each(backed_up_stages, fn {partition, stage, queue_len} ->
        Mix.shell().info("   p#{partition}:#{stage}: #{queue_len} messages")
      end)
    end
  end

  defp print_pipeline_v2_snapshot(_snapshot), do: :ok

  defp print_queue_warnings(queues) do
    backed_up =
      queues
      |> Enum.filter(fn q -> is_map(q) && Map.get(q, :queue_len, 0) > 10 end)

    if length(backed_up) > 0 do
      Mix.shell().info("⚠️  Backed up processes:")

      Enum.each(backed_up, fn q ->
        Mix.shell().info("   #{q.name}: #{q.queue_len} messages")
      end)
    end
  end

  defp find_backed_up_v2_stages(partitions) do
    partitions
    |> Enum.flat_map(fn {partition, stages} ->
      stages
      |> Enum.filter(fn {_stage, stats} ->
        is_map(stats) && Map.get(stats, :queue_len, 0) > 10
      end)
      |> Enum.map(fn {stage, stats} ->
        {partition, stage, stats.queue_len}
      end)
    end)
    |> Enum.sort_by(fn {_, _, q} -> -q end)
  end

  defp print_queues(queues) do
    if Enum.empty?(queues) do
      Mix.shell().info("No mission processes found.")
    else
      Mix.shell().info("Process Queue Depths:\n")

      Enum.each(queues, &print_queue_entry/1)
    end
  end

  defp print_queue_entry(q) do
    status = queue_status(q.queue_len)

    Mix.shell().info(
      "  #{status} #{q.name}: #{q.queue_len} msgs, #{q.memory_kb} KB, #{format_reductions(q.reductions)} reductions"
    )
  end

  defp queue_status(queue_len) do
    cond do
      queue_len > 100 -> "🔴"
      queue_len > 10 -> "🟡"
      queue_len > 0 -> "🟢"
      true -> "⚪"
    end
  end

  defp format_reductions(r) when r >= 1_000_000, do: "#{Float.round(r / 1_000_000, 1)}M"
  defp format_reductions(r) when r >= 1_000, do: "#{Float.round(r / 1_000, 1)}K"
  defp format_reductions(r), do: "#{r}"

  defp print_timing(timing, percentiles) do
    if timing_has_data?(timing) do
      format = timing_format(timing)
      print_timing_header(format, percentiles)

      Enum.each(all_timing_stages(), fn stage ->
        print_stage_timing(stage, timing, percentiles, format)
      end)
    end
  end

  defp timing_has_data?(timing) do
    Enum.any?(timing, fn {_stage, data} ->
      is_map(data) && Map.get(data, :count, 0) > 0
    end)
  end

  defp timing_format(timing) do
    first_stage_data = timing |> Map.values() |> List.first()
    if first_stage_data && Map.has_key?(first_stage_data, :min_us), do: :v1, else: :v2
  end

  defp print_timing_header(:v1, percentiles) do
    if percentiles && is_map(percentiles) do
      Mix.shell().info("Timing (μs):      avg   /  min  /  max  |  P50  /  P95  /  P99")
    else
      Mix.shell().info("Timing (μs):  avg / min / max")
    end
  end

  defp print_timing_header(:v2, _percentiles) do
    Mix.shell().info("")
    Mix.shell().info("Timing (μs):          avg   /  samples")
  end

  defp all_timing_stages do
    [
      # V1 Broadway stages
      :identify,
      :decommutate,
      :convert,
      :derive,
      # V2 GenStage stages (decom is shorter name for decommutation)
      :decom,
      # Limits evaluation
      :limits,
      # Shared stages
      :cvt_batch,
      :ets_write,
      :pubsub_broadcast,
      :total_process,
      # End-to-end latency
      :end_to_end
    ]
  end

  defp print_stage_timing(stage, timing, percentiles, :v1) do
    case Map.get(timing, stage) do
      %{avg_us: avg, min_us: min, max_us: max, count: count} when count > 0 ->
        line = format_v1_timing_line(stage, avg, min, max, percentiles)
        Mix.shell().info(line)

      _ ->
        :ok
    end
  end

  defp print_stage_timing(stage, timing, _percentiles, :v2) do
    case Map.get(timing, stage) do
      %{avg_us: avg, count: count} when count > 0 ->
        stage_name = stage |> to_string() |> String.pad_trailing(16)
        Mix.shell().info("  #{stage_name} #{format_us(avg)}  /  #{count}")

      _ ->
        :ok
    end
  end

  defp format_v1_timing_line(stage, avg, min, max, percentiles) do
    stage_name = stage |> to_string() |> String.pad_trailing(14)
    basic = "#{format_us(avg)} / #{format_us(min)} / #{format_us(max)}"

    if percentiles && is_map(percentiles) do
      case Map.get(percentiles, stage) do
        %{p50: p50, p95: p95, p99: p99} when p50 > 0 ->
          "  #{stage_name} #{basic} | #{format_us(p50)} / #{format_us(p95)} / #{format_us(p99)}"

        _ ->
          "  #{stage_name} #{basic}"
      end
    else
      "  #{stage_name} #{basic}"
    end
  end

  defp print_stage_errors(stage_errors) when is_map(stage_errors) do
    total = Enum.reduce(stage_errors, 0, fn {_stage, count}, acc -> acc + count end)

    if total > 0 do
      Mix.shell().info("\nStage Errors:")

      Enum.each([:identify, :decom, :convert, :derive], fn stage ->
        count = Map.get(stage_errors, stage, 0)
        stage_name = stage |> to_string() |> String.pad_trailing(10)
        Mix.shell().info("  #{stage_name} #{count}")
      end)

      Mix.shell().info("  Total:     #{total}")
    end
  end

  defp print_stage_errors(_), do: :ok

  defp format_us(us) when is_number(us) do
    formatted = if us >= 1000, do: "#{Float.round(us / 1000, 1)}ms", else: "#{round(us)}μs"
    String.pad_leading(formatted, 8)
  end

  defp format_us(_), do: String.pad_leading("-", 8)

  # Format large numbers with commas for readability
  defp format_number(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)

  defp print_summary(initial, final, duration_ms) do
    print_summary_header()
    print_summary_stats(initial[:stats], final[:stats], duration_ms)
    print_pipeline_summary(final[:pipeline_v2])
    print_max_queue(final[:process_queues] || [])
    Mix.shell().info("")
  end

  defp print_summary_header do
    Mix.shell().info("""

    ═══════════════════════════════════════════════════════════════
                              Summary
    ═══════════════════════════════════════════════════════════════
    """)
  end

  defp print_summary_stats(
         %{packets_processed: p1, items_processed: i1, packets_received: r1} = stats1,
         %{packets_processed: p2, items_processed: i2, packets_received: r2} = stats2,
         duration_ms
       ) do
    # V1 uses packets_failed, V2 uses packets_dropped
    f1 = Map.get(stats1, :packets_failed) || Map.get(stats1, :packets_dropped, 0)
    f2 = Map.get(stats2, :packets_failed) || Map.get(stats2, :packets_dropped, 0)
    duration_sec = duration_ms / 1000

    values = %{
      packets: p2 - p1,
      items: i2 - i1,
      received: r2 - r1,
      failed: f2 - f1,
      duration_sec: duration_sec
    }

    print_throughput(values)
    print_bitrate(stats1, stats2, duration_sec)
    print_failed(values.failed)
    print_stage_errors(stats1, stats2)
    print_backpressure(values.received, values.packets)
  end

  defp print_summary_stats(_initial, _final, _duration_ms) do
    Mix.shell().info("Could not calculate throughput (stats unavailable)")
  end

  defp print_throughput(%{
         packets: packets,
         items: items,
         received: received,
         duration_sec: duration_sec
       }) do
    pps = Float.round(packets / duration_sec, 1)
    ips = Float.round(items / duration_sec, 1)
    recv_ps = Float.round(received / duration_sec, 1)

    Mix.shell().info("Received:  #{received} packets (#{recv_ps}/sec)")
    Mix.shell().info("Processed: #{packets} packets (#{pps}/sec)")
    Mix.shell().info("Items:     #{items} (#{ips}/sec)")
  end

  defp print_bitrate(stats1, stats2, duration_sec) do
    case {Map.get(stats1, :bytes_received, 0), Map.get(stats2, :bytes_received, 0)} do
      {b1, b2} when b2 > b1 ->
        bytes = b2 - b1
        bytes_per_sec = bytes / duration_sec
        mbps = Float.round(bytes_per_sec * 8 / 1_000_000, 1)
        mb_per_sec = Float.round(bytes_per_sec / 1_000_000, 2)
        Mix.shell().info("Bitrate:   #{mb_per_sec} MB/sec (#{mbps} Mbps)")

      _ ->
        :ok
    end
  end

  defp print_failed(failed) when failed > 0 do
    Mix.shell().info("Dropped:   #{failed} packets")
  end

  defp print_failed(_failed), do: :ok

  defp print_stage_errors(stats1, stats2) do
    case {Map.get(stats1, :errors), Map.get(stats2, :errors)} do
      {e1, e2} when is_map(e1) and is_map(e2) ->
        total_errors1 = Enum.reduce(e1, 0, fn {_, v}, acc -> acc + v end)
        total_errors2 = Enum.reduce(e2, 0, fn {_, v}, acc -> acc + v end)
        stage_errors = total_errors2 - total_errors1

        if stage_errors > 0 do
          Mix.shell().info("V2 Errors: #{stage_errors} stage errors")
        end

      _ ->
        :ok
    end
  end

  defp print_backpressure(received, packets) do
    if received > packets + 10 do
      Mix.shell().info("\n⚠️  Backpressure detected: #{received - packets} packets pending")
    end
  end

  defp print_pipeline_summary(%{partition_count: partition_count, router_queue: router_queue})
       when partition_count > 0 do
    router_q = if is_integer(router_queue), do: router_queue, else: 0
    Mix.shell().info("\nV2 Pipeline: #{partition_count} partitions")

    if router_q > 0 do
      Mix.shell().info("Router queue: #{router_q} pending")
    end
  end

  defp print_pipeline_summary(_pipeline_v2), do: :ok

  defp print_max_queue(queues) do
    max_queue = Enum.max_by(queues, & &1[:queue_len], fn -> %{queue_len: 0} end)

    if max_queue[:queue_len] > 0 do
      Mix.shell().info("\nMax queue depth:   #{max_queue[:name]} (#{max_queue[:queue_len]} msgs)")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.profile - Profile a running Cadence telemetry pipeline

    Usage:
      mix cadence.profile [options]

    Required Options:
      --node, -n <name>          Name of running Cadence node (e.g., cadence)
      --mission-id, -m <uuid>    Mission UUID to profile

    Optional:
      --duration, -d <seconds>   Watch duration (default: 10)
      --interval, -i <ms>        Sampling interval in ms (default: 1000)
      --snapshot                 Take a single snapshot instead of watching
      --analyze                  Show timing analysis (warmup, spikes, trimmed avg)
      --queues                   Only show process queue depths
      --help, -h                 Show this help

    Examples:
      # Start server first:
      iex --sname cadence -S mix phx.server

      # Basic profiling (10 seconds, 1-second samples)
      mix cadence.profile -n cadence -m a1b2c3d4-...

      # Longer duration, faster sampling
      mix cadence.profile -n cadence -m a1b2c3d4-... -d 30 -i 500

      # Quick snapshot
      mix cadence.profile -n cadence -m a1b2c3d4-... --snapshot

      # Check for backed-up processes
      mix cadence.profile -n cadence -m a1b2c3d4-... --queues
    """)
  end
end
