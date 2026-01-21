defmodule Mix.Tasks.Cadence.Simulate do
  @moduledoc """
  Generates continuous telemetry to exercise the telemetry pipeline.

  This Mix task starts the simulator Coordinator to generate telemetry data
  for testing, development, and alarm verification purposes. By default it
  runs in a lightweight, standalone mode and does not boot the full Cadence
  application runtime.

  ## Usage

      # Basic usage - simulate for a specific mission
      mix cadence.simulate --mission-id <uuid> --output tcp:localhost:9999

      # With scenario for alarm testing
      mix cadence.simulate \\
        --mission-id <uuid> \\
        --scenario priv/scenarios/alarm_test.yaml \\
        --definitions ~/my_mission/telemetry.yaml \\
        --output tcp:localhost:9999

      # With CCSDS encoding
      mix cadence.simulate \\
        --mission-id <uuid> \\
        --output tcp:localhost:9999 \\
        --definitions ~/my_mission/telemetry.yaml \\
        --rate 5

  ## Options

    * `--mission-id` - Mission UUID (required)
    * `--target` - Target identifier (default: SIM-1)
    * `--rate` - Packet generation rate in Hz (default: 1.0)
    * `--duration` - Duration in seconds, 0 for infinite (default: 0)
    * `--output` - Output mode: tcp:host:port, udp:host:port (required for network output)
    * `--mode` - Connection mode: connect (default) or listen (TCP only)
    * `--mode` - Connection mode: connect (default) or listen (TCP only)
    * `--scenario` - Path to YAML scenario file for deterministic testing
    * `--definitions` - Path to YAML packet definitions for proper encoding (required)
    * `--provider` - Provider: basic (default) or scenario
    * `--frame` - Frame format for network output (tm)
    * `--scid` - Spacecraft ID for frames (tm only)
    * `--vcid` - Virtual channel ID for frames (tm only)
    * `--frame-size` - Frame size in bytes (tm only)
    * `--uplink-frame` - Frame format for uplink decoding (tc or tm)
    * `--uplink-frame-size` - Frame size for uplink decoding (defaults to frame-size)
    * `--clcw` - Emit CLCW in TM OCF (tm only)
    * `--clcw-flags` - Comma-separated CLCW flags to set (lockout, wait, retransmit, etc.)
    * `--clcw-overrides` - CLCW overrides as key=value pairs (comma-separated)
    * `--clcw-schedule` - YAML file defining CLCW override schedule
    * `--uplink-drop-every` - Drop every Nth uplink frame (simulated loss)
    * `--parallel` - Enable parallel mode for high throughput
    * `--generators` - Number of generator workers (default: CPU cores)
    * `--batch-timeout` - Send buffer flush interval in ms (default: 10)
    * `--batch-size` - Send buffer flush size in bytes (default: 32768)

  ## Scenarios

  Scenarios allow deterministic, reproducible testing of alarm conditions.
  See `priv/scenarios/` for examples.

  ## Examples

      # Basic simulation with sinusoidal values
      mix cadence.simulate -m <uuid> --output tcp:localhost:9999

      # Run alarm test scenario
      mix cadence.simulate -m <uuid> \\
        --scenario priv/scenarios/alarm_battery_low.yaml \\
        --definitions path/to/telemetry.yaml \\
        --output tcp:localhost:9999

      # High-rate stress test
      mix cadence.simulate -m <uuid> -r 100 --output tcp:localhost:9999

  The task displays real-time statistics including packets sent, current rate,
  and elapsed time. Press Ctrl+C to stop gracefully.
  """

  use Mix.Task

  require Logger

  @shortdoc "Generates continuous telemetry for testing and development"

  alias Cadence.Simulator.Coordinator

  @default_rate 1.0
  @default_duration 0
  @default_target "SIM-1"
  @max_rate 50_000

  @impl Mix.Task
  def run(args) do
    config = parse_args(args)

    start_runtime(config)
    print_banner(config)

    coordinator_opts = build_coordinator_opts(config)

    case Coordinator.start_link(coordinator_opts) do
      {:ok, pid} ->
        run_simulation(pid, config)

      {:error, reason} ->
        Mix.raise("Failed to start simulator: #{inspect(reason)}")
    end
  end

  defp parse_args(args) do
    {opts, _remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          mission_id: :string,
          target: :string,
          rate: :float,
          duration: :integer,
          output: :string,
          mode: :string,
          scenario: :string,
          definitions: :string,
          provider: :string,
          frame: :string,
          scid: :integer,
          vcid: :integer,
          frame_size: :integer,
          uplink_frame: :string,
          uplink_frame_size: :integer,
          clcw: :boolean,
          clcw_flags: :string,
          clcw_overrides: :string,
          clcw_schedule: :string,
          uplink_drop_every: :integer,
          parallel: :boolean,
          generators: :integer,
          batch_timeout: :integer,
          batch_size: :integer,
          help: :boolean
        ],
        aliases: [
          m: :mission_id,
          t: :target,
          r: :rate,
          d: :duration,
          s: :scenario,
          p: :parallel,
          h: :help
        ]
      )

    if opts[:help] do
      print_help()
      System.halt(0)
    end

    if invalid != [] do
      print_help()
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    build_config(opts)
  end

  defp build_config(opts) do
    %{
      mission_id: validate_mission_id!(opts),
      target_id: opts[:target] || @default_target,
      rate_hz: parse_rate(opts[:rate]),
      duration: parse_duration(opts[:duration]),
      output: parse_output(opts[:output]),
      mode: parse_mode(opts[:mode]),
      scenario_path: opts[:scenario],
      definitions_path: opts[:definitions] || missing_definitions!(),
      provider: parse_provider(opts[:provider]),
      frame: parse_frame(opts),
      uplink_frame: parse_uplink_frame(opts),
      clcw_enabled: opts[:clcw] || false,
      clcw_overrides: parse_clcw_overrides(opts),
      clcw_schedule: parse_clcw_schedule(opts),
      uplink_drop_every: opts[:uplink_drop_every],
      parallel_mode: if(opts[:parallel], do: :parallel, else: :sequential),
      generator_count: opts[:generators],
      send_batch_timeout: opts[:batch_timeout],
      send_batch_size: opts[:batch_size]
    }
    |> validate_clcw!()
    |> validate_mode!()
  end

  defp build_coordinator_opts(config) do
    opts = [
      mission_id: config.mission_id,
      target_id: config.target_id,
      rate_hz: config.rate_hz,
      output: config.output,
      parallel_mode: config.parallel_mode,
      mode: config.mode
    ]

    # Add scenario if provided
    opts =
      if config.scenario_path do
        Keyword.put(opts, :scenario_path, config.scenario_path)
      else
        opts
      end

    # Add definitions if provided
    opts =
      if config.definitions_path do
        Keyword.put(opts, :definitions_path, config.definitions_path)
      else
        opts
      end

    # Add parallel mode options if provided
    opts =
      opts
      |> maybe_add_opt(:generator_count, config.generator_count)
      |> maybe_add_opt(:send_batch_timeout, config.send_batch_timeout)
      |> maybe_add_opt(:send_batch_size, config.send_batch_size)
      |> maybe_add_opt(:frame, config.frame)
      |> maybe_add_opt(:uplink_frame, config.uplink_frame)
      |> maybe_add_opt(:clcw_enabled, config.clcw_enabled)
      |> maybe_add_opt(:clcw_overrides, config.clcw_overrides)
      |> maybe_add_opt(:clcw_schedule, config.clcw_schedule)
      |> maybe_add_opt(:uplink_drop_every, config.uplink_drop_every)

    opts
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_provider(nil), do: :basic
  defp parse_provider("basic"), do: :basic
  defp parse_provider("scenario"), do: :scenario
  defp parse_provider(other), do: Mix.raise("Invalid provider: #{other}. Valid: basic, scenario")

  defp parse_mode(nil), do: :connect
  defp parse_mode("connect"), do: :connect
  defp parse_mode("listen"), do: :listen
  defp parse_mode(other), do: Mix.raise("Invalid mode: #{other}. Valid: connect, listen")

  defp start_runtime(_config), do: start_standalone_runtime()

  defp start_standalone_runtime do
    ensure_simulator_dependencies()

    children = [
      {Registry, keys: :unique, name: Cadence.MissionRegistry}
    ]

    opts = [strategy: :one_for_one, name: Cadence.Simulator.RuntimeSupervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Mix.raise("Failed to start simulator runtime: #{inspect(reason)}")
    end
  end

  defp ensure_simulator_dependencies do
    {:ok, _} = Application.ensure_all_started(:crypto)
    {:ok, _} = Application.ensure_all_started(:yaml_elixir)
    {:ok, _} = Application.ensure_all_started(:yamerl)
  end

  ## Private Functions

  defp validate_mission_id!(opts) do
    case opts[:mission_id] do
      nil ->
        Mix.raise("Missing required option: --mission-id")

      id ->
        # Validate UUID format
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> uuid
          :error -> Mix.raise("Invalid mission ID format. Expected UUID, got: #{id}")
        end
    end
  end

  defp parse_rate(nil), do: @default_rate
  defp parse_rate(rate) when rate > 0 and rate <= @max_rate, do: rate

  defp parse_rate(rate) when rate > @max_rate do
    Mix.shell().info("Note: Rate clamped to maximum #{@max_rate} Hz")
    @max_rate * 1.0
  end

  defp parse_rate(rate), do: Mix.raise("Rate must be positive, got: #{rate}")

  defp parse_duration(nil), do: @default_duration
  defp parse_duration(duration) when duration >= 0, do: duration
  defp parse_duration(duration), do: Mix.raise("Duration must be non-negative, got: #{duration}")

  defp parse_output(nil), do: nil

  defp parse_output("tcp:" <> rest) do
    case String.split(rest, ":") do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> {:tcp, host, port}
          _ -> Mix.raise("Invalid TCP port: #{port_str}")
        end

      _ ->
        Mix.raise("Invalid TCP output format. Expected: tcp:host:port")
    end
  end

  defp parse_output("udp:" <> rest) do
    case String.split(rest, ":") do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, ""} -> {:udp, host, port}
          _ -> Mix.raise("Invalid UDP port: #{port_str}")
        end

      _ ->
        Mix.raise("Invalid UDP output format. Expected: udp:host:port")
    end
  end

  defp parse_output(invalid) do
    Mix.raise("Invalid output: #{invalid}. Valid: tcp:host:port, udp:host:port")
  end

  defp parse_frame(opts) do
    case opts[:frame] do
      nil ->
        nil

      "tm" ->
        frame_size = opts[:frame_size] || Mix.raise("Missing required option: --frame-size")

        %{
          format: :tm,
          scid: opts[:scid] || 0,
          vcid: opts[:vcid] || 0,
          frame_size: frame_size
        }

      other ->
        Mix.raise("Invalid frame format: #{other}. Valid: tm")
    end
  end

  defp parse_uplink_frame(opts) do
    case opts[:uplink_frame] do
      nil ->
        nil

      "tc" ->
        frame_size = opts[:uplink_frame_size] || opts[:frame_size]

        if frame_size do
          %{format: :tc, frame_size: frame_size}
        else
          Mix.raise("--uplink-frame-size is required for uplink decoding")
        end

      "tm" ->
        frame_size = opts[:uplink_frame_size] || opts[:frame_size]

        if frame_size do
          %{format: :tm, frame_size: frame_size}
        else
          Mix.raise("--uplink-frame-size is required for uplink decoding")
        end

      other ->
        Mix.raise("Invalid uplink frame format: #{other}. Valid: tc, tm")
    end
  end

  defp parse_clcw_overrides(opts) do
    overrides = parse_override_pairs(opts[:clcw_overrides])
    flags = parse_flag_list(opts[:clcw_flags])
    merged = Map.merge(overrides, flags)
    if merged == %{}, do: nil, else: merged
  end

  defp parse_clcw_schedule(opts) do
    case opts[:clcw_schedule] do
      nil ->
        nil

      path ->
        parse_clcw_schedule_file(path)
    end
  end

  defp parse_clcw_schedule_file(path) do
    case File.read(path) do
      {:ok, content} ->
        parse_clcw_schedule_content(content)

      {:error, reason} ->
        Mix.raise("Failed to read --clcw-schedule file: #{inspect(reason)}")
    end
  end

  defp parse_clcw_schedule_content(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, []} ->
        nil

      {:ok, schedule} when is_list(schedule) ->
        schedule

      {:ok, _} ->
        Mix.raise("--clcw-schedule must be a YAML list of entries")

      {:error, reason} ->
        Mix.raise("Failed to parse --clcw-schedule: #{inspect(reason)}")
    end
  end

  defp parse_override_pairs(nil), do: %{}

  defp parse_override_pairs(pairs) when is_binary(pairs) do
    pairs
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      {key, value} = parse_override_pair(pair)
      Map.put(acc, key, value)
    end)
  end

  defp parse_override_pairs(_), do: %{}

  defp parse_override_pair(pair) do
    case String.split(pair, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)

        if key == "" do
          Mix.raise("Invalid --clcw-overrides entry: #{pair}")
        else
          {key, parse_override_value(String.trim(value))}
        end

      _ ->
        Mix.raise("Invalid --clcw-overrides entry: #{pair}. Expected key=value")
    end
  end

  defp parse_flag_list(nil), do: %{}

  defp parse_flag_list(flags) when is_binary(flags) do
    flags
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn flag, acc ->
      flag = String.trim(flag)
      if flag == "", do: acc, else: Map.put(acc, flag, 1)
    end)
  end

  defp parse_flag_list(_), do: %{}

  defp parse_override_value("true"), do: true
  defp parse_override_value("false"), do: false

  defp parse_override_value(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp validate_clcw!(
         %{clcw_enabled: false, clcw_overrides: overrides, clcw_schedule: schedule} = config
       ) do
    if overrides != nil or schedule != nil do
      Mix.raise("--clcw-flags/--clcw-overrides/--clcw-schedule require --clcw")
    end

    config
  end

  defp validate_clcw!(%{clcw_enabled: true, frame: %{format: :tm}} = config), do: config

  defp validate_clcw!(%{clcw_enabled: true, frame: nil}) do
    Mix.raise("--clcw requires --frame tm with --frame-size")
  end

  defp validate_clcw!(%{clcw_enabled: true}) do
    Mix.raise("--clcw is only supported for TM frames")
  end

  defp validate_mode!(%{mode: :listen, output: {:tcp, _, _}} = config), do: config

  defp validate_mode!(%{mode: :listen}) do
    Mix.raise("--mode listen requires --output tcp:host:port")
  end

  defp validate_mode!(config), do: config

  defp print_banner(config) do
    # Calculate rate mode info
    {mode, mode_detail} =
      if config.rate_hz <= 1000 do
        interval = max(1, trunc(1000 / config.rate_hz))
        {"standard", "#{interval}ms intervals"}
      else
        packets_per_tick = ceil(config.rate_hz / 1000)
        {"burst", "#{packets_per_tick} packets/ms"}
      end

    provider_info =
      if config.scenario_path do
        "scenario (#{Path.basename(config.scenario_path)})"
      else
        "basic dynamics"
      end

    definitions_info = Path.basename(config.definitions_path)

    parallel_info =
      if config.parallel_mode == :parallel do
        gen_count = config.generator_count || System.schedulers_online()
        "parallel (#{gen_count} workers)"
      else
        "sequential"
      end

    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║          Cadence Telemetry Simulator                          ║
    ╚═══════════════════════════════════════════════════════════════╝

    Configuration:
      Mission ID:    #{config.mission_id}
      Target:        #{config.target_id}
      Provider:      #{provider_info}
      Definitions:   #{definitions_info}
      Rate:          #{config.rate_hz} Hz (#{mode} mode: #{mode_detail})
      Run Mode:      #{parallel_info}
      Connection:    #{format_connection_mode(config.mode)}
      Output:        #{format_output(config.output)}
      Frame:         #{format_frame(config.frame)}
      Uplink Frame:  #{format_frame(config.uplink_frame)}
      CLCW:          #{format_clcw(config.clcw_enabled)}
      Duration:      #{format_duration(config.duration)}

    ───────────────────────────────────────────────────────────────
    Starting telemetry generation... Press Ctrl+C to stop.
    ───────────────────────────────────────────────────────────────
    """)
  end

  defp format_output(nil), do: "none (dry run)"
  defp format_output({:tcp, host, port}), do: "TCP #{host}:#{port}"
  defp format_output({:udp, host, port}), do: "UDP #{host}:#{port}"
  defp format_output(other), do: inspect(other)

  defp format_connection_mode(:connect), do: "connect (client)"
  defp format_connection_mode(:listen), do: "listen (server)"
  defp format_connection_mode(other), do: inspect(other)

  defp format_duration(0), do: "Infinite (until Ctrl+C)"
  defp format_duration(seconds), do: "#{seconds} seconds"

  defp format_frame(nil), do: "none"

  defp format_frame(%{format: :tm, scid: scid, vcid: vcid, frame_size: frame_size}) do
    "TM (scid=#{scid}, vcid=#{vcid}, size=#{frame_size})"
  end

  defp format_frame(other), do: inspect(other)

  defp format_clcw(true), do: "enabled"
  defp format_clcw(false), do: "disabled"

  defp missing_definitions! do
    Mix.raise("--definitions is required for simulator output")
  end

  defp run_simulation(pid, config) do
    start_time = System.monotonic_time(:second)

    # Run simulation loop with cleanup on exit
    try do
      if config.duration == 0 do
        # Infinite mode - print stats periodically
        run_infinite_loop(pid, start_time)
      else
        # Timed mode - print stats and wait for duration
        run_timed_loop(pid, start_time, config.duration)
      end
    catch
      :exit, _ ->
        cleanup(pid, start_time)
        :ok
    after
      # Always cleanup on exit (including Ctrl+C)
      if Process.alive?(pid) do
        cleanup(pid, start_time)
      end
    end
  end

  defp run_infinite_loop(pid, start_time) do
    # Print stats every 5 seconds
    :timer.sleep(5000)
    print_stats(pid, start_time)
    run_infinite_loop(pid, start_time)
  end

  defp run_timed_loop(pid, start_time, duration) do
    elapsed = System.monotonic_time(:second) - start_time

    if elapsed >= duration do
      # Duration complete
      Mix.shell().info("\n\nSimulation duration complete.")
      cleanup(pid, start_time)
    else
      # Print stats every 5 seconds or when duration is reached
      sleep_time = min(5000, (duration - elapsed) * 1000)
      :timer.sleep(sleep_time)
      print_stats(pid, start_time)
      run_timed_loop(pid, start_time, duration)
    end
  end

  defp print_stats(pid, start_time) do
    stats = Coordinator.stats(pid)
    elapsed = System.monotonic_time(:second) - start_time

    # Calculate actual rate
    actual_rate = if elapsed > 0, do: stats.packet_count / elapsed, else: 0.0

    base_info =
      "[#{format_elapsed(elapsed)}] " <>
        "Packets: #{format_number(stats.packet_count)} | " <>
        "Rate: #{format_rate(actual_rate)} pkt/s | " <>
        "Steps: #{format_number(stats.step)}"

    # Add parallel mode metrics if available
    output =
      case stats[:send_buffer_stats] do
        nil ->
          base_info

        buffer_stats ->
          sent = buffer_stats[:packets_sent] || 0
          bytes = buffer_stats[:bytes_sent] || 0
          sent_rate = if elapsed > 0, do: sent / elapsed, else: 0.0
          mbps = if elapsed > 0, do: bytes * 8 / elapsed / 1_000_000, else: 0.0

          base_info <>
            " | Sent: #{format_number(sent)} (#{format_rate(sent_rate)} pkt/s, #{Float.round(mbps, 2)} Mbps)"
      end

    Mix.shell().info(output)
  end

  defp cleanup(pid, start_time) do
    # Get final stats before stopping
    stats = Coordinator.stats(pid)
    elapsed = System.monotonic_time(:second) - start_time

    # Stop simulator
    Coordinator.stop(pid)

    # Print summary
    print_summary(stats, elapsed)
  end

  defp print_summary(stats, elapsed) do
    avg_rate = if elapsed > 0, do: stats.packet_count / elapsed, else: 0.0

    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║                    Simulation Summary                         ║
    ╚═══════════════════════════════════════════════════════════════╝

    Duration:        #{format_elapsed(elapsed)}
    Total Packets:   #{format_number(stats.packet_count)}
    Total Steps:     #{format_number(stats.step)}
    Average Rate:    #{format_rate(avg_rate)} packets/sec
    Target:          #{stats.target_id}
    Provider:        #{inspect(stats.provider)}

    Simulation complete.
    """)
  end

  defp format_elapsed(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}h #{minutes}m #{secs}s"
    else
      "#{minutes}m #{secs}s"
    end
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 2)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 2)}K"
  end

  defp format_number(num), do: "#{num}"

  defp format_rate(rate) do
    Float.round(rate, 2)
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.simulate - Generate continuous telemetry for testing

    Usage:
      mix cadence.simulate [options]

    By default this runs in standalone mode without starting the full Cadence app.

    Required Options:
      --mission-id, -m <uuid>    Mission UUID to simulate telemetry for
      --definitions <path>       Path to YAML packet definitions for encoding

    Optional:
      --target, -t <id>          Target identifier (default: SIM-1)
      --rate, -r <float>         Packet rate in Hz (default: 1.0, max: 15000)
      --duration, -d <seconds>   Duration in seconds, 0=infinite (default: 0)
      --output <mode>            Output: tcp:host:port, udp:host:port
      --mode <mode>              Connection mode: connect (default) or listen (TCP only)
      --scenario, -s <path>      Path to YAML scenario file for deterministic testing
      --definitions <path>       Path to YAML packet definitions for encoding
      --provider <type>          Provider: basic (default) or scenario
      --frame <format>           Frame format for network output: tm
      --scid <id>                Spacecraft ID for frames (tm only)
      --vcid <id>                Virtual channel ID for frames (tm only)
      --frame-size <bytes>       Frame size in bytes (tm only)
      --uplink-frame <format>    Frame format for uplink decoding: tc or tm
      --uplink-frame-size <bytes>Frame size for uplink decoding (defaults to frame-size)
      --clcw                     Emit CLCW in TM OCF (tm only)
      --clcw-flags <list>        Comma-separated CLCW flags to set (lockout, wait, etc.)
      --clcw-overrides <pairs>   CLCW overrides as key=value pairs
      --clcw-schedule <path>     YAML file with CLCW override schedule
      --uplink-drop-every <n>    Drop every Nth uplink frame (simulated loss)
      --help, -h                 Show this help

    Parallel Mode (for high-throughput testing):
      --parallel, -p             Enable parallel mode with multiple workers
      --generators <count>       Number of generator workers (default: CPU cores)
      --batch-timeout <ms>       Send buffer flush interval (default: 10)
      --batch-size <bytes>       Send buffer flush size (default: 32768)

    Providers:
      basic     - Generates sinusoidal telemetry values (default)
      scenario  - Executes YAML-defined scenarios for alarm testing

    Examples:
      # Basic simulation with packet definitions
      mix cadence.simulate -m <uuid> \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9999

      # Emit TM framed CCSDS packets
      mix cadence.simulate -m <uuid> \\
        --frame tm --frame-size 1115 --scid 42 --vcid 0 \\
        --output tcp:localhost:9999

      # Decode TC uplink frames for FARM
      mix cadence.simulate -m <uuid> \\
        --frame tm --frame-size 1115 --scid 42 --vcid 0 \\
        --uplink-frame tc --uplink-frame-size 1024 \\
        --output tcp:localhost:9999 --clcw

      # Inject lockout/wait flags in CLCW
      mix cadence.simulate -m <uuid> \\
        --frame tm --frame-size 1115 --scid 42 --vcid 0 \\
        --uplink-frame tc --uplink-frame-size 1024 \\
        --output tcp:localhost:9999 --clcw --clcw-flags lockout,wait

      # Listen for a TcpClientInterface connection
      mix cadence.simulate -m <uuid> \\
        --frame tm --frame-size 1115 --scid 42 --vcid 0 \\
        --output tcp:0.0.0.0:9999 --mode listen

      # Run alarm test scenario
      mix cadence.simulate -m <uuid> \\
        --scenario priv/scenarios/battery_low.yaml \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9999

      # High-rate stress test with sequential mode
      mix cadence.simulate -m <uuid> -r 100 --output tcp:localhost:9999

      # Maximum throughput with parallel mode
      mix cadence.simulate -m <uuid> -r 10000 --parallel \\
        --generators 8 --output tcp:localhost:9999
    """)
  end
end
