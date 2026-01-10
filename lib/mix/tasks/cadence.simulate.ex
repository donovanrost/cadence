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
          scenario: :string,
          definitions: :string,
          provider: :string,
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
      scenario_path: opts[:scenario],
      definitions_path: opts[:definitions],
      provider: parse_provider(opts[:provider]),
      parallel_mode: if(opts[:parallel], do: :parallel, else: :sequential),
      generator_count: opts[:generators],
      send_batch_timeout: opts[:batch_timeout],
      send_batch_size: opts[:batch_size]
    }
  end

  defp build_coordinator_opts(config) do
    opts = [
      mission_id: config.mission_id,
      target_id: config.target_id,
      rate_hz: config.rate_hz,
      output: config.output,
      parallel_mode: config.parallel_mode
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

    opts
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_provider(nil), do: :basic
  defp parse_provider("basic"), do: :basic
  defp parse_provider("scenario"), do: :scenario
  defp parse_provider(other), do: Mix.raise("Invalid provider: #{other}. Valid: basic, scenario")

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
      Mode:          #{parallel_info}
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

    Optional:
      --target, -t <id>          Target identifier (default: SIM-1)
      --rate, -r <float>         Packet rate in Hz (default: 1.0, max: 15000)
      --duration, -d <seconds>   Duration in seconds, 0=infinite (default: 0)
      --output <mode>            Output: tcp:host:port, udp:host:port
      --scenario, -s <path>      Path to YAML scenario file for deterministic testing
      --definitions <path>       Path to YAML packet definitions for encoding
      --provider <type>          Provider: basic (default) or scenario
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
      # Basic simulation with hardcoded encoding
      mix cadence.simulate -m <uuid> --output tcp:localhost:9999

      # Using packet definitions for proper encoding
      mix cadence.simulate -m <uuid> \\
        --definitions ~/mission/telemetry.yaml \\
        --output tcp:localhost:9999

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
