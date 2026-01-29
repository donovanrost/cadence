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

  alias Cadence.CCSDS.Metrics
  alias Cadence.CCSDS.SDLP.Metrics, as: SDLP
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Limits.{Cache, StateTracker}
  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Telemetry.Stats
  alias Cadence.Time, as: CadenceTime

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
    print_cvt_lookup(mission_id)
    print_lanes_lookup(mission_id)
    print_cvt_table(mission_id)
    print_stats_counters(mission_id)
    print_lanes_lookup(mission_id)

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
        _ -> false
      end)

    IO.puts("   Found #{length(matching)} matching entries:")

    Enum.each(matching, fn {key, pid, value} ->
      IO.puts("   - #{inspect(key)} => #{inspect(pid)} (value: #{inspect(value)})")
    end)
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

  defp print_lanes_lookup(mission_id) do
    IO.puts("\n5. Lanes lookup:")
    router_key = {:lanes, mission_id, :router}
    lanes_key = {:lanes, mission_id, :supervisor}

    IO.puts("   Router: #{inspect(Registry.lookup(Cadence.MissionRegistry, router_key))}")
    IO.puts("   Supervisor: #{inspect(Registry.lookup(Cadence.MissionRegistry, lanes_key))}")
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

  @doc """
  Returns a snapshot of all observable metrics for a mission.
  """
  def snapshot(mission_id) do
    lanes_active = lanes_pipeline_active?(mission_id)

    stats = safe_call(fn -> PipelineMetrics.get_stats(mission_id) end)

    %{
      timestamp: CadenceTime.now(),
      stats: stats,
      percentiles: nil,
      stage_errors: Map.get(stats, :errors, %{}),
      ccsds: safe_call(fn -> Metrics.get_stats(mission_id) end),
      sdlp: safe_call(fn -> SDLP.get_stats(mission_id) end),
      cvt: safe_call(fn -> CurrentValueTable.stats(mission_id) end),
      lanes:
        if lanes_active do
          lanes_stats(mission_id)
        else
          %{error: :not_found}
        end,
      process_queues: check_queues(mission_id),
      pipeline_version: if(lanes_active, do: :lanes, else: :unknown)
    }
  end

  defp lanes_pipeline_active?(mission_id) do
    router_key = {:lanes, mission_id, :router}

    registry_active? =
      case Registry.lookup(Cadence.MissionRegistry, router_key) do
        [{_pid, _}] -> true
        [] -> false
      end

    registry_active? or PipelineMetrics.get_partition_count(mission_id) > 0
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
  Returns stats about lanes/shards pipeline.
  """
  def lanes_stats(mission_id) do
    router_key = {:via, Registry, {Cadence.MissionRegistry, {:lanes, mission_id, :router}}}

    case GenServer.whereis(router_key) do
      nil ->
        %{error: :not_found}

      router_pid ->
        alias Cadence.Runtime.Telemetry.Lanes.Router
        lane_names = lane_names(mission_id)
        lane_stats = build_lane_stats(mission_id, lane_names)

        %{
          router_pid: router_pid,
          router_queue: safe_call(fn -> Router.queue_depth(router_pid) end),
          router_queues: safe_call(fn -> Router.queue_depths(router_pid) end),
          router_mailbox: safe_call(fn -> get_queue_len(router_pid) end),
          lanes: lane_stats,
          packets_dropped: get_packets_dropped(mission_id)
        }
    end
  end

  defp build_lane_stats(mission_id, lane_names) do
    Enum.map(lane_names, fn lane ->
      shard_count = PipelineMetrics.get_partition_count(mission_id, lane)
      workers = worker_stats(mission_id, lane, shard_count)

      %{
        lane: lane,
        shard_count: shard_count,
        worker_count: length(Enum.filter(workers, & &1.alive?)),
        workers: workers,
        shards: shard_stats(mission_id, lane, shard_count)
      }
    end)
  end

  defp shard_stats(mission_id, lane, shard_count) do
    Enum.map(0..(shard_count - 1), fn shard ->
      counters = PipelineMetrics.get_counters(mission_id, {lane, shard})
      %{shard: shard, counters: counters}
    end)
  end

  defp worker_stats(mission_id, lane, shard_count) do
    Enum.map(0..(shard_count - 1), fn shard ->
      worker_stats_for_shard(mission_id, lane, shard)
    end)
  end

  defp worker_stats_for_shard(mission_id, lane, shard) do
    worker_key = {:lanes, mission_id, {:shard, lane, shard}}

    case Registry.lookup(Cadence.MissionRegistry, worker_key) do
      [{pid, _}] -> worker_info(pid, shard)
      [] -> %{shard: shard, alive?: false}
    end
  end

  defp worker_info(pid, shard) do
    case Process.info(pid, [:message_queue_len, :memory, :reductions, :status]) do
      nil ->
        %{shard: shard, alive?: false}

      info ->
        %{
          shard: shard,
          alive?: true,
          pid: pid,
          queue_len: info[:message_queue_len],
          memory_kb: div(info[:memory], 1024),
          reductions: info[:reductions],
          status: info[:status]
        }
    end
  end

  defp lane_names(mission_id) do
    case PipelineMetrics.get_partition_keys(mission_id) do
      [] ->
        [:payload]

      keys ->
        keys
        |> Enum.filter(&match?({_, _}, &1))
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()
    end
  end

  @doc """
  Calculates throughput between two snapshots.
  """
  def throughput(snapshot1, snapshot2) do
    time_diff_ms =
      DateTime.diff(snapshot2.timestamp, snapshot1.timestamp, :millisecond)

    case {snapshot1.stats, snapshot2.stats} do
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

  defp get_packets_dropped(mission_id) do
    case safe_call(fn -> PipelineMetrics.get_stats(mission_id) end) do
      %{packets_dropped: dropped} -> dropped
      _ -> 0
    end
  end

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

    basic_procs
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
    print_ccsds_snapshot(snapshot)
    print_sdlp_snapshot(snapshot)
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
    print_timing_breakdown(stats, snapshot)
    print_stage_errors_snapshot(snapshot)
  end

  defp print_stats_snapshot(%{stats: other}, _prev) do
    IO.puts("Stats: #{inspect(other)}")
  end

  defp print_ccsds_snapshot(%{ccsds: stats}) when is_map(stats) and map_size(stats) > 0 do
    stats
    |> build_ccsds_totals()
    |> Enum.each(&print_ccsds_totals/1)
  end

  defp print_ccsds_snapshot(_snapshot), do: :ok

  defp print_sdlp_snapshot(%{sdlp: stats}) when is_map(stats) and map_size(stats) > 0 do
    stats
    |> Enum.sort_by(fn {profile, _} -> profile end)
    |> Enum.each(&print_sdlp_totals/1)
  end

  defp print_sdlp_snapshot(_snapshot), do: :ok

  defp print_sdlp_totals({profile, metrics}) do
    decode = metrics.frame_decode
    encode = metrics.frame_encode
    seg = metrics.segmentation
    reasm = metrics.reassembly

    IO.puts(
      "SDLP #{profile}: dec #{decode.ok}/#{decode.total} drop #{decode.drop} " <>
        "enc #{encode.ok}/#{encode.total} seg #{seg.segments_emitted} " <>
        "reasm #{reasm.sdu_emitted} in #{format_bytes(decode.bytes_in)} out #{format_bytes(encode.bytes_out)}"
    )
  end

  defp build_ccsds_totals(stats) do
    Enum.reduce(stats, %{}, fn {_transport_id, profiles}, acc ->
      accumulate_profiles(acc, profiles)
    end)
  end

  defp accumulate_profiles(acc, profiles) do
    Enum.reduce(profiles, acc, fn {profile, metrics}, acc ->
      Map.put(acc, profile, accumulate_metrics(Map.get(acc, profile, %{}), metrics))
    end)
  end

  defp accumulate_metrics(acc, metrics) do
    Enum.reduce(metrics, acc, fn {metric, count}, acc_metrics ->
      Map.update(acc_metrics, metric, count, &(&1 + count))
    end)
  end

  defp print_ccsds_totals({profile, metrics}) do
    IO.puts(
      "CCSDS #{profile}: frames=#{Map.get(metrics, :frames_decoded, 0)}, sdu=#{Map.get(metrics, :sdu_octets, 0)}, packets=#{Map.get(metrics, :packets_emitted, 0)}, idle=#{Map.get(metrics, :idle_packets, 0)}, errors=#{ccsds_error_count(metrics)}"
    )
  end

  defp ccsds_error_count(metrics) do
    Map.get(metrics, :frame_decode_errors, 0) +
      Map.get(metrics, :reassembly_errors, 0) +
      Map.get(metrics, :sdu_decode_errors, 0)
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 2)}MB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_000 do
    "#{Float.round(bytes / 1_000, 2)}KB"
  end

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes}B"

  defp packet_delta(%{stats: %{packets_processed: prev_proc}}, proc),
    do: " (+#{proc - prev_proc}/s)"

  defp packet_delta(_prev, _proc), do: ""

  defp print_throughput(%{packets_per_sec_rolling: pps, bytes_per_sec_rolling: bps} = stats)
       when pps > 0 do
    mbps = Float.round(bps * 8 / 1_000_000, 1)
    mb_per_sec = Float.round(bps / 1_000_000, 2)
    window_ms = Map.get(stats, :rolling_duration_ms, 0)

    IO.puts(
      "Throughput: #{format_number(round(pps))} packets/sec, #{mb_per_sec} MB/sec (#{mbps} Mbps, rolling #{window_ms}ms)"
    )
  end

  defp print_throughput(%{packets_per_sec_rolling: pps}) when pps > 0 do
    IO.puts("Throughput: #{format_number(round(pps))} packets/sec (rolling)")
  end

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

  # Removed unused single-arity version - use print_timing(timing, nil) directly

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

      Enum.each([:identify_missing_catalog, :identify_unknown_packet], fn stage ->
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
