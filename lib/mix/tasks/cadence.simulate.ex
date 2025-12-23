defmodule Mix.Tasks.Cadence.Simulate do
  @moduledoc """
  Generates continuous telemetry to exercise the telemetry pipeline.

  This Mix task starts the simulator Coordinator to generate telemetry data
  for testing, development, and alarm verification purposes.

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
        --rate 5

  ## Options

    * `--mission-id` - Mission UUID (required)
    * `--target` - Target identifier (default: SIM-1)
    * `--rate` - Packet generation rate in Hz (default: 1.0)
    * `--duration` - Duration in seconds, 0 for infinite (default: 0)
    * `--output` - Output mode: tcp:host:port, udp:host:port (required for network output)
    * `--scenario` - Path to YAML scenario file for deterministic testing
    * `--definitions` - Path to YAML packet definitions for proper encoding
    * `--provider` - Provider: basic (default) or scenario

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
  @max_rate 15_000

  @impl Mix.Task
  def run(args) do
    # Parse command-line arguments
    {opts, _remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          mission_id: :string,
          target: :string,
          rate: :float,
          duration: :integer,
          output: :string,
          scenario: :string,
          definitions: :string,
          provider: :string,
          start_mission: :boolean,
          help: :boolean
        ],
        aliases: [
          m: :mission_id,
          t: :target,
          r: :rate,
          d: :duration,
          s: :scenario,
          h: :help
        ]
      )

    # Show help if requested or invalid options
    if opts[:help] || invalid != [] do
      print_help()
      if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")
      System.halt(0)
    end

    # Validate and extract mission_id
    mission_id = validate_mission_id!(opts)

    # Parse configuration
    config = %{
      mission_id: mission_id,
      target_id: opts[:target] || @default_target,
      rate_hz: parse_rate(opts[:rate]),
      duration: parse_duration(opts[:duration]),
      output: parse_output(opts[:output]),
      scenario_path: opts[:scenario],
      definitions_path: opts[:definitions],
      provider: parse_provider(opts[:provider]),
      start_mission: opts[:start_mission] || false
    }

    # Start the application (needed for supervision tree, PubSub, etc.)
    Mix.Task.run("app.start")

    # Start the mission if requested (starts interfaces, pipeline, etc.)
    maybe_start_mission(config)

    # Display configuration
    print_banner(config)

    # Build coordinator options
    coordinator_opts = build_coordinator_opts(config)

    case Coordinator.start_link(coordinator_opts) do
      {:ok, pid} ->
        run_simulation(pid, config)

      {:error, reason} ->
        Mix.raise("Failed to start simulator: #{inspect(reason)}")
    end
  end

  defp build_coordinator_opts(config) do
    opts = [
      mission_id: config.mission_id,
      target_id: config.target_id,
      rate_hz: config.rate_hz,
      output: config.output
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

    opts
  end

  defp parse_provider(nil), do: :basic
  defp parse_provider("basic"), do: :basic
  defp parse_provider("scenario"), do: :scenario
  defp parse_provider(other), do: Mix.raise("Invalid provider: #{other}. Valid: basic, scenario")

  defp maybe_start_mission(%{start_mission: true, mission_id: mission_id}) do
    Mix.shell().info("Starting mission runtime (interfaces, pipeline, etc.)...")

    # Mix task - use unscoped for CLI access
    case Cadence.Missions.get_mission(mission_id) do
      {:error, :not_found} ->
        Mix.raise("Mission not found: #{mission_id}")

      {:ok, mission} ->
        case Cadence.Missions.start_mission(mission.id, mission.organization_id) do
          {:ok, _mission} ->
            Mix.shell().info("Mission started")
            # Give interfaces time to start
            :timer.sleep(500)

          {:error, reason} ->
            Mix.raise("Failed to start mission: #{inspect(reason)}")
        end
    end
  end

  defp maybe_start_mission(_config), do: :ok

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
    Mix.raise("Invalid output: #{invalid}. Valid: pubsub, tcp:host:port, udp:host:port")
  end

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

    definitions_info =
      if config.definitions_path do
        Path.basename(config.definitions_path)
      else
        "hardcoded (legacy)"
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
      Output:        #{format_output(config.output)}
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

  defp format_duration(0), do: "Infinite (until Ctrl+C)"
  defp format_duration(seconds), do: "#{seconds} seconds"

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

    Mix.shell().info(
      "[#{format_elapsed(elapsed)}] " <>
        "Packets: #{format_number(stats.packet_count)} | " <>
        "Rate: #{format_rate(actual_rate)} pkt/s | " <>
        "Steps: #{format_number(stats.step)}"
    )
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

    Required Options:
      --mission-id, -m <uuid>    Mission UUID to simulate telemetry for

    Optional:
      --target, -t <id>          Target identifier (default: SIM-1)
      --rate, -r <float>         Packet rate in Hz (default: 1.0, max: 15000)
      --duration, -d <seconds>   Duration in seconds, 0=infinite (default: 0)
      --output <mode>            Output: tcp:host:port, udp:host:port
      --scenario, -s <path>      Path to YAML scenario file for deterministic testing
      --definitions <path>       Path to YAML packet definitions for encoding
      --provider <type>          Provider: basic (default) or scenario
      --start-mission            Start the mission runtime (interfaces, pipeline)
      --help, -h                 Show this help

    Providers:
      basic     - Generates sinusoidal telemetry values (default)
      scenario  - Executes YAML-defined scenarios for alarm testing

    Examples:
      # Basic simulation with hardcoded encoding
      mix cadence.simulate -m <uuid> --output tcp:localhost:9999

      # With mission runtime started (for end-to-end testing)
      mix cadence.simulate -m <uuid> \\
        --start-mission \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9000

      # Using packet definitions for proper encoding
      mix cadence.simulate -m <uuid> \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9999

      # Run alarm test scenario
      mix cadence.simulate -m <uuid> \\
        --scenario priv/scenarios/battery_low.yaml \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9999

      # High-rate stress test
      mix cadence.simulate -m <uuid> -r 100 --output tcp:localhost:9999
    """)
  end
end
