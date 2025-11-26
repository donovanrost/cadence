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

    # CVT stats
    case snapshot[:cvt] do
      %{total_entries: entries, memory_bytes: bytes} ->
        Mix.shell().info("CVT: #{entries} entries, #{div(bytes, 1024)} KB")

      %{error: e} ->
        Mix.shell().info("CVT: error - #{inspect(e)}")

      other ->
        Mix.shell().info("CVT: #{inspect(other)}")
    end

    # Stats (from ETS counters - works with Broadway)
    case snapshot[:stats] do
      %{packets_received: recv, packets_processed: proc, packets_failed: failed, items_processed: items} ->
        delta =
          case prev do
            %{stats: %{packets_processed: prev_proc}} ->
              " (+#{proc - prev_proc})"

            _ ->
              ""
          end

        pending = recv - proc - failed
        Mix.shell().info("Packets: #{proc} processed#{delta}, #{recv} received, #{pending} pending, #{failed} failed")
        Mix.shell().info("Items: #{items} processed")

        # Show timing if available (with percentiles)
        case snapshot[:stats] do
          %{timing: timing} when is_map(timing) ->
            percentiles = snapshot[:percentiles]
            print_timing(timing, percentiles)
          _ ->
            :ok
        end

        # Show stage errors if any
        case snapshot[:stage_errors] do
          errors when is_map(errors) ->
            print_stage_errors(errors)
          _ ->
            :ok
        end

      %{error: e} ->
        Mix.shell().info("Stats: error - #{inspect(e)}")

      other ->
        Mix.shell().info("Stats: #{inspect(other)}")
    end

    # V2 Pipeline stats (if running)
    case snapshot[:pipeline_v2] do
      %{error: :not_found} ->
        :ok

      %{router_queue: router_queue, partition_count: partition_count} = v2 ->
        router_q = if is_integer(router_queue), do: router_queue, else: 0
        Mix.shell().info("V2 Pipeline: #{partition_count} partitions, router queue: #{router_q}")

        # Show V2-specific counters
        stage_errors = Map.get(v2, :stage_errors, 0)
        dropped = Map.get(v2, :packets_dropped, 0)
        if stage_errors > 0 or dropped > 0 do
          Mix.shell().info("V2 Errors: #{stage_errors} stage errors, #{dropped} dropped")
        end

        # Show partition queue depths if any are backed up
        partitions = Map.get(v2, :partitions, %{})
        backed_up_stages = find_backed_up_v2_stages(partitions)
        if length(backed_up_stages) > 0 do
          Mix.shell().info("⚠️  V2 backed up stages:")
          Enum.each(backed_up_stages, fn {partition, stage, queue_len} ->
            Mix.shell().info("   p#{partition}:#{stage}: #{queue_len} messages")
          end)
        end

      _ ->
        :ok
    end

    # Queue warnings
    queues = snapshot[:process_queues] || []

    backed_up =
      queues
      |> Enum.filter(fn q -> is_map(q) && Map.get(q, :queue_len, 0) > 10 end)

    if length(backed_up) > 0 do
      Mix.shell().info("⚠️  Backed up processes:")

      Enum.each(backed_up, fn q ->
        Mix.shell().info("   #{q.name}: #{q.queue_len} messages")
      end)
    end

    Mix.shell().info("")
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

      Enum.each(queues, fn q ->
        status =
          cond do
            q.queue_len > 100 -> "🔴"
            q.queue_len > 10 -> "🟡"
            q.queue_len > 0 -> "🟢"
            true -> "⚪"
          end

        Mix.shell().info(
          "  #{status} #{q.name}: #{q.queue_len} msgs, #{q.memory_kb} KB, #{format_reductions(q.reductions)} reductions"
        )
      end)
    end
  end

  defp format_reductions(r) when r >= 1_000_000, do: "#{Float.round(r / 1_000_000, 1)}M"
  defp format_reductions(r) when r >= 1_000, do: "#{Float.round(r / 1_000, 1)}K"
  defp format_reductions(r), do: "#{r}"

  defp print_timing(timing), do: print_timing(timing, nil)

  defp print_timing(timing, percentiles) do
    stages_with_data = Enum.filter(timing, fn {_stage, data} ->
      is_map(data) && Map.get(data, :count, 0) > 0
    end)

    if length(stages_with_data) > 0 do
      if percentiles && is_map(percentiles) do
        Mix.shell().info("Timing (μs):      avg   /  min  /  max  |  P50  /  P95  /  P99")
      else
        Mix.shell().info("Timing (μs):  avg / min / max")
      end

      # V1 Broadway stages + V2 GenStage stages
      all_stages = [
        # V1 Broadway stages
        :identify, :decommutate, :convert, :derive,
        # V2 GenStage stages (decom is shorter name for decommutation)
        :decom,
        # Shared stages
        :cvt_batch, :ets_write, :pubsub_broadcast, :total_process,
        # End-to-end latency
        :end_to_end
      ]

      Enum.each(all_stages, fn stage ->
        case Map.get(timing, stage) do
          %{avg_us: avg, min_us: min, max_us: max, count: count} when count > 0 ->
            stage_name = stage |> to_string() |> String.pad_trailing(14)
            basic = "#{format_us(avg)} / #{format_us(min)} / #{format_us(max)}"

            line =
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

            Mix.shell().info(line)

          _ ->
            :ok
        end
      end)
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
    cond do
      us >= 1000 -> "#{Float.round(us / 1000, 1)}ms"
      true -> "#{round(us)}μs"
    end
    |> String.pad_leading(8)
  end

  defp format_us(_), do: String.pad_leading("-", 8)

  defp print_summary(initial, final, duration_ms) do
    Mix.shell().info("""

    ═══════════════════════════════════════════════════════════════
                              Summary
    ═══════════════════════════════════════════════════════════════
    """)

    case {initial[:stats], final[:stats]} do
      {%{packets_processed: p1, items_processed: i1, packets_received: r1, packets_failed: f1},
       %{packets_processed: p2, items_processed: i2, packets_received: r2, packets_failed: f2}} ->
        packets = p2 - p1
        items = i2 - i1
        received = r2 - r1
        failed = f2 - f1
        duration_sec = duration_ms / 1000
        pps = Float.round(packets / duration_sec, 1)
        ips = Float.round(items / duration_sec, 1)
        recv_ps = Float.round(received / duration_sec, 1)

        Mix.shell().info("Received:  #{received} packets (#{recv_ps}/sec)")
        Mix.shell().info("Processed: #{packets} packets (#{pps}/sec)")
        Mix.shell().info("Items:     #{items} (#{ips}/sec)")

        if failed > 0 do
          Mix.shell().info("Failed:    #{failed} packets")
        end

        # V2-specific stats
        case {initial[:stats], final[:stats]} do
          {%{stage_errors: se1, packets_dropped: pd1}, %{stage_errors: se2, packets_dropped: pd2}} ->
            stage_errors = (se2 || 0) - (se1 || 0)
            dropped = (pd2 || 0) - (pd1 || 0)
            if stage_errors > 0 or dropped > 0 do
              Mix.shell().info("V2 Errors: #{stage_errors} stage errors, #{dropped} dropped")
            end
          _ ->
            :ok
        end

        # Check for backpressure
        if received > packets + 10 do
          Mix.shell().info("\n⚠️  Backpressure detected: #{received - packets} packets pending")
        end

      _ ->
        Mix.shell().info("Could not calculate throughput (stats unavailable)")
    end

    # V2 Pipeline summary
    case final[:pipeline_v2] do
      %{partition_count: partition_count, router_queue: router_queue} when partition_count > 0 ->
        router_q = if is_integer(router_queue), do: router_queue, else: 0
        Mix.shell().info("\nV2 Pipeline: #{partition_count} partitions")
        if router_q > 0 do
          Mix.shell().info("Router queue: #{router_q} pending")
        end
      _ ->
        :ok
    end

    # Final queue check
    queues = final[:process_queues] || []
    max_queue = Enum.max_by(queues, & &1[:queue_len], fn -> %{queue_len: 0} end)

    if max_queue[:queue_len] > 0 do
      Mix.shell().info("\nMax queue depth:   #{max_queue[:name]} (#{max_queue[:queue_len]} msgs)")
    end

    Mix.shell().info("")
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
