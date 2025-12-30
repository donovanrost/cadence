defmodule Cadence.Telemetry.Profiler do
  @moduledoc """
  Helper module for profiling and observing the telemetry pipeline performance.

  Use this module to gather metrics while running the simulator at high rates
  to identify bottlenecks.

  ## Quick Start

      # Get a snapshot of all metrics for a mission
      Cadence.Telemetry.Profiler.snapshot(mission_id)

      # Watch metrics over time (prints every second for 10 seconds)
      Cadence.Telemetry.Profiler.watch(mission_id, duration: 10_000, interval: 1_000)

      # Check for backed-up processes
      Cadence.Telemetry.Profiler.check_queues(mission_id)

      # Debug - dump all raw data
      Cadence.Telemetry.Profiler.debug(mission_id)

      # Profile limits evaluation specifically
      Cadence.Telemetry.Profiler.limits_stats(mission_id)

      # Analyze timing warmup and spikes
      Cadence.Telemetry.Profiler.analyze(mission_id)
  """

  alias Cadence.Runtime.Telemetry.{BroadwayPubSub, Pipeline}
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.{Cache, StateTracker}
  alias Cadence.Runtime.Telemetry.PipelineV2.{PartitionRouter, PartitionSupervisor}
  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Telemetry.Stats

  @doc """
  Analyzes timing data to detect warmup effects and GC spikes.

  Shows:
  - Warmup samples (first 10 packets per stage)
  - Comparison: avg vs trimmed avg vs median
  - Spike count (samples > 3σ from mean)
  - Whether first packet is skewing the average

  Use this to diagnose if timing measurements are affected by:
  - JIT/cache warmup (first packets slow)
  - GC pauses (random spikes)
  - Outliers skewing the average
  """
  def analyze(mission_id) do
    IO.puts("\n=== Timing Analysis: Warmup & Spike Detection ===\n")

    analysis = Stats.get_all_timing_analysis(mission_id)

    # Show analysis for key stages
    stages_to_show = [:identify, :decom, :convert, :derive, :limits, :end_to_end]

    Enum.each(stages_to_show, fn stage ->
      case Map.get(analysis, stage) do
        %{sample_count: count} = data when count > 0 ->
          print_stage_analysis(stage, data)

        _ ->
          :ok
      end
    end)

    IO.puts("=== Legend ===")
    IO.puts("  avg       - Standard average (affected by outliers)")
    IO.puts("  trimmed   - Average excluding top/bottom 5%")
    IO.puts("  median    - Middle value (P50)")
    IO.puts("  warmup    - First 10 samples (may be slow due to JIT/cache)")
    IO.puts("  spikes    - Samples > 3σ from mean (likely GC pauses)")
    IO.puts("")

    :ok
  end

  defp print_stage_analysis(stage, data) do
    stage_name = stage |> to_string() |> String.upcase()

    IO.puts("#{stage_name} (#{data.sample_count} samples)")

    IO.puts(
      "  Averages:  avg=#{format_us(data.avg_us)}  trimmed=#{format_us(data.trimmed_avg_us)}  median=#{format_us(data.median_us)}"
    )

    # Warmup analysis
    if length(data.warmup_samples) > 0 do
      warmup_str = Enum.map_join(data.warmup_samples, ", ", &format_us_compact/1)
      IO.puts("  Warmup:    [#{warmup_str}]  avg=#{format_us(data.warmup_avg_us)}")

      # Check if first packet is an outlier
      first = List.first(data.warmup_samples)

      if first && first > data.avg_us * 2 do
        IO.puts(
          "  ⚠️  First packet (#{format_us(first)}) is #{Float.round(first / data.avg_us, 1)}x slower than avg"
        )
      end

      # Check if warmup avg is significantly higher
      if data.warmup_avg_us > data.trimmed_avg_us * 1.5 do
        IO.puts(
          "  ⚠️  Warmup period #{Float.round(data.warmup_avg_us / data.trimmed_avg_us, 1)}x slower than steady state"
        )
      end
    end

    # Spike analysis
    if data.spike_count > 0 do
      spike_pct = Float.round(data.spike_count / data.sample_count * 100, 2)

      IO.puts(
        "  Spikes:    #{data.spike_count} samples (#{spike_pct}%) > #{format_us(data.spike_threshold_us)}"
      )
    end

    # Show how much outliers affect the average
    if abs(data.avg_us - data.trimmed_avg_us) > data.trimmed_avg_us * 0.1 do
      diff_pct = Float.round((data.avg_us - data.trimmed_avg_us) / data.trimmed_avg_us * 100, 1)
      IO.puts("  📊 Outliers inflate avg by #{diff_pct}% (use trimmed for accurate measurement)")
    end

    IO.puts("")
  end

  defp format_us_compact(us) when is_number(us) do
    if us >= 1000, do: "#{Float.round(us / 1000, 1)}ms", else: "#{round(us)}μs"
  end

  defp format_us_compact(_), do: "-"

  @doc """
  Debug function - dumps all raw data to help diagnose profiler issues.
  """
  def debug(mission_id) do
    IO.puts("\n=== DEBUG: Profiler Diagnostics ===\n")
    print_registry_entries(mission_id)
    print_pipeline_lookup(mission_id)
    print_cvt_lookup(mission_id)
    print_broadway_lookup(mission_id)
    print_cvt_table(mission_id)
    print_stats_counters(mission_id)
    print_pipeline_v2_lookup(mission_id)

    IO.puts("\n=== END DEBUG ===\n")
    :ok
  end

  defp print_registry_entries(mission_id) do
    IO.puts("1. All Registry entries for this mission:")

    all_keys =
      Registry.select(Cadence.MissionRegistry, [
        {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
      ])

    matching =
      Enum.filter(all_keys, fn
        {{^mission_id, _}, _, _} -> true
        {{:broadway_pipeline, ^mission_id, _}, _, _} -> true
        _ -> false
      end)

    IO.puts("   Found #{length(matching)} matching entries:")

    Enum.each(matching, fn {key, pid, value} ->
      IO.puts("   - #{inspect(key)} => #{inspect(pid)} (value: #{inspect(value)})")
    end)
  end

  defp print_pipeline_lookup(mission_id) do
    IO.puts("\n2. Direct Pipeline lookup:")
    pipeline_key = {mission_id, :telemetry_pipeline}

    case Registry.lookup(Cadence.MissionRegistry, pipeline_key) do
      [{pid, value}] ->
        IO.puts("   Found: #{inspect(pid)}, value: #{inspect(value)}")
        IO.puts("   Process alive? #{Process.alive?(pid)}")
        IO.puts("   Attempting GenServer.call(:stats)...")
        print_pipeline_stats(pid)

      [] ->
        IO.puts("   NOT FOUND with key #{inspect(pipeline_key)}")
    end
  end

  defp print_pipeline_stats(pid) do
    case safe_call(fn -> GenServer.call(pid, :stats, 5000) end) do
      %{error: error} -> IO.puts("   Error: #{error}")
      result -> IO.puts("   Result: #{inspect(result)}")
    end
  end

  defp print_cvt_lookup(mission_id) do
    IO.puts("\n3. Direct CVT lookup:")
    cvt_key = {mission_id, :cvt}

    case Registry.lookup(Cadence.MissionRegistry, cvt_key) do
      [{pid, value}] ->
        IO.puts("   Found: #{inspect(pid)}, value: #{inspect(value)}")
        IO.puts("   Process alive? #{Process.alive?(pid)}")
        IO.puts("   Attempting CurrentValueTable.stats()...")
        print_cvt_stats(mission_id)

      [] ->
        IO.puts("   NOT FOUND")
    end
  end

  defp print_cvt_stats(mission_id) do
    case safe_call(fn -> CurrentValueTable.stats(mission_id) end) do
      %{error: error} -> IO.puts("   Error: #{error}")
      result -> IO.puts("   Result: #{inspect(result)}")
    end
  end

  defp print_broadway_lookup(mission_id) do
    IO.puts("\n4. Broadway lookup:")
    broadway_key = {:broadway_pipeline, mission_id, :main}

    case Registry.lookup(Cadence.MissionRegistry, broadway_key) do
      [{pid, _}] ->
        IO.puts("   Found: #{inspect(pid)}")
        IO.puts("   Process alive? #{Process.alive?(pid)}")

      [] ->
        IO.puts("   NOT FOUND with key #{inspect(broadway_key)}")
    end
  end

  defp print_cvt_table(mission_id) do
    IO.puts("\n5. ETS tables:")
    cvt_table = String.to_atom("cvt_mission_#{mission_id}")

    case :ets.info(cvt_table) do
      :undefined ->
        IO.puts("   CVT table #{cvt_table} does not exist")

      info ->
        IO.puts("   CVT table #{cvt_table}:")
        IO.puts("   - size: #{info[:size]}")
        IO.puts("   - memory: #{info[:memory]} words")
    end
  end

  defp print_stats_counters(mission_id) do
    IO.puts("\n6. Stats (ETS counters):")

    try do
      stats = Stats.get(mission_id)
      IO.puts("   packets_received: #{stats.packets_received}")
      IO.puts("   packets_processed: #{stats.packets_processed}")
      IO.puts("   packets_failed: #{stats.packets_failed}")
      IO.puts("   items_processed: #{stats.items_processed}")
      IO.puts("   stage_errors: #{stats.stage_errors}")
      IO.puts("   packets_dropped: #{stats.packets_dropped}")
      IO.puts("   duration: #{Float.round(stats.duration_sec, 1)}s")
      IO.puts("   rate: #{stats.packets_per_sec} packets/sec")
    rescue
      e -> IO.puts("   Error: #{Exception.message(e)}")
    catch
      kind, reason -> IO.puts("   Caught #{kind}: #{inspect(reason)}")
    end
  end

  defp print_pipeline_v2_lookup(mission_id) do
    IO.puts("\n7. Pipeline V2 lookup:")
    router_key = {:pipeline_v2, mission_id, :router}

    case Registry.lookup(Cadence.MissionRegistry, router_key) do
      [{pid, _}] ->
        IO.puts("   Router found: #{inspect(pid)}")
        IO.puts("   Process alive? #{Process.alive?(pid)}")
        print_router_depth(pid)
        print_partition_stats(mission_id)

      [] ->
        IO.puts("   NOT FOUND with key #{inspect(router_key)}")
    end
  end

  defp print_router_depth(pid) do
    case safe_call(fn -> PartitionRouter.queue_depth(pid) end) do
      %{error: error} -> IO.puts("   Queue depth error: #{error}")
      depth -> IO.puts("   Router queue depth: #{depth}")
    end
  end

  defp print_partition_stats(mission_id) do
    partition_count = count_partitions(mission_id)
    IO.puts("   Partition count: #{partition_count}")
    print_partition_stages(mission_id, partition_count)
  end

  defp print_partition_stages(_mission_id, partition_count) when partition_count <= 0, do: :ok

  defp print_partition_stages(mission_id, _partition_count) do
    IO.puts("   Partition 0 stages:")

    for stage <- [:identify, :decom, :convert, :derive] do
      stage_name = PartitionSupervisor.stage_name(mission_id, 0, stage)

      case GenServer.whereis(stage_name) do
        nil -> IO.puts("     #{stage}: NOT FOUND")
        pid -> IO.puts("     #{stage}: #{inspect(pid)}")
      end
    end
  end

  @doc """
  Returns a snapshot of all observable metrics for a mission.
  """
  def snapshot(mission_id) do
    # Check if V2 pipeline is running
    v2_active = v2_pipeline_active?(mission_id)

    # Use PipelineMetrics for V2, Stats for V1 (Broadway)
    stats =
      if v2_active do
        safe_call(fn -> PipelineMetrics.get_stats(mission_id) end)
      else
        safe_call(fn -> Stats.get(mission_id) end)
      end

    %{
      timestamp: DateTime.utc_now(),
      stats: stats,
      # Percentiles only available for V1 (Stats keeps raw samples)
      percentiles:
        unless(v2_active, do: safe_call(fn -> Stats.get_all_percentiles(mission_id) end)),
      stage_errors:
        if v2_active do
          # V2 errors are in stats.errors
          Map.get(stats, :errors, %{})
        else
          safe_call(fn -> Stats.get_stage_errors(mission_id) end)
        end,
      cvt: safe_call(fn -> CurrentValueTable.stats(mission_id) end),
      pipeline: safe_call(fn -> Pipeline.stats(mission_id) end),
      broadway: broadway_stats(mission_id),
      pipeline_v2: pipeline_v2_stats(mission_id),
      process_queues: check_queues(mission_id),
      pipeline_version: if(v2_active, do: :v2, else: :v1)
    }
  end

  defp v2_pipeline_active?(mission_id) do
    router_key = {:pipeline_v2, mission_id, :router}

    case Registry.lookup(Cadence.MissionRegistry, router_key) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Watches metrics over time, printing snapshots at regular intervals.

  Options:
    - `:duration` - Total time to watch in ms (default: 10_000)
    - `:interval` - Time between snapshots in ms (default: 1_000)
  """
  def watch(mission_id, opts \\ []) do
    duration = Keyword.get(opts, :duration, 10_000)
    interval = Keyword.get(opts, :interval, 1_000)
    iterations = div(duration, interval)

    IO.puts("\n=== Starting #{iterations} samples over #{duration}ms ===\n")

    initial = snapshot(mission_id)
    print_snapshot(initial, nil)

    _final =
      Enum.reduce(1..iterations, initial, fn i, prev ->
        Process.sleep(interval)
        current = snapshot(mission_id)
        print_snapshot(current, prev)

        if i == iterations do
          print_summary(initial, current, duration)
        end

        current
      end)

    :ok
  end

  @doc """
  Checks message queue depths for all telemetry-related processes.

  Returns a list of processes with queue depth > 0, sorted by queue size.
  """
  def check_queues(mission_id) do
    # Find all processes registered for this mission
    mission_processes = find_mission_processes(mission_id)

    # Get queue info for each
    mission_processes
    |> Enum.map(fn {name, pid} ->
      case Process.info(pid, [:message_queue_len, :reductions, :memory, :current_function]) do
        nil ->
          nil

        info ->
          %{
            name: name,
            pid: pid,
            queue_len: info[:message_queue_len],
            reductions: info[:reductions],
            memory_kb: div(info[:memory], 1024),
            current_function: info[:current_function]
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.queue_len, :desc)
  end

  @doc """
  Returns stats about Broadway pipeline processes.
  """
  def broadway_stats(mission_id) do
    # Find Broadway processes via Registry
    broadway_key = {:broadway_pipeline, mission_id, :main}

    case Registry.lookup(Cadence.MissionRegistry, broadway_key) do
      [{pid, _}] ->
        # Get producer queue depth
        producer_queue_depth = get_producer_queue_depth(mission_id)

        %{
          main_pid: pid,
          main_queue: get_queue_len(pid),
          producer_queue_depth: producer_queue_depth,
          producers: find_broadway_children(pid, "Producer"),
          processors: find_broadway_children(pid, "Processor"),
          batchers: find_broadway_children(pid, "Batcher")
        }

      [] ->
        %{error: :not_found}
    end
  end

  @doc """
  Returns stats about PipelineV2 GenStage processes.
  """
  def pipeline_v2_stats(mission_id) do
    router_key = {:via, Registry, {Cadence.MissionRegistry, {:pipeline_v2, mission_id, :router}}}

    case GenServer.whereis(router_key) do
      nil ->
        %{error: :not_found}

      router_pid ->
        # Get router queue depth
        router_queue = safe_call(fn -> PartitionRouter.queue_depth(router_pid) end)

        # Find partition count by looking for registered stages
        partition_count = count_partitions(mission_id)

        # Get stats for each partition's stages
        partition_stats =
          if partition_count > 0 do
            for partition <- 0..(partition_count - 1), into: %{} do
              stages = get_partition_stage_stats(mission_id, partition)
              {partition, stages}
            end
          else
            %{}
          end

        %{
          router_pid: router_pid,
          router_queue: router_queue,
          partition_count: partition_count,
          partitions: partition_stats,
          # V2-specific counters from Stats
          stage_errors: safe_call(fn -> get_v2_counter(mission_id, :stage_errors) end),
          packets_dropped: safe_call(fn -> get_v2_counter(mission_id, :packets_dropped) end)
        }
    end
  end

  defp count_partitions(mission_id) do
    # Count how many partition 0 stages exist (indicates partition count)
    # Look for identify stages across partitions
    Registry.select(Cadence.MissionRegistry, [
      {
        {{:pipeline_v2, :"$1", {:stage, :"$2", :identify}}, :_, :_},
        [{:==, :"$1", mission_id}],
        [:"$2"]
      }
    ])
    |> length()
  end

  defp get_partition_stage_stats(mission_id, partition) do
    stages = [:identify, :decom, :convert, :derive]

    for stage <- stages, into: %{} do
      stage_name = PartitionSupervisor.stage_name(mission_id, partition, stage)

      stats =
        case GenServer.whereis(stage_name) do
          nil ->
            %{error: :not_found}

          pid ->
            case Process.info(pid, [:message_queue_len, :reductions, :memory]) do
              nil ->
                %{error: :dead}

              info ->
                %{
                  pid: pid,
                  queue_len: info[:message_queue_len],
                  reductions: info[:reductions],
                  memory_kb: div(info[:memory], 1024)
                }
            end
        end

      {stage, stats}
    end
  end

  defp get_v2_counter(mission_id, counter) do
    stats = Stats.get(mission_id)
    Map.get(stats, counter, 0)
  end

  defp get_producer_queue_depth(mission_id) do
    # Find the Producer_0 process
    producer_key = {:broadway_pipeline, mission_id, "Producer_0"}

    case Registry.lookup(Cadence.MissionRegistry, producer_key) do
      [{pid, _}] ->
        try do
          BroadwayPubSub.queue_depth(pid)
        catch
          _, _ -> nil
        end

      [] ->
        nil
    end
  end

  @doc """
  Calculates throughput between two snapshots.
  """
  def throughput(snapshot1, snapshot2) do
    time_diff_ms =
      DateTime.diff(snapshot2.timestamp, snapshot1.timestamp, :millisecond)

    case {snapshot1.pipeline, snapshot2.pipeline} do
      {%{packets_processed: p1}, %{packets_processed: p2}} ->
        packets_diff = p2 - p1
        packets_per_sec = packets_diff / (time_diff_ms / 1000)

        %{
          packets_processed: packets_diff,
          duration_ms: time_diff_ms,
          packets_per_second: Float.round(packets_per_sec, 1)
        }

      _ ->
        %{error: :pipeline_stats_unavailable}
    end
  end

  @doc """
  Returns detailed statistics about limits evaluation performance.

  Shows:
  - Timing statistics (avg, min, max, percentiles)
  - StateTracker stats (tracked items, transitions)
  - Cache stats (entries, hit rate if tracked)
  """
  def limits_stats(mission_id) do
    IO.puts("\n=== Limits Evaluation Statistics ===\n")

    print_limits_timing(mission_id)
    print_state_tracker_stats(mission_id)
    print_limits_cache_stats()
    print_limits_timing_analysis(mission_id)

    IO.puts("\n=== End Limits Stats ===\n")
    :ok
  end

  defp print_limits_timing(mission_id) do
    IO.puts("1. Timing (limits evaluation per packet):")
    timing = Stats.get_timing(mission_id)

    case Map.get(timing, :limits) do
      %{avg_us: avg, min_us: min, max_us: max, count: count} when count > 0 ->
        IO.puts("   Evaluations: #{count}")
        IO.puts("   Average:     #{format_us(avg)}")
        IO.puts("   Min:         #{format_us(min)}")
        IO.puts("   Max:         #{format_us(max)}")
        print_limits_percentiles(mission_id)

      _ ->
        IO.puts("   No limits timing data recorded yet")
    end
  end

  defp print_limits_percentiles(mission_id) do
    percentiles = Stats.get_percentiles(mission_id, :limits)
    IO.puts("   P50:         #{format_us(percentiles.p50)}")
    IO.puts("   P95:         #{format_us(percentiles.p95)}")
    IO.puts("   P99:         #{format_us(percentiles.p99)}")
  end

  defp print_state_tracker_stats(mission_id) do
    IO.puts("\n2. StateTracker:")
    tracker_stats = safe_call(fn -> StateTracker.stats(mission_id) end)

    case tracker_stats do
      %{tracked_items: items, table_memory_bytes: mem, state_counts: state_counts} ->
        IO.puts("   Tracked items:  #{items}")
        IO.puts("   Table memory:   #{div(mem, 1024)} KB")
        print_state_breakdown(state_counts)

      %{error: :not_found} ->
        IO.puts("   StateTracker not running")

      other ->
        IO.puts("   #{inspect(other)}")
    end
  end

  defp print_state_breakdown(state_counts) do
    if map_size(state_counts) > 0 do
      IO.puts("   State breakdown:")

      Enum.each(state_counts, fn {state, count} ->
        IO.puts("     #{state}: #{count}")
      end)
    end
  end

  defp print_limits_cache_stats do
    IO.puts("\n3. Limits Cache:")
    cache_stats = safe_call(fn -> Cache.stats() end)

    case cache_stats do
      %{size: size, memory_bytes: mem} ->
        IO.puts("   Cached targets: #{size}")
        IO.puts("   Cache memory:   #{div(mem, 1024)} KB")

      %{error: _} ->
        IO.puts("   Cache not available")

      other ->
        IO.puts("   #{inspect(other)}")
    end
  end

  defp print_limits_timing_analysis(mission_id) do
    IO.puts("\n4. Timing Analysis:")
    analysis = Stats.get_timing_analysis(mission_id, :limits)

    if analysis.sample_count > 0 do
      IO.puts("   Samples:       #{analysis.sample_count}")
      IO.puts("   Avg:           #{format_us(analysis.avg_us)}")
      IO.puts("   Trimmed avg:   #{format_us(analysis.trimmed_avg_us)}")
      IO.puts("   Median:        #{format_us(analysis.median_us)}")
      print_spikes(analysis)
      print_warmup(analysis)
    else
      IO.puts("   No timing samples recorded")
    end
  end

  defp print_spikes(%{spike_count: spike_count, sample_count: sample_count})
       when spike_count > 0 do
    spike_pct = Float.round(spike_count / sample_count * 100, 2)
    IO.puts("   Spikes:        #{spike_count} (#{spike_pct}%)")
  end

  defp print_spikes(_analysis), do: :ok

  defp print_warmup(%{warmup_samples: warmup_samples}) when length(warmup_samples) > 0 do
    warmup_str =
      warmup_samples
      |> Enum.take(5)
      |> Enum.map_join(", ", &format_us_compact/1)

    IO.puts("   Warmup:        [#{warmup_str}...]")
  end

  defp print_warmup(_analysis), do: :ok

  # Private helpers

  defp safe_call(fun) do
    fun.()
  rescue
    e -> %{error: Exception.message(e)}
  catch
    :exit, reason -> %{error: inspect(reason)}
  end

  defp find_mission_processes(mission_id) do
    # Query Registry for all processes with this mission_id
    # Pattern 1: {mission_id, type} keys
    basic_procs =
      Registry.select(Cadence.MissionRegistry, [
        {
          {{:"$1", :"$2"}, :"$3", :_},
          [{:==, :"$1", mission_id}],
          [{{:"$2", :"$3"}}]
        }
      ])
      |> Enum.map(fn {type, pid} -> {"#{type}", pid} end)

    # Pattern 2: {:broadway_pipeline, mission_id, suffix} keys
    broadway_procs =
      Registry.select(Cadence.MissionRegistry, [
        {
          {{:broadway_pipeline, :"$1", :"$2"}, :"$3", :_},
          [{:==, :"$1", mission_id}],
          [{{:"$2", :"$3"}}]
        }
      ])
      |> Enum.map(fn {suffix, pid} -> {"broadway:#{suffix}", pid} end)

    # Pattern 3: {:pipeline_v2, mission_id, key} keys
    v2_procs =
      Registry.select(Cadence.MissionRegistry, [
        {
          {{:pipeline_v2, :"$1", :"$2"}, :"$3", :_},
          [{:==, :"$1", mission_id}],
          [{{:"$2", :"$3"}}]
        }
      ])
      |> Enum.map(fn
        {:router, pid} -> {"v2:router", pid}
        {:batcher, pid} -> {"v2:batcher", pid}
        {:supervisor, pid} -> {"v2:supervisor", pid}
        {{:stage, partition, stage}, pid} -> {"v2:p#{partition}:#{stage}", pid}
        {{:partition_sup, partition}, pid} -> {"v2:p#{partition}:sup", pid}
        {other, pid} -> {"v2:#{inspect(other)}", pid}
      end)

    basic_procs ++ broadway_procs ++ v2_procs
  end

  defp find_broadway_children(broadway_pid, name_pattern) do
    # Broadway creates child processes with predictable naming
    # Try to find them via process links or Supervisor.which_children
    case Process.info(broadway_pid, :links) do
      {:links, links} ->
        links
        |> Enum.filter(&is_pid/1)
        |> Enum.map(&build_broadway_child(&1, name_pattern))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp build_broadway_child(pid, name_pattern) do
    case Process.info(pid, [:registered_name, :message_queue_len]) do
      nil ->
        nil

      info ->
        name = info[:registered_name] || inspect(pid)

        if String.contains?(to_string(name), name_pattern) do
          %{pid: pid, name: name, queue_len: info[:message_queue_len]}
        else
          nil
        end
    end
  end

  defp get_queue_len(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> nil
    end
  end

  defp print_snapshot(snapshot, prev) do
    IO.puts("--- #{format_time(snapshot.timestamp)} ---")

    print_cvt_snapshot(snapshot.cvt)
    print_stats_snapshot(snapshot, prev)
    print_queue_warnings(snapshot.process_queues)

    IO.puts("")
  end

  defp print_cvt_snapshot(%{total_entries: entries, memory_bytes: bytes}) do
    IO.puts("CVT: #{entries} entries, #{div(bytes, 1024)} KB")
  end

  defp print_cvt_snapshot(other) do
    IO.puts("CVT: #{inspect(other)}")
  end

  defp print_stats_snapshot(
         %{
           stats:
             %{packets_received: _recv, packets_processed: proc, items_processed: items} = stats
         } = snapshot,
         prev
       ) do
    failed = Map.get(stats, :packets_failed) || Map.get(stats, :packets_dropped, 0)
    delta = packet_delta(prev, proc)

    IO.puts("Packets: #{proc} processed#{delta}, #{failed} dropped, 0 failed")
    IO.puts("Items: #{items} processed")

    print_throughput(stats)
    print_router_queue(snapshot.pipeline_v2)
    print_producer_queue(snapshot.broadway)
    print_timing_breakdown(stats, snapshot)
    print_stage_errors_snapshot(snapshot)
  end

  defp print_stats_snapshot(%{stats: other}, _prev) do
    IO.puts("Stats: #{inspect(other)}")
  end

  defp packet_delta(%{stats: %{packets_processed: prev_proc}}, proc),
    do: " (+#{proc - prev_proc}/s)"

  defp packet_delta(_prev, _proc), do: ""

  defp print_throughput(%{packets_per_sec: pps, bytes_per_sec: bps}) when bps > 0 do
    mbps = Float.round(bps * 8 / 1_000_000, 1)
    mb_per_sec = Float.round(bps / 1_000_000, 2)

    IO.puts(
      "Throughput: #{format_number(round(pps))} packets/sec, #{mb_per_sec} MB/sec (#{mbps} Mbps)"
    )
  end

  defp print_throughput(%{packets_per_sec: pps}) when pps > 0 do
    IO.puts("Throughput: #{format_number(round(pps))} packets/sec")
  end

  defp print_throughput(_stats), do: :ok

  defp print_router_queue(%{router_queue: depth}) when is_integer(depth) and depth > 0 do
    IO.puts("Router queue: #{depth} pending")
  end

  defp print_router_queue(_pipeline_v2), do: :ok

  defp print_producer_queue(%{producer_queue_depth: depth})
       when is_integer(depth) and depth > 0 do
    IO.puts("Producer queue: #{depth} waiting")
  end

  defp print_producer_queue(_broadway), do: :ok

  defp print_timing_breakdown(%{timing: timing}, snapshot)
       when is_map(timing) and map_size(timing) > 0 do
    percentiles = Map.get(snapshot, :percentiles)
    first_stage_data = timing |> Map.values() |> List.first()

    if first_stage_data && Map.has_key?(first_stage_data, :min_us) do
      print_timing(timing, percentiles)
    else
      print_timing_v2(timing, percentiles)
    end
  end

  defp print_timing_breakdown(_stats, _snapshot), do: :ok

  defp print_stage_errors_snapshot(%{stage_errors: errors})
       when is_map(errors) and map_size(errors) > 0 do
    print_stage_errors(errors)
  end

  defp print_stage_errors_snapshot(_snapshot), do: :ok

  defp print_queue_warnings(process_queues) do
    backed_up = Enum.filter(process_queues, fn q -> q.queue_len > 10 end)

    if length(backed_up) > 0 do
      IO.puts("⚠️  Backed up processes:")

      Enum.each(backed_up, fn q ->
        IO.puts("   #{q.name}: #{q.queue_len} messages")
      end)
    end
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(other), do: inspect(other)

  # V2 timing format: %{stage => %{avg_us: float, count: integer}}
  defp print_timing_v2(timing, _percentiles) do
    stages_with_data =
      timing
      |> Enum.filter(fn {_stage, data} ->
        is_map(data) && Map.get(data, :count, 0) > 0
      end)

    if length(stages_with_data) > 0 do
      IO.puts("")
      IO.puts("Timing (μs):          avg   /  samples")

      stages = [:identify, :decom, :convert, :derive, :limits, :cvt_batch, :ets_write]

      Enum.each(stages, &print_v2_stage(timing, &1))
    end
  end

  defp print_v2_stage(timing, stage) do
    case Map.get(timing, stage) do
      %{avg_us: avg, count: count} when count > 0 ->
        stage_name = stage |> to_string() |> String.pad_trailing(16)
        IO.puts("  #{stage_name} #{format_us(avg)}  /  #{count}")

      _ ->
        :ok
    end
  end

  # V1 timing format: %{stage => %{avg_us, min_us, max_us, count}}
  defp print_timing(timing, percentiles) do
    # Only print if we have data
    stages_with_data = Enum.filter(timing, fn {_stage, data} -> data.count > 0 end)

    if length(stages_with_data) > 0 do
      print_timing_header(percentiles)
      Enum.each(all_timing_stages(), &print_v1_stage(timing, percentiles, &1))
    end
  end

  defp print_timing_header(percentiles) do
    if percentiles && is_map(percentiles) do
      IO.puts("Timing (μs):      avg   /  min  /  max  |  P50  /  P95  /  P99")
    else
      IO.puts("Timing (μs):  avg / min / max")
    end
  end

  defp all_timing_stages do
    [
      :identify,
      :decommutate,
      :convert,
      :derive,
      :decom,
      :limits,
      :cvt_batch,
      :ets_write,
      :pubsub_broadcast,
      :total_process,
      :end_to_end
    ]
  end

  defp print_v1_stage(timing, percentiles, stage) do
    case Map.get(timing, stage) do
      %{avg_us: avg, min_us: min, max_us: max, count: count} when count > 0 ->
        stage_name = stage |> to_string() |> String.pad_trailing(14)
        basic = "#{format_us(avg)} / #{format_us(min)} / #{format_us(max)}"
        IO.puts(timing_line(stage_name, basic, percentiles, stage))

      _ ->
        :ok
    end
  end

  defp timing_line(stage_name, basic, percentiles, stage) do
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
      IO.puts("\nStage Errors:")

      Enum.each([:identify, :decom, :convert, :derive], fn stage ->
        count = Map.get(stage_errors, stage, 0)
        stage_name = stage |> to_string() |> String.pad_trailing(10)
        IO.puts("  #{stage_name} #{count}")
      end)

      IO.puts("  Total:     #{total}")
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
    IO.puts("=== Summary ===")

    case {initial.stats, final.stats} do
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

        IO.puts("Received:  #{received} packets (#{recv_ps}/sec)")
        IO.puts("Processed: #{packets} packets (#{pps}/sec)")
        IO.puts("Items:     #{items} (#{ips}/sec)")

        if failed > 0 do
          IO.puts("Failed:    #{failed} packets")
        end

        # Check for backpressure
        if received > packets + 10 do
          IO.puts("\n⚠️  Backpressure detected: #{received - packets} packets pending")
        end

      _ ->
        IO.puts("Could not calculate throughput (stats unavailable)")
    end
  end
end
