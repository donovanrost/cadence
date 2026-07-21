defmodule CadenceSimulator.CLI do
  @moduledoc """
  Thin executable entrypoint for running the simulator as its own app.
  """

  alias CadenceSimulator.CadenceRuntimeBootstrap
  alias CadenceSimulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}

  @telemetry_switches [
    config: :string,
    cadence_url: :string,
    api_token: :string,
    organization_id: :string,
    mission_id: :string,
    realized_contact_id: :string,
    path_id: :string,
    provider_binding_id: :string,
    transport_binding_id: :string,
    target: :string,
    definitions: :string,
    rate: :float,
    tcp: :string,
    udp: :string,
    provider: :string,
    scenario: :string,
    noise_amplitude: :float,
    tm_frame_size: :integer,
    scid: :integer,
    vcid: :integer,
    fecf: :boolean,
    parallel: :boolean,
    tm_parallel_framing: :boolean,
    generator_count: :integer,
    metrics_sample_rate: :integer,
    send_batch_timeout: :integer,
    send_batch_size: :integer,
    help: :boolean
  ]
  @telemetry_aliases [t: :target, d: :definitions, r: :rate, h: :help]

  @loopback_switches [
    config: :string,
    cadence_url: :string,
    api_token: :string,
    organization_id: :string,
    mission_id: :string,
    realized_contact_id: :string,
    path_id: :string,
    provider_binding_id: :string,
    transport_binding_id: :string,
    tcp: :string,
    tc_frame_size: :integer,
    segment_header_flag: :integer,
    fecf: :boolean,
    clcw_overrides: :keep,
    clcw_schedule: :keep,
    help: :boolean
  ]
  @loopback_aliases [h: :help]

  @runtime_modes %{
    "telemetry" => :telemetry,
    "cop1_loopback" => :cop1_loopback
  }

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case parse_args(args) do
      {:help, usage} ->
        IO.puts(usage)
        System.halt(0)

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)

      {:ok, opts} ->
        run!(opts)
    end
  end

  @spec parse_args([String.t()]) :: {:ok, keyword()} | {:help, String.t()} | {:error, String.t()}
  def parse_args(["--help"]), do: {:help, usage()}
  def parse_args(["-h"]), do: {:help, usage()}

  def parse_args(args) when is_list(args) do
    with {:ok, runtime_mode, mode_args, config_root} <- resolve_runtime_mode(args) do
      parse_mode_args(runtime_mode, mode_args, config_root)
    end
  end

  @spec usage() :: String.t()
  def usage do
    """
    Usage:
      cadence_simulator --config PATH
      cadence_simulator [telemetry] --definitions PATH [options]
      cadence_simulator cop1_loopback --tcp HOST:PORT --tc-frame-size BYTES [options]

    Runtime Modes:
      telemetry      Generate downlink packet or TM frame output (default)
      cop1_loopback  Connect to a TCP uplink provider and reply with CLCW reports

    Run `cadence_simulator telemetry --help` or
    `cadence_simulator cop1_loopback --help` for mode-specific options.
    """
  end

  defp usage(:telemetry) do
    """
    Usage:
      cadence_simulator [telemetry] --config PATH [options]
      cadence_simulator [telemetry] --definitions PATH [options]

    Required:
      --definitions, -d        Path to the legacy Cadence dev YAML database

    Output:
      --tcp HOST:PORT          Connect to a TCP endpoint
      --udp HOST:PORT          Send to a UDP endpoint

    Provider:
      --provider NAME          basic | database | scenario (default: database)
      --scenario PATH          Scenario file path for the scenario provider
      --noise-amplitude VALUE  Database dynamics noise amplitude

    Framing:
      --tm-frame-size BYTES    Wrap generated packets into TM transfer frames
      --scid VALUE             TM SCID (default: 0)
      --vcid VALUE             TM VCID (default: 0)
      --fecf                   Generate the managed TM Frame Error Control Field

    Cadence Bootstrap:
      --cadence-url URL        Resolve path runtime socket info from Cadence
      --api-token TOKEN        Bearer token for the Cadence API
      --organization-id ID     Organization scope for runtime lookup
      --mission-id ID          Mission scope for runtime lookup
      --realized-contact-id ID Realized contact to inspect
      --path-id ID             Path runtime to inspect
      --provider-binding-id ID Select one provider runtime when a path has many

    Performance:
      --parallel               Enable concurrent packet generation; with --generator-count 1 this behaves sequentially
      --tm-parallel-framing    Plan TM frame payloads in workers before ordered framing emit
      --generator-count N      Parallel worker count
      --metrics-sample-rate N  Record hot-path timings every Nth sample (default: 100, 0 disables)
      --send-batch-timeout MS  Send buffer flush timeout
      --send-batch-size BYTES  Send buffer flush size

    General:
      --config PATH           Load a simulator run profile from YAML
      --target, -t             Target/source-endpoint identifier (default: SIM-1)
      --rate, -r               Generation rate in Hz (default: 1.0)
      --help, -h               Show this help
    """
  end

  defp usage(:cop1_loopback) do
    """
    Usage:
      cadence_simulator cop1_loopback --config PATH [options]
      cadence_simulator cop1_loopback --tcp HOST:PORT --tc-frame-size BYTES [options]

    Required:
      --tcp HOST:PORT          TCP uplink provider socket to connect to
      --tc-frame-size BYTES    Maximum TC transfer frame size accepted on the socket

    TC Data Link:
      --segment-header-flag N  Managed Segment Header presence for the VC: 0 or 1
      --fecf                   Validate the managed TC Frame Error Control Field

    CLCW Injection:
      --clcw-overrides SPEC    Static CLCW overrides as KEY=VALUE[,KEY=VALUE...]
      --clcw-schedule SPEC     Step-based overrides as STEP:KEY=VALUE[,KEY=VALUE...]

    Cadence Bootstrap:
      --cadence-url URL        Resolve path runtime socket info from Cadence
      --api-token TOKEN        Bearer token for the Cadence API
      --organization-id ID     Organization scope for runtime lookup
      --mission-id ID          Mission scope for runtime lookup
      --realized-contact-id ID Realized contact to inspect
      --path-id ID             Path runtime to inspect
      --provider-binding-id ID Select one provider runtime when a path has many
      --transport-binding-id ID Select one uplink transport runtime when a path has many

    General:
      --config PATH           Load a simulator run profile from YAML
      --help, -h               Show this help
    """
  end

  defp run!(opts) do
    run_runtime!(opts)
  end

  defp run_runtime!(opts) do
    {:ok, _started} = Application.ensure_all_started(:cadence_simulator)

    case CadenceRuntimeBootstrap.resolve_runtime_opts(opts) do
      {:ok, resolved_opts} ->
        do_run!(resolved_opts)

      {:error, reason} ->
        IO.puts(:stderr, "failed to resolve simulator bootstrap: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp do_run!(opts) do
    case start_runtime(opts) do
      {:ok, pid} ->
        IO.puts("cadence_simulator started in #{opts[:runtime_mode]} mode")
        {:ok, _reason} = CadenceSimulator.await_simulator(pid)
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "failed to start simulator: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp resolve_runtime_mode(args) do
    {explicit_runtime_mode, mode_args} = parse_runtime_mode(args)

    with {:ok, config_root} <- maybe_load_config_root(mode_args),
         {:ok, runtime_mode} <- resolve_runtime_mode_value(explicit_runtime_mode, config_root) do
      {:ok, runtime_mode, mode_args, config_root}
    end
  end

  defp parse_runtime_mode([candidate | rest]) do
    case @runtime_modes do
      %{^candidate => runtime_mode} -> {runtime_mode, rest}
      _other -> {nil, [candidate | rest]}
    end
  end

  defp parse_runtime_mode([]), do: {nil, []}

  defp parse_mode_args(:telemetry, args, config_root) do
    {parsed, positional, invalid} =
      OptionParser.parse(args, strict: @telemetry_switches, aliases: @telemetry_aliases)

    cond do
      parsed[:help] ->
        {:help, usage(:telemetry)}

      invalid != [] ->
        {:error,
         "invalid telemetry options: #{format_invalid_options(invalid)}\n\n" <> usage(:telemetry)}

      positional != [] ->
        {:error,
         "unexpected telemetry arguments: #{Enum.join(positional, " ")}\n\n" <> usage(:telemetry)}

      true ->
        case merge_config(parsed, :telemetry, config_root) do
          {:ok, merged_parsed} ->
            with_usage(build_telemetry_options(merged_parsed), :telemetry)

          {:error, message} ->
            {:error, message <> "\n\n" <> usage(:telemetry)}
        end
    end
  end

  defp parse_mode_args(:cop1_loopback, args, config_root) do
    {parsed, positional, invalid} =
      OptionParser.parse(args, strict: @loopback_switches, aliases: @loopback_aliases)

    cond do
      parsed[:help] ->
        {:help, usage(:cop1_loopback)}

      invalid != [] ->
        {:error,
         "invalid cop1_loopback options: #{format_invalid_options(invalid)}\n\n" <>
           usage(:cop1_loopback)}

      positional != [] ->
        {:error,
         "unexpected cop1_loopback arguments: #{Enum.join(positional, " ")}\n\n" <>
           usage(:cop1_loopback)}

      true ->
        case merge_config(parsed, :cop1_loopback, config_root) do
          {:ok, merged_parsed} ->
            with_usage(build_loopback_options(merged_parsed), :cop1_loopback)

          {:error, message} ->
            {:error, message <> "\n\n" <> usage(:cop1_loopback)}
        end
    end
  end

  defp build_telemetry_options(parsed) do
    with {:ok, definitions_path} <-
           require_string(parsed, :definitions, "--definitions is required"),
         {:ok, provider} <- parse_provider(parsed[:provider] || default_provider(parsed)),
         {:ok, output} <- parse_output(parsed),
         {:ok, frame} <- parse_frame(parsed),
         {:ok, provider_opts} <- provider_opts(provider, parsed) do
      opts =
        [
          runtime_mode: :telemetry,
          target_id: parsed[:target] || "SIM-1",
          rate_hz: parsed[:rate] || 1.0,
          definitions_path: definitions_path,
          provider: provider,
          parallel_mode: if(parsed[:parallel], do: :parallel, else: :sequential)
        ]
        |> maybe_put(:output, output)
        |> maybe_put(:frame, frame)
        |> maybe_put(:tm_parallel_framing, parsed[:tm_parallel_framing])
        |> maybe_put(:generator_count, parsed[:generator_count])
        |> maybe_put(:metrics_sample_rate, parsed[:metrics_sample_rate])
        |> maybe_put(:send_batch_timeout, parsed[:send_batch_timeout])
        |> maybe_put(:send_batch_size, parsed[:send_batch_size])
        |> Keyword.merge(cadence_bootstrap_opts(parsed))
        |> Keyword.merge(provider_opts)

      {:ok, opts}
    end
  end

  defp build_loopback_options(parsed) do
    with {:ok, output} <- optional_tcp_output(parsed),
         {:ok, tc_frame_size} <- optional_positive_integer_value(parsed[:tc_frame_size]),
         {:ok, segment_header_flag} <-
           optional_flag_value(parsed[:segment_header_flag], "--segment-header-flag"),
         {:ok, fecf?} <- optional_boolean_value(parsed[:fecf], "--fecf"),
         {:ok, clcw_overrides} <-
           parse_clcw_overrides(Keyword.get_values(parsed, :clcw_overrides)),
         {:ok, clcw_schedule} <- parse_clcw_schedule(Keyword.get_values(parsed, :clcw_schedule)) do
      bootstrap_opts = cadence_bootstrap_opts(parsed)

      opts =
        [runtime_mode: :cop1_loopback]
        |> maybe_put(:host, output && elem(output, 1))
        |> maybe_put(:port, output && elem(output, 2))
        |> maybe_put(:tc_frame_size, tc_frame_size)
        |> maybe_put(:segment_header_flag, segment_header_flag)
        |> maybe_put(:fecf, fecf?)
        |> maybe_put(:clcw_overrides, if(clcw_overrides == %{}, do: nil, else: clcw_overrides))
        |> maybe_put(:clcw_schedule, if(clcw_schedule == [], do: nil, else: clcw_schedule))
        |> Keyword.merge(bootstrap_opts)

      cond do
        Keyword.has_key?(bootstrap_opts, :cadence_url) ->
          {:ok, opts}

        is_nil(output) ->
          {:error, "--tcp is required"}

        is_nil(tc_frame_size) ->
          {:error, "--tc-frame-size is required"}

        true ->
          {:ok, opts}
      end
    end
  end

  defp start_runtime(runtime_opts) do
    case Keyword.fetch!(runtime_opts, :runtime_mode) do
      :telemetry ->
        CadenceSimulator.start_simulator(Keyword.delete(runtime_opts, :runtime_mode))

      :cop1_loopback ->
        CadenceSimulator.start_cop1_loopback_peer(Keyword.delete(runtime_opts, :runtime_mode))
    end
  end

  defp default_provider(parsed) do
    if parsed[:scenario], do: "scenario", else: "database"
  end

  defp require_string(parsed, key, error_message) do
    case parsed[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, error_message}
    end
  end

  defp optional_positive_integer_value(nil), do: {:ok, nil}

  defp optional_positive_integer_value(value) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp optional_positive_integer_value(_value),
    do: {:error, "--tc-frame-size must be a positive integer"}

  defp optional_flag_value(nil, _option), do: {:ok, nil}
  defp optional_flag_value(value, _option) when value in [0, 1], do: {:ok, value}

  defp optional_flag_value(_value, option),
    do: {:error, "#{option} must be 0 or 1"}

  defp optional_boolean_value(nil, _option), do: {:ok, nil}
  defp optional_boolean_value(value, _option) when is_boolean(value), do: {:ok, value}

  defp optional_boolean_value(_value, option),
    do: {:error, "#{option} must be true or false"}

  defp parse_provider("basic"), do: {:ok, BasicDynamics}
  defp parse_provider("database"), do: {:ok, DatabaseDynamics}
  defp parse_provider("scenario"), do: {:ok, ScenarioProvider}
  defp parse_provider(other), do: {:error, "unsupported provider: #{inspect(other)}"}

  defp parse_output(parsed) do
    case {parsed[:tcp], parsed[:udp]} do
      {nil, nil} -> {:ok, nil}
      {tcp, nil} -> parse_socket_target(tcp, :tcp)
      {nil, udp} -> parse_socket_target(udp, :udp)
      {_tcp, _udp} -> {:error, "choose only one of --tcp or --udp"}
    end
  end

  defp optional_tcp_output(parsed) do
    case {parsed[:tcp], parsed[:udp]} do
      {nil, nil} -> {:ok, nil}
      {tcp, nil} when is_binary(tcp) -> parse_socket_target(tcp, :tcp)
      {nil, _udp} -> {:error, "cop1_loopback only supports --tcp"}
      {_tcp, _udp} -> {:error, "choose only one of --tcp or --udp"}
    end
  end

  defp parse_socket_target(target, protocol) when is_binary(target) do
    case String.split(target, ":", parts: 2) do
      [host, port_string] ->
        case Integer.parse(port_string) do
          {port, ""} when port > 0 -> {:ok, {protocol, host, port}}
          _ -> {:error, "invalid #{protocol} target port: #{inspect(target)}"}
        end

      _ ->
        {:error, "invalid #{protocol} target, expected HOST:PORT"}
    end
  end

  defp parse_frame(parsed) when is_list(parsed) do
    if is_nil(parsed[:tm_frame_size]) do
      {:ok, nil}
    else
      do_parse_frame(parsed)
    end
  end

  defp do_parse_frame(parsed) do
    frame_size = parsed[:tm_frame_size]

    if is_integer(frame_size) and frame_size > 0 do
      {:ok,
       %{
         format: :tm,
         frame_size: frame_size,
         scid: parsed[:scid] || 0,
         vcid: parsed[:vcid] || 0,
         fecf: parsed[:fecf] || false
       }}
    else
      {:error, "--tm-frame-size must be a positive integer"}
    end
  end

  defp provider_opts(ScenarioProvider, parsed) do
    case parsed[:scenario] do
      value when is_binary(value) and value != "" -> {:ok, [scenario_path: value]}
      _ -> {:error, "--scenario is required when --provider scenario is used"}
    end
  end

  defp provider_opts(DatabaseDynamics, parsed) do
    {:ok, maybe_put([], :noise_amplitude, parsed[:noise_amplitude])}
  end

  defp provider_opts(_provider, _parsed), do: {:ok, []}

  defp cadence_bootstrap_opts(parsed) do
    []
    |> maybe_put(:cadence_url, parsed[:cadence_url])
    |> maybe_put(:api_token, parsed[:api_token])
    |> maybe_put(:organization_id, parsed[:organization_id])
    |> maybe_put(:mission_id, parsed[:mission_id])
    |> maybe_put(:realized_contact_id, parsed[:realized_contact_id])
    |> maybe_put(:path_id, parsed[:path_id])
    |> maybe_put(:provider_binding_id, parsed[:provider_binding_id])
    |> maybe_put(:transport_binding_id, parsed[:transport_binding_id])
  end

  defp maybe_load_config_root(args) do
    with {:ok, config_path} <- extract_config_path(args) do
      case config_path do
        nil -> {:ok, nil}
        path -> load_config_root(path)
      end
    end
  end

  defp extract_config_path([]), do: {:ok, nil}

  defp extract_config_path(["--config"]), do: {:error, "--config requires PATH"}

  defp extract_config_path(["--config", path | _rest]) when is_binary(path) and path != "" do
    {:ok, path}
  end

  defp extract_config_path([<<"--config=", path::binary>> | _rest]) when path != "" do
    {:ok, path}
  end

  defp extract_config_path([_arg | rest]), do: extract_config_path(rest)

  defp load_config_root(path) when is_binary(path) do
    with {:ok, yaml_content} <- File.read(path),
         {:ok, parsed} <- YamlElixir.read_from_string(yaml_content),
         {:ok, config_root} <- normalize_config_root(parsed) do
      {:ok, Map.put(config_root, "__config_path__", path)}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "failed to load simulator config #{inspect(path)}: #{inspect(reason)}"}
    end
  end

  defp normalize_config_root(%{} = parsed) do
    case fetch_map_value(parsed, ["simulator"]) do
      nil -> {:ok, parsed}
      %{} = simulator_root -> {:ok, simulator_root}
    end
  end

  defp normalize_config_root(_parsed), do: {:error, "simulator config must be a YAML map"}

  defp resolve_runtime_mode_value(runtime_mode, _config_root)
       when runtime_mode in [:telemetry, :cop1_loopback],
       do: {:ok, runtime_mode}

  defp resolve_runtime_mode_value(nil, nil), do: {:ok, :telemetry}

  defp resolve_runtime_mode_value(nil, config_root) do
    case config_runtime_mode(config_root) do
      {:ok, nil} -> {:ok, :telemetry}
      {:ok, runtime_mode} -> {:ok, runtime_mode}
      {:error, message} -> {:error, message}
    end
  end

  defp config_runtime_mode(nil), do: {:ok, nil}

  defp config_runtime_mode(%{} = config_root) do
    case fetch_config_value(config_root, ["runtime_mode", "mode"]) do
      nil -> {:ok, nil}
      value -> parse_runtime_mode_value(value)
    end
  end

  defp parse_runtime_mode_value(value) when is_atom(value) do
    parse_runtime_mode_value(Atom.to_string(value))
  end

  defp parse_runtime_mode_value(value) when is_binary(value) do
    case @runtime_modes do
      %{^value => runtime_mode} -> {:ok, runtime_mode}
      _other -> {:error, "unsupported simulator runtime mode in config: #{inspect(value)}"}
    end
  end

  defp parse_runtime_mode_value(value),
    do: {:error, "unsupported simulator runtime mode in config: #{inspect(value)}"}

  defp merge_config(parsed, runtime_mode, config_root) do
    with {:ok, config_parsed} <- parsed_options_from_config(runtime_mode, config_root) do
      {:ok, merge_parsed_options(config_parsed, Keyword.delete(parsed, :config))}
    end
  end

  defp parsed_options_from_config(_runtime_mode, nil), do: {:ok, []}

  defp parsed_options_from_config(runtime_mode, config_root) do
    with :ok <- validate_config_runtime_mode(runtime_mode, config_root) do
      case runtime_mode do
        :telemetry -> telemetry_config_options(config_root)
        :cop1_loopback -> {:ok, loopback_config_options(config_root)}
      end
    end
  end

  defp validate_config_runtime_mode(runtime_mode, config_root) do
    case config_runtime_mode(config_root) do
      {:ok, nil} ->
        :ok

      {:ok, ^runtime_mode} ->
        :ok

      {:ok, other_runtime_mode} ->
        config_path = Map.get(config_root, "__config_path__", "<unknown>")

        {:error,
         "simulator config #{inspect(config_path)} declares #{inspect(other_runtime_mode)} mode, " <>
           "but CLI selected #{inspect(runtime_mode)}"}

      {:error, message} ->
        {:error, message}
    end
  end

  defp validate_telemetry_config(config_root) do
    if is_nil(fetch_config_value(config_root, ["tm_worker_fast_path"])) do
      :ok
    else
      {:error, "tm_worker_fast_path is no longer supported; remove it from the simulator config"}
    end
  end

  defp telemetry_config_options(config_root) do
    output = fetch_map_value(config_root, ["output"]) || %{}
    frame = fetch_map_value(config_root, ["frame"]) || %{}
    cadence = fetch_map_value(config_root, ["cadence"]) || %{}

    with :ok <- validate_telemetry_config(config_root) do
      {:ok,
       []
       |> maybe_put_config(:target, fetch_config_value(config_root, ["target", "target_id"]))
       |> maybe_put_config(
         :definitions,
         fetch_config_value(config_root, ["definitions", "definitions_path"])
       )
       |> maybe_put_config(:rate, fetch_config_value(config_root, ["rate", "rate_hz"]))
       |> maybe_put_config(:tcp, config_socket_value(config_root, output, :tcp))
       |> maybe_put_config(:udp, config_socket_value(config_root, output, :udp))
       |> maybe_put_config(:provider, fetch_config_value(config_root, ["provider"]))
       |> maybe_put_config(
         :scenario,
         fetch_config_value(config_root, ["scenario", "scenario_path"])
       )
       |> maybe_put_config(:noise_amplitude, fetch_config_value(config_root, ["noise_amplitude"]))
       |> maybe_put_config(
         :tm_frame_size,
         config_frame_value(config_root, frame, "tm_frame_size")
       )
       |> maybe_put_config(:scid, config_frame_value(config_root, frame, "scid"))
       |> maybe_put_config(:vcid, config_frame_value(config_root, frame, "vcid"))
       |> maybe_put_config(:fecf, config_frame_value(config_root, frame, "fecf"))
       |> maybe_put_config(:parallel, config_parallel_value(config_root))
       |> maybe_put_config(
         :tm_parallel_framing,
         fetch_config_value(config_root, ["tm_parallel_framing"])
       )
       |> maybe_put_config(:generator_count, fetch_config_value(config_root, ["generator_count"]))
       |> maybe_put_config(
         :metrics_sample_rate,
         fetch_config_value(config_root, ["metrics_sample_rate"])
       )
       |> maybe_put_config(
         :send_batch_timeout,
         fetch_config_value(config_root, ["send_batch_timeout"])
       )
       |> maybe_put_config(:send_batch_size, fetch_config_value(config_root, ["send_batch_size"]))
       |> Keyword.merge(cadence_bootstrap_config_options(config_root, cadence))}
    end
  end

  defp loopback_config_options(config_root) do
    clcw = fetch_map_value(config_root, ["clcw"]) || %{}
    cadence = fetch_map_value(config_root, ["cadence"]) || %{}

    []
    |> maybe_put_config(:tcp, config_socket_value(config_root, %{}, :tcp))
    |> maybe_put_config(:tc_frame_size, fetch_config_value(config_root, ["tc_frame_size"]))
    |> maybe_put_config(
      :segment_header_flag,
      fetch_config_value(config_root, ["segment_header_flag"])
    )
    |> maybe_put_config(:fecf, fetch_config_value(config_root, ["fecf"]))
    |> maybe_put_config(
      :clcw_overrides,
      fetch_config_value(config_root, ["clcw_overrides"]) ||
        fetch_config_value(clcw, ["overrides"])
    )
    |> append_config_values(
      :clcw_schedule,
      fetch_config_value(config_root, ["clcw_schedule"]) || fetch_config_value(clcw, ["schedule"])
    )
    |> Keyword.merge(cadence_bootstrap_config_options(config_root, cadence))
  end

  defp cadence_bootstrap_config_options(config_root, cadence) do
    []
    |> maybe_put_config(
      :cadence_url,
      fetch_config_value(config_root, ["cadence_url"]) ||
        fetch_config_value(cadence, ["url", "cadence_url"])
    )
    |> maybe_put_config(
      :api_token,
      fetch_config_value(config_root, ["api_token"]) || fetch_config_value(cadence, ["api_token"])
    )
    |> maybe_put_config(
      :organization_id,
      fetch_config_value(config_root, ["organization_id"]) ||
        fetch_config_value(cadence, ["organization_id"])
    )
    |> maybe_put_config(
      :mission_id,
      fetch_config_value(config_root, ["mission_id"]) ||
        fetch_config_value(cadence, ["mission_id"])
    )
    |> maybe_put_config(
      :realized_contact_id,
      fetch_config_value(config_root, ["realized_contact_id"]) ||
        fetch_config_value(cadence, ["realized_contact_id"])
    )
    |> maybe_put_config(
      :path_id,
      fetch_config_value(config_root, ["path_id"]) || fetch_config_value(cadence, ["path_id"])
    )
    |> maybe_put_config(
      :provider_binding_id,
      fetch_config_value(config_root, ["provider_binding_id"]) ||
        fetch_config_value(cadence, ["provider_binding_id"])
    )
    |> maybe_put_config(
      :transport_binding_id,
      fetch_config_value(config_root, ["transport_binding_id"]) ||
        fetch_config_value(cadence, ["transport_binding_id"])
    )
  end

  defp config_socket_value(config_root, output, protocol) do
    protocol_key = Atom.to_string(protocol)

    fetch_config_value(config_root, [protocol_key]) ||
      fetch_config_value(output, [protocol_key]) ||
      build_socket_target_from_output(output, protocol_key)
  end

  defp build_socket_target_from_output(%{} = output, protocol_key) do
    protocol = fetch_config_value(output, ["protocol"])
    host = fetch_config_value(output, ["host"])
    port = fetch_config_value(output, ["port"])

    if protocol == protocol_key and is_binary(host) and not is_nil(port) do
      "#{host}:#{port}"
    else
      nil
    end
  end

  defp build_socket_target_from_output(_output, _protocol_key), do: nil

  defp config_frame_value(config_root, frame, key) do
    fetch_config_value(config_root, [key]) ||
      case key do
        "tm_frame_size" -> fetch_config_value(frame, ["tm_frame_size", "frame_size"])
        _other -> fetch_config_value(frame, [key])
      end
  end

  defp config_parallel_value(config_root) do
    fetch_config_value(config_root, ["parallel"]) ||
      case fetch_config_value(config_root, ["parallel_mode"]) do
        "parallel" -> true
        :parallel -> true
        "sequential" -> false
        :sequential -> false
        other -> other
      end
  end

  defp merge_parsed_options(config_parsed, cli_parsed) do
    repeated_keys = [:clcw_overrides, :clcw_schedule]

    base =
      config_parsed
      |> Keyword.drop(repeated_keys)
      |> Keyword.merge(Keyword.drop(cli_parsed, repeated_keys))

    base
    |> append_repeat_values(:clcw_overrides, config_parsed, cli_parsed)
    |> append_repeat_values(:clcw_schedule, config_parsed, cli_parsed)
  end

  defp append_repeat_values(opts, key, config_parsed, cli_parsed) do
    values =
      repeat_values(config_parsed, key) ++
        repeat_values(cli_parsed, key)

    Enum.reduce(values, opts, fn value, acc -> acc ++ [{key, value}] end)
  end

  defp repeat_values(parsed, :clcw_overrides) do
    parsed
    |> Keyword.get_values(:clcw_overrides)
    |> Enum.flat_map(fn
      nil -> []
      value -> [value]
    end)
  end

  defp repeat_values(parsed, :clcw_schedule) do
    parsed
    |> Keyword.get_values(:clcw_schedule)
    |> Enum.flat_map(fn
      nil -> []
      values when is_list(values) -> values
      value -> [value]
    end)
  end

  defp maybe_put_config(opts, key, value) do
    maybe_put(opts, key, normalize_config_value(key, value))
  end

  defp append_config_values(opts, _key, nil), do: opts

  defp append_config_values(opts, key, values) when is_list(values) do
    Enum.reduce(values, opts, fn value, acc -> acc ++ [{key, value}] end)
  end

  defp append_config_values(opts, key, value), do: opts ++ [{key, value}]

  defp normalize_config_value(_key, nil), do: nil

  defp normalize_config_value(key, value)
       when key in [:tm_frame_size, :scid, :vcid, :tc_frame_size],
       do: parse_integer(value) || value

  defp normalize_config_value(key, value)
       when key in [:generator_count, :metrics_sample_rate, :send_batch_timeout, :send_batch_size],
       do: parse_integer(value) || value

  defp normalize_config_value(:rate, value), do: parse_float(value) || value
  defp normalize_config_value(:noise_amplitude, value), do: parse_float(value) || value
  defp normalize_config_value(:parallel, value), do: parse_boolean(value)
  defp normalize_config_value(:tm_parallel_framing, value), do: parse_boolean(value)
  defp normalize_config_value(:fecf, value), do: parse_boolean(value)
  defp normalize_config_value(_key, value), do: value

  defp fetch_config_value(nil, _keys), do: nil

  defp fetch_config_value(map, keys) when is_map(map),
    do: Enum.find_value(keys, &Map.get(map, &1))

  defp fetch_config_value(_map, _keys), do: nil

  defp fetch_map_value(map, keys) do
    case fetch_config_value(map, keys) do
      %{} = value -> value
      _other -> nil
    end
  end

  defp parse_clcw_overrides([]), do: {:ok, %{}}

  defp parse_clcw_overrides(specs) when is_list(specs) do
    Enum.reduce_while(specs, {:ok, %{}}, fn spec, {:ok, acc} ->
      case parse_override_spec(spec) do
        {:ok, overrides} -> {:cont, {:ok, Map.merge(acc, overrides)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp parse_clcw_schedule([]), do: {:ok, []}

  defp parse_clcw_schedule(specs) when is_list(specs) do
    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
      case parse_schedule_spec(spec) do
        {:ok, entry} -> {:cont, {:ok, acc ++ [entry]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp parse_schedule_spec(spec) when is_binary(spec) do
    case String.split(spec, ":", parts: 2) do
      [step_string, overrides_spec] ->
        with {:ok, step} <- parse_schedule_step(step_string),
             {:ok, overrides} <- parse_override_spec(overrides_spec) do
          {:ok, %{at: step, overrides: overrides}}
        end

      _other ->
        {:error, "invalid --clcw-schedule entry: #{inspect(spec)}"}
    end
  end

  defp parse_schedule_spec(%{} = spec) do
    step = fetch_config_value(spec, ["at", "step", :at, :step])
    overrides = fetch_config_value(spec, ["overrides", "flags", :overrides, :flags])

    with {:ok, parsed_step} <- parse_schedule_step(step),
         {:ok, parsed_overrides} <- parse_override_spec(overrides) do
      {:ok, %{at: parsed_step, overrides: parsed_overrides}}
    else
      {:error, _message} = error -> error
    end
  end

  defp parse_schedule_spec(spec), do: {:error, "invalid --clcw-schedule entry: #{inspect(spec)}"}

  defp parse_schedule_step(step) when is_integer(step) and step >= 0, do: {:ok, step}

  defp parse_schedule_step(step_string) when is_binary(step_string) do
    case Integer.parse(String.trim(step_string)) do
      {step, ""} when step >= 0 -> {:ok, step}
      _other -> {:error, "invalid --clcw-schedule step: #{inspect(step_string)}"}
    end
  end

  defp parse_schedule_step(step), do: {:error, "invalid --clcw-schedule step: #{inspect(step)}"}

  defp parse_override_spec(spec) when is_binary(spec) do
    entries =
      spec
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    if entries == [] do
      {:error, "invalid --clcw-overrides entry: #{inspect(spec)}"}
    else
      Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
        reduce_override_entry(entry, acc)
      end)
    end
  end

  defp parse_override_spec(%{} = spec), do: {:ok, spec}

  defp parse_override_spec(spec), do: {:error, "invalid --clcw-overrides entry: #{inspect(spec)}"}

  defp reduce_override_entry(entry, acc) do
    case parse_override_entry(entry) do
      {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp parse_override_entry(entry) when is_binary(entry) do
    case String.split(entry, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)

        if key == "" or value == "" do
          {:error, "invalid CLCW override pair: #{inspect(entry)}"}
        else
          {:ok, {key, parse_override_value(value)}}
        end

      _other ->
        {:error, "invalid CLCW override pair: #{inspect(entry)}"}
    end
  end

  defp parse_override_value(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "false" -> false
      _other -> parse_integer(value) || value
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp with_usage({:error, message}, runtime_mode),
    do: {:error, message <> "\n\n" <> usage(runtime_mode)}

  defp with_usage(result, _runtime_mode), do: result

  defp format_invalid_options(invalid) do
    Enum.map_join(invalid, ", ", fn
      {option, nil} -> option
      {option, value} -> "#{option}=#{value}"
    end)
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _other -> nil
    end
  end

  defp parse_float(_value), do: nil

  defp parse_boolean(value) when value in [true, false], do: value

  defp parse_boolean(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "false" -> false
      _other -> value
    end
  end

  defp parse_boolean(value), do: value
end
