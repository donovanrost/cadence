defmodule Mix.Tasks.Cadence.ProfileSweep do
  @moduledoc """
  Runs a stepped simulator rate sweep while sampling a running Cadence node's
  downlink profiler.

  Simulator telemetry arguments must be passed after `--` and use the same
  format as `cadence_simulator telemetry`.

  Example:

      mix cadence.profile_sweep --node cadence --mission-id mission-alpha \\
        --rates 5,10,25,50 --settle-seconds 2 --sample-seconds 8 -- \\
        --config priv/simulator/downlink.yaml
  """

  use Mix.Task

  alias CadenceSimulator.{CLI, DevTools, ProfileSweep}

  @shortdoc "Sweep simulator rates against a running Cadence profiler"

  @default_settle_seconds 2
  @default_sample_seconds 8

  @impl true
  def run(args) do
    {profile_identifier, option_args} = extract_profile_identifier(args)

    profile_defaults =
      case profile_identifier do
        nil ->
          %{node: nil, mission_id: nil}

        identifier ->
          case DevTools.profiler_defaults(identifier) do
            {:ok, defaults} -> defaults
            {:error, message} -> Mix.raise(message)
          end
      end

    {opts, simulator_args, invalid} =
      OptionParser.parse(
        option_args,
        strict: [
          node: :string,
          mission_id: :string,
          rates: :string,
          settle_seconds: :integer,
          sample_seconds: :integer,
          help: :boolean
        ],
        aliases: [
          n: :node,
          m: :mission_id,
          h: :help
        ]
      )

    if opts[:help] || invalid != [] do
      print_help()

      if invalid != [] do
        Mix.raise("Invalid options: #{inspect(invalid)}")
      end

      System.halt(0)
    end

    node_name = validate_node!(opts, profile_defaults.node)
    mission_id = validate_mission_id!(opts, profile_defaults.mission_id)
    rates = validate_rates!(opts)
    settle_seconds = validate_positive_integer!(opts[:settle_seconds] || @default_settle_seconds, "--settle-seconds")
    sample_seconds = validate_positive_integer!(opts[:sample_seconds] || @default_sample_seconds, "--sample-seconds")

    start_distribution()
    connect_to_node(node_name)

    {:ok, _started} = Application.ensure_all_started(:cadence_simulator)

    with {:ok, resolved_runtime_opts} <-
           resolve_simulator_runtime_opts(profile_identifier, simulator_args),
         {:ok, simulator_pid} <-
           CadenceSimulator.start_simulator(Keyword.delete(resolved_runtime_opts, :runtime_mode)) do
      try do
        print_header()

        Enum.each(rates, fn rate_hz ->
          :ok = CadenceSimulator.set_simulator_rate(simulator_pid, rate_hz)
          Process.sleep(settle_seconds * 1000)
          simulator_before = CadenceSimulator.simulator_stats(simulator_pid)
          :ok = rpc_call!(node_name, Cadence.Telemetry.Profiler, :reset, [mission_id])
          Process.sleep(sample_seconds * 1000)
          snapshot = rpc_call!(node_name, Cadence.Telemetry.Profiler, :snapshot, [mission_id])
          simulator_after = CadenceSimulator.simulator_stats(simulator_pid)

          print_summary(
            ProfileSweep.build_summary(
              rate_hz,
              snapshot,
              sample_seconds,
              simulator_before,
              simulator_after
            )
          )
        end)
      after
        if Process.alive?(simulator_pid), do: CadenceSimulator.stop_simulator(simulator_pid)
      end
    else
      {:error, reason} ->
        Mix.raise("Failed to start sweep simulator: #{inspect(reason)}")
    end
  end

  defp validate_simulator_opts!(simulator_args) do
    case CLI.parse_args(simulator_args) do
      {:ok, opts} ->
        if opts[:runtime_mode] == :telemetry do
          opts
        else
          Mix.raise("Profile sweep only supports telemetry simulator mode")
        end

      {:help, usage} ->
        Mix.shell().info(usage)
        System.halt(0)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  defp validate_node!(opts, default) do
    case opts[:node] || default do
      nil -> Mix.raise("Missing required option: --node")
      name -> name |> to_string() |> ensure_node_host() |> validate_node_name!()
    end
  end

  defp validate_mission_id!(opts, default) do
    case opts[:mission_id] || default do
      mission_id when is_binary(mission_id) and mission_id != "" -> mission_id
      _other -> Mix.raise("Missing required option: --mission-id")
    end
  end

  defp validate_rates!(opts) do
    case opts[:rates] do
      nil ->
        Mix.raise("Missing required option: --rates")

      rates_string ->
        case ProfileSweep.parse_rates(rates_string) do
          {:ok, rates} -> rates
          {:error, message} -> Mix.raise(message)
        end
    end
  end

  defp validate_positive_integer!(value, _label) when is_integer(value) and value > 0, do: value
  defp validate_positive_integer!(_value, label), do: Mix.raise("#{label} must be a positive integer")

  defp print_header do
    Mix.shell().info(
      " rate_hz  ingress/s  packets/s  samples/s  avg_ms(resolve/runtime/persist/e2e)  db_q/ing  db_ms/ing  arch(q/old_ms/fl_ms/seg_kb/fail)  sim(tx/s/mbps/q/fl/sz_kb)  sim_ms(gen/fr/send)"
    )
  end

  defp print_summary(summary) do
    Mix.shell().info(
      String.pad_leading(format_number(summary.rate_hz, 1), 8) <>
        String.pad_leading(format_number(summary.ingress_per_sec, 1), 11) <>
        String.pad_leading(format_number(summary.packets_per_sec, 1), 11) <>
        String.pad_leading(format_number(summary.samples_per_sec, 1), 11) <>
        "  " <>
        format_number(summary.resolve_ms, 2) <>
        "/" <>
        format_number(summary.runtime_ms, 2) <>
        "/" <>
        format_number(summary.persist_ms, 2) <>
        "/" <>
        format_number(summary.e2e_ms, 2) <>
        String.pad_leading(format_number(summary.db_queries_per_ingress, 1), 11) <>
        String.pad_leading(format_number(summary.db_ms_per_ingress, 2), 11) <>
        "  " <>
        Integer.to_string(summary.archive_queue_depth) <>
        "/" <>
        Integer.to_string(summary.archive_oldest_buffered_age_ms) <>
        "/" <>
        format_number(summary.archive_avg_flush_ms, 2) <>
        "/" <>
        format_number(summary.archive_avg_segment_kb, 1) <>
        "/" <>
        Integer.to_string(summary.archive_flush_failures) <>
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
        format_number(summary.simulator_generation_ms, 2) <>
        "/" <>
        format_number(summary.simulator_framing_ms, 2) <>
        "/" <>
        format_number(summary.simulator_send_ms, 2)
    )
  end

  defp start_distribution do
    local_node = :"profile_sweep_#{System.unique_integer([:positive])}@#{hostname()}"

    case Node.start(local_node, :shortnames) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Failed to start distributed node: #{inspect(reason)}")
    end

    maybe_set_distribution_cookie()
  end

  defp connect_to_node(target_node) do
    Mix.shell().info("Connecting to #{target_node}...")

    case Node.connect(target_node) do
      true -> Mix.shell().info("Connected successfully.\n")

      false ->
        Mix.raise("""
        Failed to connect to #{target_node}.

        Make sure the server is running with a node name, for example:
          iex --sname cadence -S mix phx.server

        If the server was started with a non-default Erlang cookie, set the
        same cookie in `CADENCE_NODE_COOKIE` before running this task.
        """)

      :ignored -> Mix.raise("Local sweep node is not alive.")
    end
  end

  defp rpc_call!(node, module, function, args) do
    case :rpc.call(node, module, function, args) do
      {:badrpc, reason} -> Mix.raise("RPC failed: #{inspect(reason)}")
      result -> result
    end
  end

  defp ensure_node_host(name) do
    if String.contains?(name, "@"), do: name, else: "#{name}@#{hostname()}"
  end

  defp validate_node_name!(name) when is_binary(name) do
    if byte_size(name) <= 128 and Regex.match?(~r/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$/, name) do
      String.to_atom(name)
    else
      Mix.raise("Invalid node name: #{inspect(name)}")
    end
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

  defp format_number(number, decimals) when is_number(number) do
    :erlang.float_to_binary(number * 1.0, decimals: decimals)
  end

  defp resolve_simulator_runtime_opts(nil, simulator_args) do
    simulator_opts = validate_simulator_opts!(simulator_args)

    CadenceSimulator.CadenceRuntimeBootstrap.resolve_runtime_opts(simulator_opts)
  end

  defp resolve_simulator_runtime_opts(profile_identifier, simulator_args)
       when is_binary(profile_identifier) do
    case DevTools.resolve_profile_runtime(profile_identifier, simulator_args, runtime_mode: :telemetry) do
      {:ok, %{runtime_opts: runtime_opts}} ->
        {:ok, runtime_opts}

      {:help, usage} ->
        Mix.shell().info(usage)
        System.halt(0)

      {:error, reason} when is_binary(reason) ->
        Mix.raise(reason)

      {:error, reason} ->
        Mix.raise("Failed to start sweep simulator: #{inspect(reason)}")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix cadence.profile_sweep - Sweep telemetry simulator rates against a running Cadence profiler

    Usage:
      mix cadence.profile_sweep PROFILE [options] [-- simulator overrides]
      mix cadence.profile_sweep [options] -- [telemetry simulator args]

    Required:
      --rates <csv>             Comma-separated telemetry rates in Hz

    Optional:
      --node, -n <name>         Running Cadence node name (or use the profile default)
      --mission-id, -m <id>     Mission identifier to profile (or use the profile default)
      --settle-seconds <n>      Time to wait after changing rate (default: #{@default_settle_seconds})
      --sample-seconds <n>      Time to sample each rate after reset (default: #{@default_sample_seconds})
      --help, -h                Show this help

    Profile mode:
      Pass a named dev profile first, for example `demo_spacecraft`. Any telemetry
      simulator overrides may be passed after `--`.

    Advanced mode:
      Omit PROFILE and pass the same telemetry-mode arguments used by
      cadence_simulator after `--`.

    Example:
      mix cadence.profile_sweep demo_spacecraft --rates 5,10,25,50

      mix cadence.profile_sweep demo_spacecraft --rates 5,10,25,50 -- --rate 25.0

      mix cadence.profile_sweep --node cadence --mission-id mission-alpha \\
        --rates 5,10,25,50 --settle-seconds 2 --sample-seconds 8 -- \\
        --config priv/simulator/downlink.yaml
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
