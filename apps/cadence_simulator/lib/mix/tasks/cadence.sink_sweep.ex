defmodule Mix.Tasks.Cadence.SinkSweep do
  @moduledoc """
  Runs a stepped simulator rate sweep against a local dumb TCP drain sink.
  """

  use Mix.Task

  alias Cadence.DevProfile
  alias CadenceSimulator.{CLI, DrainSink, SinkSweep}

  @shortdoc "Sweep simulator rates against a dumb local TCP sink"

  @default_settle_seconds 2
  @default_sample_seconds 8

  @impl true
  def run(args) do
    {profile_identifier, option_args} = extract_profile_identifier(args)

    {opts, simulator_args, invalid} =
      OptionParser.parse(
        option_args,
        strict: [
          rates: :string,
          settle_seconds: :integer,
          sample_seconds: :integer,
          sink_host: :string,
          sink_port: :integer,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    if opts[:help] || invalid != [] do
      print_help()

      if invalid != [] do
        Mix.raise("Invalid options: #{inspect(invalid)}")
      end

      System.halt(0)
    end

    rates = validate_rates!(opts)
    settle_seconds = validate_positive_integer!(opts[:settle_seconds] || @default_settle_seconds, "--settle-seconds")
    sample_seconds = validate_positive_integer!(opts[:sample_seconds] || @default_sample_seconds, "--sample-seconds")

    {:ok, _started} = Application.ensure_all_started(:cadence_simulator)

    with {:ok, runtime_opts} <- resolve_simulator_runtime_opts(profile_identifier, simulator_args),
         {:ok, sink_runtime_opts} <- resolve_tcp_output(runtime_opts, opts),
         {:ok, sink_pid} <- start_sink(sink_runtime_opts),
         {:ok, simulator_pid} <-
           CadenceSimulator.start_simulator(Keyword.delete(sink_runtime_opts, :runtime_mode)) do
      try do
        print_header()

        Enum.each(rates, fn rate_hz ->
          :ok = CadenceSimulator.set_simulator_rate(simulator_pid, rate_hz)
          Process.sleep(settle_seconds * 1000)
          simulator_before = CadenceSimulator.simulator_stats(simulator_pid)
          sink_before = DrainSink.stats(sink_pid)
          Process.sleep(sample_seconds * 1000)
          simulator_after = CadenceSimulator.simulator_stats(simulator_pid)
          sink_after = DrainSink.stats(sink_pid)

          print_summary(
            SinkSweep.build_summary(
              rate_hz,
              sample_seconds,
              simulator_before,
              simulator_after,
              sink_before,
              sink_after
            )
          )
        end)
      after
        if Process.alive?(simulator_pid), do: CadenceSimulator.stop_simulator(simulator_pid)
        if Process.alive?(sink_pid), do: DrainSink.stop(sink_pid)
      end
    else
      {:help, usage} ->
        Mix.shell().info(usage)
        System.halt(0)

      {:error, reason} when is_binary(reason) ->
        Mix.raise(reason)

      {:error, reason} ->
        Mix.raise("Failed to start sink sweep: #{inspect(reason)}")
    end
  end

  defp validate_simulator_opts!(simulator_args) do
    case CLI.parse_args(simulator_args) do
      {:ok, opts} ->
        if opts[:runtime_mode] == :telemetry do
          opts
        else
          Mix.raise("Sink sweep only supports telemetry simulator mode")
        end

      {:help, usage} ->
        Mix.shell().info(usage)
        System.halt(0)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp validate_rates!(opts) do
    case opts[:rates] do
      nil ->
        Mix.raise("Missing required option: --rates")

      rates_string ->
        case CadenceSimulator.ProfileSweep.parse_rates(rates_string) do
          {:ok, rates} -> rates
          {:error, message} -> Mix.raise(message)
        end
    end
  end

  defp validate_positive_integer!(value, _label) when is_integer(value) and value > 0, do: value
  defp validate_positive_integer!(_value, label), do: Mix.raise("#{label} must be a positive integer")

  defp resolve_simulator_runtime_opts(nil, simulator_args) do
    {:ok, validate_simulator_opts!(simulator_args)}
  end

  defp resolve_simulator_runtime_opts(profile_identifier, simulator_args)
       when is_binary(profile_identifier) do
    with {:ok, profile} <- DevProfile.load(profile_identifier),
         {:ok, parsed_runtime_opts} <- parse_profile_runtime_opts(profile, simulator_args) do
      {:ok, parsed_runtime_opts}
    end
  end

  defp parse_profile_runtime_opts(profile, simulator_args) do
    cli_args = ["--config", DevProfile.simulator_config_path(profile) | simulator_args]

    case CLI.parse_args(cli_args) do
      {:ok, opts} ->
        if opts[:runtime_mode] == :telemetry do
          {:ok, DevProfile.resolve_runtime_opts(profile, opts)}
        else
          {:error, "profile #{profile.name} resolves to #{inspect(opts[:runtime_mode])} mode, but :telemetry is required"}
        end

      {:help, usage} ->
        {:help, usage}

      {:error, message} ->
        {:error, message}
    end
  end

  defp resolve_tcp_output(runtime_opts, opts) do
    sink_host = opts[:sink_host]
    sink_port = opts[:sink_port]

    resolved_runtime_opts =
      case Keyword.get(runtime_opts, :output) do
        {:tcp, host, port} ->
          host = sink_host || host
          port = sink_port || port
          Keyword.put(runtime_opts, :output, {:tcp, host, port})

        nil when is_binary(sink_host) and is_integer(sink_port) ->
          Keyword.put(runtime_opts, :output, {:tcp, sink_host, sink_port})

        nil when is_integer(sink_port) ->
          Keyword.put(runtime_opts, :output, {:tcp, "127.0.0.1", sink_port})

        _other ->
          runtime_opts
      end

    case Keyword.get(resolved_runtime_opts, :output) do
      {:tcp, host, port} when is_binary(host) and is_integer(port) and port > 0 ->
        {:ok, Keyword.put(resolved_runtime_opts, :output, {:tcp, host, port})}

      _other ->
        {:error,
         "sink sweep requires a direct TCP output. Pass a profile with simulator.output.tcp or override with --sink-port/--sink-host."}
    end
  end

  defp start_sink(runtime_opts) do
    {:tcp, host, port} = Keyword.fetch!(runtime_opts, :output)

    case DrainSink.start_link(host: host, port: port) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, "Failed to start TCP drain sink on #{host}:#{port}: #{inspect(reason)}"}
    end
  end

  defp print_header do
    Mix.shell().info(
      " rate_hz  sim(tx/s/mbps/q/fl/sz_kb)  sink(rx/mbps/ch_s/acc/open)  sim_ms(gen/fr/send)"
    )
  end

  defp print_summary(summary) do
    Mix.shell().info(
      String.pad_leading(format_number(summary.rate_hz, 1), 8) <>
        "  " <>
        format_number(summary.simulator_tx_per_sec, 1) <>
        "/" <>
        format_number(summary.simulator_mbps, 2) <>
        "/" <>
        Integer.to_string(summary.simulator_queue_depth) <>
        "/" <>
        format_number(summary.simulator_flushes_per_sec, 1) <>
        "/" <>
        format_number(summary.simulator_kb_per_flush, 1) <>
        "  " <>
        format_number(summary.sink_mbps, 2) <>
        "/" <>
        format_number(summary.sink_chunks_per_sec, 1) <>
        "/" <>
        Integer.to_string(summary.sink_accepted_connections) <>
        "/" <>
        Integer.to_string(summary.sink_open_connections) <>
        "  " <>
        format_number(summary.simulator_generation_ms, 2) <>
        "/" <>
        format_number(summary.simulator_framing_ms, 2) <>
        "/" <>
        format_number(summary.simulator_send_ms, 2)
    )
  end

  defp format_number(number, decimals) when is_number(number) do
    :erlang.float_to_binary(number * 1.0, decimals: decimals)
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.sink_sweep - Sweep telemetry simulator rates against a local dumb TCP sink

    Usage:
      mix cadence.sink_sweep PROFILE [options] [-- simulator overrides]
      mix cadence.sink_sweep [options] -- [telemetry simulator args]

    Required:
      --rates <csv>             Comma-separated telemetry rates in Hz

    Optional:
      --settle-seconds <n>      Time to wait after changing rate (default: #{@default_settle_seconds})
      --sample-seconds <n>      Time to sample each rate (default: #{@default_sample_seconds})
      --sink-host <host>        Override the simulator TCP sink host
      --sink-port <port>        Override the simulator TCP sink port
      --help, -h                Show this help

    Profile mode:
      Pass a named dev profile first, for example `demo_spacecraft`. Any telemetry
      simulator overrides may be passed after `--`.

    Advanced mode:
      Omit PROFILE and pass the same telemetry-mode arguments used by
      cadence_simulator after `--`. A direct TCP output is required.

    Example:
      mix cadence.sink_sweep demo_spacecraft --rates 800,1600,3200 --sink-port 4200

      mix cadence.sink_sweep demo_spacecraft --rates 800,1600,3200 --sink-port 4200 -- \\
        --tm-worker-fast-path --metrics-sample-rate 0
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
