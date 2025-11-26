defmodule Mix.Tasks.Cadence.Simulate do
  @moduledoc """
  Generates continuous telemetry to exercise the telemetry read pipeline.

  This Mix task starts the PacketSimulator to generate realistic telemetry data
  for testing, development, and load testing purposes.

  ## Usage

      # Basic usage - simulate for a specific mission
      mix cadence.simulate --mission-id <uuid>

      # Advanced options
      mix cadence.simulate \\
        --mission-id <uuid> \\
        --targets SAT-1,SAT-2,SAT-3 \\
        --rate 10 \\
        --duration 60 \\
        --packet-types health,attitude,power \\
        --encoding json

      # With protocol chain (e.g., CRC) from interface
      mix cadence.simulate \\
        --mission-id <uuid> \\
        --interface-id <uuid> \\
        --encoding ccsds \\
        --output tcp:localhost:9999

  ## Options

    * `--mission-id` - Mission UUID (required)
    * `--interface-id` - Interface UUID to get write protocols from (optional)
    * `--targets` - Comma-separated list of target IDs (default: sim-target-1)
    * `--rate` - Packet generation rate in Hz per target (default: 1.0)
    * `--duration` - Duration in seconds, 0 for infinite (default: 0)
    * `--packet-types` - Comma-separated packet types: health,attitude,power (default: all)
    * `--encoding` - Encoding format: json or ccsds (default: json)
    * `--output` - Output mode: pubsub, tcp:host:port, udp:host:port (default: pubsub)

  When `--interface-id` is provided, outgoing packets are processed through
  the interface's write protocol chain. This allows testing protocols like
  CRC that append data to packets.

  ## Examples

      # Simulate 3 satellites at 10 Hz for 60 seconds
      mix cadence.simulate \\
        --mission-id a1b2c3d4-... \\
        --targets SAT-1,SAT-2,SAT-3 \\
        --rate 10 \\
        --duration 60

      # Continuous simulation with CCSDS encoding
      mix cadence.simulate \\
        --mission-id a1b2c3d4-... \\
        --encoding ccsds \\
        --duration 0

      # Send telemetry to TCP interface for integration testing
      mix cadence.simulate \\
        --mission-id a1b2c3d4-... \\
        --output tcp:localhost:9999 \\
        --rate 5

  The task displays real-time statistics including packets sent, current rate,
  and elapsed time. Press Ctrl+C to stop gracefully.
  """

  use Mix.Task

  require Logger

  @shortdoc "Generates continuous telemetry for testing and development"

  @default_rate 1.0
  @default_duration 0
  @default_targets ["sim-target-1"]
  @default_packet_types [:health, :attitude, :power]
  @default_encoding :json
  @default_output :pubsub
  # Maximum supported rate (matches PacketSimulator)
  @max_rate 15_000

  @impl Mix.Task
  def run(args) do
    # Parse command-line arguments
    {opts, _remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          mission_id: :string,
          interface_id: :string,
          targets: :string,
          rate: :float,
          duration: :integer,
          packet_types: :string,
          encoding: :string,
          output: :string,
          help: :boolean
        ],
        aliases: [
          m: :mission_id,
          i: :interface_id,
          t: :targets,
          r: :rate,
          d: :duration,
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
    interface_id = parse_interface_id(opts[:interface_id])

    # Parse configuration
    config = %{
      mission_id: mission_id,
      interface_id: interface_id,
      targets: parse_targets(opts[:targets]),
      rate_hz: parse_rate(opts[:rate]),
      duration: parse_duration(opts[:duration]),
      packet_types: parse_packet_types(opts[:packet_types]),
      encoding: parse_encoding(opts[:encoding]),
      output: parse_output(opts[:output])
    }

    # Start the application (needed for supervision tree, PubSub, etc.)
    Mix.Task.run("app.start")

    # Display configuration
    print_banner(config)

    # Start simulator
    simulator_opts =
      [
        mission_id: config.mission_id,
        targets: config.targets,
        packet_types: config.packet_types,
        rate_hz: config.rate_hz,
        encoding: config.encoding,
        output: config.output
      ]
      |> maybe_add_interface_id(config.interface_id)

    case Cadence.Simulator.PacketSimulator.start_link(simulator_opts) do
      {:ok, pid} ->
        run_simulation(pid, config)

      {:error, reason} ->
        Mix.raise("Failed to start simulator: #{inspect(reason)}")
    end
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

  defp parse_interface_id(nil), do: nil

  defp parse_interface_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> Mix.raise("Invalid interface ID format. Expected UUID, got: #{id}")
    end
  end

  defp maybe_add_interface_id(opts, nil), do: opts
  defp maybe_add_interface_id(opts, interface_id), do: Keyword.put(opts, :interface_id, interface_id)

  defp parse_targets(nil), do: @default_targets

  defp parse_targets(targets_str) do
    targets_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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

  defp parse_packet_types(nil), do: @default_packet_types

  defp parse_packet_types(types_str) do
    types_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn type ->
      case String.downcase(type) do
        "health" -> :health
        "attitude" -> :attitude
        "power" -> :power
        invalid -> Mix.raise("Invalid packet type: #{invalid}. Valid: health, attitude, power")
      end
    end)
  end

  defp parse_encoding(nil), do: @default_encoding

  defp parse_encoding(encoding_str) do
    case String.downcase(encoding_str) do
      "json" -> :json
      "ccsds" -> :ccsds
      invalid -> Mix.raise("Invalid encoding: #{invalid}. Valid: json, ccsds")
    end
  end

  defp parse_output(nil), do: @default_output

  defp parse_output("pubsub"), do: :pubsub

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
    interface_line = if config.interface_id do
      "  Interface ID:  #{config.interface_id} (write chain enabled)\n"
    else
      ""
    end

    # Calculate rate mode info
    {mode, mode_detail} =
      if config.rate_hz <= 1000 do
        interval = max(1, trunc(1000 / config.rate_hz))
        {"standard", "#{interval}ms intervals"}
      else
        packets_per_tick = ceil(config.rate_hz / 1000)
        {"burst", "#{packets_per_tick} packets/ms"}
      end

    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║          Cadence Telemetry Simulator                          ║
    ╚═══════════════════════════════════════════════════════════════╝

    Configuration:
      Mission ID:    #{config.mission_id}
    #{interface_line}  Targets:       #{Enum.join(config.targets, ", ")} (#{length(config.targets)} total)
      Packet Types:  #{Enum.join(config.packet_types, ", ")}
      Rate:          #{config.rate_hz} Hz per target (#{mode} mode: #{mode_detail})
      Encoding:      #{config.encoding}
      Output:        #{format_output(config.output)}
      Duration:      #{format_duration(config.duration)}

    Total Rate:      #{config.rate_hz * length(config.targets) * length(config.packet_types)} packets/sec

    ───────────────────────────────────────────────────────────────
    Starting telemetry generation... Press Ctrl+C to stop.
    ───────────────────────────────────────────────────────────────
    """)
  end

  defp format_output(:pubsub), do: "PubSub only"
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
    stats = Cadence.Simulator.PacketSimulator.stats(pid)
    elapsed = System.monotonic_time(:second) - start_time

    # Calculate actual rate
    actual_rate = if elapsed > 0, do: stats.packet_count / elapsed, else: 0.0

    Mix.shell().info(
      "[#{format_elapsed(elapsed)}] " <>
        "Packets: #{format_number(stats.packet_count)} | " <>
        "Rate: #{format_rate(actual_rate)} pkt/s | " <>
        "Cycles: #{format_number(stats.cycle_count)}"
    )
  end

  defp cleanup(pid, start_time) do
    # Get final stats before stopping
    stats = Cadence.Simulator.PacketSimulator.stats(pid)
    elapsed = System.monotonic_time(:second) - start_time

    # Stop simulator
    Cadence.Simulator.PacketSimulator.stop(pid)

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
    Total Cycles:    #{format_number(stats.cycle_count)}
    Average Rate:    #{format_rate(avg_rate)} packets/sec
    Targets:         #{stats.targets}
    Packet Types:    #{Enum.join(stats.packet_types, ", ")}

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
      --interface-id, -i <uuid>  Interface UUID for write protocol chain (e.g., CRC)
      --targets, -t <list>       Comma-separated target IDs (default: sim-target-1)
      --rate, -r <float>         Packet rate in Hz per target (default: 1.0, max: 10000)
      --duration, -d <seconds>   Duration in seconds, 0=infinite (default: 0)
      --packet-types <list>      Types: health,attitude,power (default: all)
      --encoding <format>        Format: json or ccsds (default: json)
      --output <mode>            Output: pubsub, tcp:host:port, udp:host:port
      --help, -h                 Show this help

    Rate Modes:
      Rates up to 1000 Hz use standard timing (1 packet per timer tick).
      Rates above 1000 Hz use burst mode (multiple packets per 1ms tick).

    Examples:
      # Basic simulation
      mix cadence.simulate --mission-id a1b2c3d4-...

      # High-rate multi-target test
      mix cadence.simulate -m a1b2c3d4-... -t SAT-1,SAT-2,SAT-3 -r 10 -d 60

      # High-throughput stress test (5000 packets/sec)
      mix cadence.simulate -m a1b2c3d4-... -r 5000 --output tcp:localhost:9999

      # CCSDS encoding with TCP output
      mix cadence.simulate -m a1b2c3d4-... --encoding ccsds --output tcp:localhost:9999

      # With CRC from interface write chain
      mix cadence.simulate -m a1b2c3d4-... -i b2c3d4e5-... --encoding ccsds
    """)
  end
end
