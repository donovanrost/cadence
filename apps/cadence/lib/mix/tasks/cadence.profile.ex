defmodule Mix.Tasks.Cadence.Profile do
  @moduledoc """
  Profiles a running Cadence downlink ingress pipeline.

  This task connects to a running Cadence node and samples the new telemetry
  profiler while traffic is being driven through the simulator or another
  ingress source.

  ## Usage

      iex --sname cadence -S mix phx.server
      mix cadence.profile --node cadence --mission-id mission-alpha

  ## Options

    * `--node`, `-n` - Name of the running Cadence node (required)
    * `--mission-id`, `-m` - Mission identifier to profile (required)
    * `--duration`, `-d` - Duration in seconds for watch mode (default: 10)
    * `--interval`, `-i` - Sampling interval in ms for watch mode (default: 1000)
    * `--snapshot` - Print one cumulative snapshot and exit
    * `--reset` - Reset mission profiler counters before sampling
    * `--help`, `-h` - Show help
  """

  use Mix.Task

  alias Cadence.DevProfile

  @shortdoc "Profile a running Cadence downlink ingress pipeline"

  @default_duration 10
  @default_interval 1000

  @impl true
  def run(args) do
    {profile_identifier, option_args} = extract_profile_identifier(args)
    profile_defaults = profile_defaults(profile_identifier)

    {opts, remaining, invalid} =
      OptionParser.parse(
        option_args,
        strict: [
          node: :string,
          mission_id: :string,
          duration: :integer,
          interval: :integer,
          snapshot: :boolean,
          reset: :boolean,
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

    maybe_handle_help_or_invalid_opts(opts, remaining, invalid)

    node_name = validate_node!(opts, profile_defaults.node)
    mission_id = validate_mission_id!(opts, profile_defaults.mission_id)
    config = build_profile_config(node_name, mission_id, opts)

    start_distribution()
    connect_to_node(config.node)
    maybe_reset_profiler(config)
    run_profile_mode(config)
  end

  defp profile_defaults(nil), do: %{node: nil, mission_id: nil}

  defp profile_defaults(identifier) do
    identifier
    |> DevProfile.load!()
    |> DevProfile.profiler_defaults()
  end

  defp maybe_handle_help_or_invalid_opts(opts, remaining, invalid) do
    if opts[:help] || invalid != [] || remaining != [] do
      print_help()
      maybe_raise_invalid_opts(invalid)
      maybe_raise_remaining_args(remaining)
      System.halt(0)
    end
  end

  defp maybe_raise_invalid_opts([]), do: :ok

  defp maybe_raise_invalid_opts(invalid) do
    Mix.raise("Invalid options: #{inspect(invalid)}")
  end

  defp maybe_raise_remaining_args([]), do: :ok

  defp maybe_raise_remaining_args(remaining) do
    Mix.raise("Unexpected arguments: #{inspect(remaining)}")
  end

  defp build_profile_config(node_name, mission_id, opts) do
    %{
      node: node_name,
      mission_id: mission_id,
      duration_seconds: opts[:duration] || @default_duration,
      interval_ms: opts[:interval] || @default_interval,
      snapshot?: opts[:snapshot] || false,
      reset?: opts[:reset] || false
    }
  end

  defp maybe_reset_profiler(%{reset?: false}), do: :ok

  defp maybe_reset_profiler(config) do
    case rpc_call(config.node, Cadence.Telemetry.Profiler, :reset, [config.mission_id]) do
      :ok ->
        Mix.shell().info("Reset profiler counters for #{config.mission_id}.\n")

      {:badrpc, reason} ->
        Mix.raise("Failed to reset profiler counters: #{inspect(reason)}")
    end
  end

  defp run_profile_mode(%{snapshot?: true} = config) do
    config
    |> fetch_snapshot!()
    |> print_snapshot()
  end

  defp run_profile_mode(config) do
    run_watch(config)
  end

  defp validate_node!(opts, default) do
    case opts[:node] || default do
      nil ->
        Mix.raise("Missing required option: --node")

      name ->
        name
        |> to_string()
        |> ensure_node_host()
        |> validate_node_name!()
    end
  end

  defp validate_mission_id!(opts, default) do
    case opts[:mission_id] || default do
      mission_id when is_binary(mission_id) and mission_id != "" ->
        mission_id

      _other ->
        Mix.raise("Missing required option: --mission-id")
    end
  end

  defp ensure_node_host(name) do
    if String.contains?(name, "@") do
      name
    else
      "#{name}@#{hostname()}"
    end
  end

  defp validate_node_name!(name) when is_binary(name) do
    if byte_size(name) <= 128 and
         Regex.match?(~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$/, name) do
      String.to_atom(name)
    else
      Mix.raise("Invalid node name: #{inspect(name)}")
    end
  end

  defp start_distribution do
    local_node = :"profiler_#{System.unique_integer([:positive])}@#{hostname()}"

    case Node.start(local_node, :shortnames) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Mix.raise("Failed to start distributed node: #{inspect(reason)}")
    end

    maybe_set_distribution_cookie()
  end

  defp connect_to_node(target_node) do
    Mix.shell().info("Connecting to #{target_node}...")

    case Node.connect(target_node) do
      true ->
        Mix.shell().info("Connected successfully.\n")

      false ->
        Mix.raise("""
        Failed to connect to #{target_node}.

        Make sure the server is running with a node name, for example:
          iex --sname cadence -S mix phx.server

        If the server was started with a non-default Erlang cookie, set the
        same cookie in `CADENCE_NODE_COOKIE` before running this task.
        """)

      :ignored ->
        Mix.raise("Local profiler node is not alive.")
    end
  end

  defp run_watch(config) do
    Mix.shell().info("""
    Profiling mission #{config.mission_id} for #{config.duration_seconds}s at #{config.interval_ms}ms intervals.
    Drive traffic now with cadence_simulator or another ingress source.
    """)

    initial_snapshot = fetch_snapshot!(config)
    print_watch_header()

    sample_count =
      max(div(config.duration_seconds * 1000, config.interval_ms), 1)

    Enum.reduce(1..sample_count, initial_snapshot, fn sample_index, previous_snapshot ->
      Process.sleep(config.interval_ms)
      current_snapshot = fetch_snapshot!(config)
      print_watch_sample(sample_index, config.interval_ms, previous_snapshot, current_snapshot)
      current_snapshot
    end)
    |> print_cumulative_footer()
  end

  defp fetch_snapshot!(config) do
    case rpc_call(config.node, Cadence.Telemetry.Profiler, :snapshot, [config.mission_id]) do
      {:badrpc, reason} ->
        Mix.raise("Profiler RPC failed: #{inspect(reason)}")

      snapshot when is_map(snapshot) ->
        snapshot
    end
  end

  defp print_watch_header do
    Mix.shell().info(
      " interval  ingress/s  packets/s  samples/s  avg_ms(resolve/runtime/persist/e2e)  db_q/ing  db_ms/ing  db_ops/ing(S/I/U/D)  arch(q/old_ms/fl_ms/seg_kb/fail)"
    )
  end

  defp print_watch_sample(sample_index, interval_ms, previous_snapshot, current_snapshot) do
    ingress_delta = delta(current_snapshot, previous_snapshot, [:ingress_count])
    packet_delta = delta(current_snapshot, previous_snapshot, [:packets, :packet_count])
    sample_delta = delta(current_snapshot, previous_snapshot, [:dispatch, :sample_count])

    resolve_us_delta = delta(current_snapshot, previous_snapshot, [:stages, :resolve, :total_us])
    runtime_us_delta = delta(current_snapshot, previous_snapshot, [:stages, :runtime, :total_us])

    persistence_us_delta =
      delta(current_snapshot, previous_snapshot, [:stages, :persistence, :total_us])

    end_to_end_us_delta =
      delta(current_snapshot, previous_snapshot, [:stages, :end_to_end, :total_us])

    db_query_delta = delta(current_snapshot, previous_snapshot, [:db, :query_count])
    db_us_delta = delta(current_snapshot, previous_snapshot, [:db, :query_total_us])
    select_delta = delta(current_snapshot, previous_snapshot, [:db, :operations, :select_count])
    insert_delta = delta(current_snapshot, previous_snapshot, [:db, :operations, :insert_count])
    update_delta = delta(current_snapshot, previous_snapshot, [:db, :operations, :update_count])
    delete_delta = delta(current_snapshot, previous_snapshot, [:db, :operations, :delete_count])
    archive_queue_depth = get_in(current_snapshot, [:archive, :combined, :queue_depth])

    archive_oldest_buffered_age_ms =
      get_in(current_snapshot, [:archive, :combined, :oldest_buffered_age_ms])

    archive_flush_count_delta =
      delta(current_snapshot, previous_snapshot, [:archive, :combined, :flush_count])

    archive_flush_total_us_delta =
      delta(current_snapshot, previous_snapshot, [:archive, :combined, :flush_total_us])

    archive_segment_count_delta =
      delta(current_snapshot, previous_snapshot, [:archive, :combined, :segment_count])

    archive_flushed_bytes_delta =
      delta(current_snapshot, previous_snapshot, [:archive, :combined, :flushed_bytes_total])

    archive_flush_failure_delta =
      delta(current_snapshot, previous_snapshot, [:archive, :combined, :flush_failure_count])

    interval_sec = interval_ms / 1000.0

    Mix.shell().info(
      String.pad_leading(Integer.to_string(sample_index), 8) <>
        String.pad_leading(format_rate(ingress_delta, interval_sec), 11) <>
        String.pad_leading(format_rate(packet_delta, interval_sec), 11) <>
        String.pad_leading(format_rate(sample_delta, interval_sec), 11) <>
        "  " <>
        format_stage_ms(resolve_us_delta, ingress_delta) <>
        "/" <>
        format_stage_ms(runtime_us_delta, ingress_delta) <>
        "/" <>
        format_stage_ms(persistence_us_delta, ingress_delta) <>
        "/" <>
        format_stage_ms(end_to_end_us_delta, ingress_delta) <>
        String.pad_leading(format_avg(db_query_delta, ingress_delta, 1), 11) <>
        String.pad_leading(format_avg(db_us_delta / 1000.0, ingress_delta, 2), 11) <>
        "  " <>
        format_avg(select_delta, ingress_delta, 1) <>
        "/" <>
        format_avg(insert_delta, ingress_delta, 1) <>
        "/" <>
        format_avg(update_delta, ingress_delta, 1) <>
        "/" <>
        format_avg(delete_delta, ingress_delta, 1) <>
        "  " <>
        Integer.to_string(archive_queue_depth) <>
        "/" <>
        Integer.to_string(archive_oldest_buffered_age_ms) <>
        "/" <>
        format_avg(archive_flush_total_us_delta / 1000.0, archive_flush_count_delta, 2) <>
        "/" <>
        format_avg(archive_flushed_bytes_delta / 1024.0, archive_segment_count_delta, 1) <>
        "/" <>
        Integer.to_string(archive_flush_failure_delta)
    )
  end

  defp print_cumulative_footer(snapshot) do
    Mix.shell().info("\nCumulative snapshot:\n")
    print_snapshot(snapshot)
  end

  defp print_snapshot(snapshot) do
    Mix.shell().info("""
    Mission: #{snapshot.mission_id}
    Duration: #{Float.round(snapshot.duration_sec, 2)}s
    Ingress: #{snapshot.ingress_count} total, #{snapshot.ingress_error_count} errors
    Data: #{snapshot.packets.packet_count} packets, #{snapshot.packets.transfer_frame_count} frames, #{snapshot.dispatch.sample_count} samples

    Stage avg (ms):
      resolve      #{format_us_as_ms(snapshot.stages.resolve.avg_us)}
      runtime      #{format_us_as_ms(snapshot.stages.runtime.avg_us)}
      persistence  #{format_us_as_ms(snapshot.stages.persistence.avg_us)}
      end_to_end   #{format_us_as_ms(snapshot.stages.end_to_end.avg_us)}

    DB:
      queries      #{snapshot.db.query_count} total (#{Float.round(snapshot.db.queries_per_ingress, 2)}/ingress)
      query time   #{format_us_as_ms(snapshot.db.query_avg_us)} avg/query, #{format_us_as_ms(snapshot.db.query_time_per_ingress_us)} per ingress
      operations   select=#{snapshot.db.operations.select_count} insert=#{snapshot.db.operations.insert_count} update=#{snapshot.db.operations.update_count} delete=#{snapshot.db.operations.delete_count} other=#{snapshot.db.operations.other_count}
      by stage     resolve=#{snapshot.db.by_stage.resolve.query_count} runtime=#{snapshot.db.by_stage.runtime.query_count} persistence=#{snapshot.db.by_stage.persistence.query_count}

    Archive:
      combined     queue=#{snapshot.archive.combined.queue_depth} oldest_ms=#{snapshot.archive.combined.oldest_buffered_age_ms} flushes=#{snapshot.archive.combined.flush_count} failures=#{snapshot.archive.combined.flush_failure_count} avg_flush_ms=#{format_us_as_ms(snapshot.archive.combined.avg_flush_us)} avg_seg_kb=#{format_number(snapshot.archive.combined.avg_segment_bytes / 1024.0, 1)}
      ingress      queue=#{snapshot.archive.ingress.queue_depth} oldest_ms=#{snapshot.archive.ingress.oldest_buffered_age_ms} flushes=#{snapshot.archive.ingress.flush_count} failures=#{snapshot.archive.ingress.flush_failure_count} avg_flush_ms=#{format_us_as_ms(snapshot.archive.ingress.avg_flush_us)} avg_seg_kb=#{format_number(snapshot.archive.ingress.avg_segment_bytes / 1024.0, 1)}
      protocol     queue=#{snapshot.archive.protocol.queue_depth} oldest_ms=#{snapshot.archive.protocol.oldest_buffered_age_ms} flushes=#{snapshot.archive.protocol.flush_count} failures=#{snapshot.archive.protocol.flush_failure_count} avg_flush_ms=#{format_us_as_ms(snapshot.archive.protocol.avg_flush_us)} avg_seg_kb=#{format_number(snapshot.archive.protocol.avg_segment_bytes / 1024.0, 1)}
      last error   #{snapshot.archive.combined.last_flush_error || "none"}
    """)
  end

  defp delta(current, previous, path) when is_list(path) do
    get_in(current, path) - get_in(previous, path)
  end

  defp format_rate(value, interval_sec) do
    format_number(value / interval_sec, 1)
  end

  defp format_stage_ms(_total_us, 0), do: "0.00"
  defp format_stage_ms(total_us, count), do: format_number(total_us / count / 1000.0, 2)

  defp format_us_as_ms(us), do: format_number(us / 1000.0, 2)

  defp format_avg(_total, 0, decimals), do: format_number(0.0, decimals)
  defp format_avg(total, count, decimals), do: format_number(total / count, decimals)

  defp format_number(number, decimals) when is_number(number) do
    :erlang.float_to_binary(number * 1.0, decimals: decimals)
  end

  defp rpc_call(node, module, function, args) do
    :rpc.call(node, module, function, args)
  end

  defp hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp maybe_set_distribution_cookie do
    case System.get_env("CADENCE_NODE_COOKIE") || System.get_env("ERL_COOKIE") do
      nil ->
        :ok

      cookie ->
        Node.set_cookie(String.to_atom(cookie))
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.profile - Profile a running Cadence downlink ingress pipeline

    Usage:
      mix cadence.profile PROFILE [options]
      mix cadence.profile [options]

    Required:
      --node, -n <name>         Running Cadence node name
      --mission-id, -m <id>     Mission identifier to profile

    Optional:
      --duration, -d <seconds>  Watch duration (default: #{@default_duration})
      --interval, -i <ms>       Watch interval in ms (default: #{@default_interval})
      --snapshot                Print one cumulative snapshot and exit
      --reset                   Reset counters before sampling
      --help, -h                Show this help

    Example:
      mix cadence.profile demo_spacecraft
    """)
  end

  defp extract_profile_identifier([candidate | rest]) when is_binary(candidate) do
    if String.starts_with?(candidate, "-") do
      {nil, [candidate | rest]}
    else
      {candidate, rest}
    end
  end

  defp extract_profile_identifier([]), do: {nil, []}
end
