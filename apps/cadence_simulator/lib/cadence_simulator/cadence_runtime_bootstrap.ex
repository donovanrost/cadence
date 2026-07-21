defmodule CadenceSimulator.CadenceRuntimeBootstrap do
  @moduledoc """
  Resolves simulator runtime options from authenticated Cadence path-runtime
  snapshots.

  This lets simulator runs target declared provider/contact runtime state
  instead of manually repeating socket endpoints in local config.
  """

  @default_receive_timeout 5_000

  @bootstrap_keys [
    :cadence_url,
    :api_token,
    :organization_id,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :provider_binding_id,
    :transport_binding_id
  ]

  @required_bootstrap_keys [
    :cadence_url,
    :api_token,
    :organization_id,
    :mission_id,
    :realized_contact_id,
    :path_id
  ]

  @spec resolve_runtime_opts(keyword(), keyword()) :: {:ok, keyword()} | {:error, term()}
  def resolve_runtime_opts(runtime_opts, opts \\ [])
      when is_list(runtime_opts) and is_list(opts) do
    case bootstrap_request(runtime_opts) do
      nil ->
        {:ok, strip_bootstrap_keys(runtime_opts)}

      {:error, _reason} = error ->
        error

      bootstrap_request when is_map(bootstrap_request) ->
        runtime_mode = Keyword.fetch!(runtime_opts, :runtime_mode)
        http_client = Keyword.get(opts, :http_client, __MODULE__.ReqClient)

        with {:ok, path_snapshot} <- fetch_path_runtime_snapshot(http_client, bootstrap_request),
             {:ok, bootstrap_runtime_opts} <-
               derive_runtime_opts(
                 runtime_mode,
                 bootstrap_request,
                 path_snapshot
               ) do
          {:ok,
           runtime_opts
           |> strip_bootstrap_keys()
           |> merge_bootstrap_runtime_opts(runtime_mode, bootstrap_runtime_opts)
           |> Keyword.put(
             :runtime_resolver,
             runtime_resolver_spec(runtime_mode, bootstrap_request, http_client)
           )}
        end
    end
  end

  @spec refresh_runtime_opts(map() | keyword()) :: {:ok, keyword()} | {:error, term()}
  def refresh_runtime_opts(opts) when is_list(opts) do
    refresh_runtime_opts(Map.new(opts))
  end

  def refresh_runtime_opts(%{
        runtime_mode: runtime_mode,
        bootstrap_request: bootstrap_request,
        http_client: http_client
      })
      when is_map(bootstrap_request) and is_atom(http_client) do
    with {:ok, path_snapshot} <- fetch_path_runtime_snapshot(http_client, bootstrap_request) do
      derive_runtime_opts(runtime_mode, bootstrap_request, path_snapshot)
    end
  end

  @spec fetch_path_runtime_snapshot(module(), map()) :: {:ok, map()} | {:error, term()}
  def fetch_path_runtime_snapshot(http_client, bootstrap_request)
      when is_atom(http_client) and is_map(bootstrap_request) do
    url =
      bootstrap_request.cadence_url
      |> String.trim_trailing("/")
      |> Kernel.<>(
        "/api/organizations/#{bootstrap_request.organization_id}/missions/#{bootstrap_request.mission_id}" <>
          "/realized_contacts/#{bootstrap_request.realized_contact_id}/paths/#{bootstrap_request.path_id}/runtime"
      )

    headers = [{"authorization", "Bearer " <> bootstrap_request.api_token}]
    http_client.get_json(url, headers: headers, receive_timeout: @default_receive_timeout)
  end

  defp derive_runtime_opts(:telemetry, bootstrap_request, path_snapshot) do
    with {:ok, provider_runtime} <- select_provider_runtime(path_snapshot, bootstrap_request),
         :ok <- ensure_connectable_provider(provider_runtime, :telemetry),
         {:ok, output} <- provider_output(provider_runtime) do
      frame = telemetry_frame(provider_runtime)

      {:ok,
       []
       |> Keyword.put(:output, output)
       |> maybe_put(:frame, frame)}
    end
  end

  defp derive_runtime_opts(:cop1_loopback, bootstrap_request, path_snapshot) do
    with {:ok, provider_runtime} <- select_provider_runtime(path_snapshot, bootstrap_request),
         :ok <- ensure_connectable_provider(provider_runtime, :cop1_loopback),
         {:ok, {host, port}} <- provider_host_port(provider_runtime),
         {:ok, transport_runtime} <- select_transport_runtime(path_snapshot, bootstrap_request),
         {:ok, tc_frame_size} <- transport_frame_size(transport_runtime),
         {:ok, segment_header_flag} <- transport_segment_header_flag(transport_runtime),
         {:ok, fecf?} <- transport_fecf(transport_runtime) do
      {:ok,
       [
         host: host,
         port: port,
         tc_frame_size: tc_frame_size,
         segment_header_flag: segment_header_flag,
         fecf: fecf?
       ]}
    end
  end

  defp bootstrap_request(runtime_opts) do
    values = Map.new(@bootstrap_keys, fn key -> {key, Keyword.get(runtime_opts, key)} end)

    if Enum.any?(@bootstrap_keys, &present?(Map.get(values, &1))) do
      case validate_bootstrap_request(values) do
        :ok -> values
        {:error, _reason} = error -> error
      end
    else
      nil
    end
  end

  defp validate_bootstrap_request(values) do
    missing_keys =
      Enum.reject(@required_bootstrap_keys, fn key ->
        present?(Map.get(values, key))
      end)

    case missing_keys do
      [] -> :ok
      _other -> {:error, {:missing_cadence_bootstrap_keys, missing_keys}}
    end
  end

  defp select_provider_runtime(path_snapshot, bootstrap_request) do
    provider_runtimes =
      path_snapshot
      |> Map.get("provider_runtimes", [])
      |> Enum.filter(&(Map.get(&1, "adapter_key") == "tcp_socket"))

    case bootstrap_request.provider_binding_id do
      provider_binding_id when is_binary(provider_binding_id) ->
        case Enum.find(provider_runtimes, &(&1["provider_binding_id"] == provider_binding_id)) do
          nil -> {:error, {:provider_runtime_not_found, provider_binding_id}}
          provider_runtime -> {:ok, provider_runtime}
        end

      _other ->
        case provider_runtimes do
          [provider_runtime] -> {:ok, provider_runtime}
          [] -> {:error, :tcp_provider_runtime_not_found}
          _many -> {:error, :provider_runtime_selection_required}
        end
    end
  end

  defp select_transport_runtime(path_snapshot, bootstrap_request) do
    transport_runtimes = Map.get(path_snapshot, "transport_runtimes", [])

    selected_transport_runtimes =
      case bootstrap_request.transport_binding_id do
        transport_binding_id when is_binary(transport_binding_id) ->
          Enum.filter(
            transport_runtimes,
            &(&1["capability_instance_id"] == transport_binding_id)
          )

        _other ->
          Enum.filter(transport_runtimes, &(&1["family_key"] == "uplink_gateway"))
      end

    case selected_transport_runtimes do
      [transport_runtime] ->
        {:ok, transport_runtime}

      [] when is_binary(bootstrap_request.transport_binding_id) ->
        {:error, {:transport_runtime_not_found, bootstrap_request.transport_binding_id}}

      [] ->
        {:error, :uplink_gateway_runtime_not_found}

      _many when is_binary(bootstrap_request.transport_binding_id) ->
        {:error, {:ambiguous_transport_runtime, bootstrap_request.transport_binding_id}}

      _many ->
        {:error, :transport_runtime_selection_required}
    end
  end

  defp transport_frame_size(transport_runtime) when is_map(transport_runtime) do
    case get_in(transport_runtime, ["state", "frame_size"]) do
      frame_size when is_integer(frame_size) and frame_size > 0 ->
        {:ok, frame_size}

      other ->
        {:error, {:invalid_transport_frame_size, other}}
    end
  end

  defp transport_segment_header_flag(transport_runtime) when is_map(transport_runtime) do
    case get_in(transport_runtime, ["state", "segment_header_flag"]) do
      nil -> {:ok, 0}
      segment_header_flag when segment_header_flag in [0, 1] -> {:ok, segment_header_flag}
      other -> {:error, {:invalid_transport_segment_header_flag, other}}
    end
  end

  defp transport_fecf(transport_runtime) when is_map(transport_runtime) do
    case get_in(transport_runtime, ["state", "fecf"]) do
      nil -> {:ok, false}
      fecf? when is_boolean(fecf?) -> {:ok, fecf?}
      other -> {:error, {:invalid_transport_fecf, other}}
    end
  end

  defp telemetry_frame(provider_runtime) when is_map(provider_runtime) do
    case {provider_runtime["ingress_protocol_family"], provider_runtime["fixed_message_bytes"]} do
      {protocol_family, frame_size}
      when protocol_family in ["tm", "tm_transfer_frame"] and is_integer(frame_size) and
             frame_size > 0 ->
        ingress_metadata = provider_runtime["ingress_metadata"] || %{}

        %{
          format: :tm,
          frame_size: frame_size,
          scid: 0,
          vcid: 0,
          fecf: Map.get(ingress_metadata, "fecf", false)
        }

      _other ->
        nil
    end
  end

  defp ensure_connectable_provider(provider_runtime, runtime_mode)
       when is_map(provider_runtime) do
    case provider_runtime["mode"] do
      "listen" ->
        :ok

      mode ->
        {:error, {:unsupported_provider_mode_for_simulator, runtime_mode, mode}}
    end
  end

  defp provider_output(provider_runtime) when is_map(provider_runtime) do
    with {:ok, {host, port}} <- provider_host_port(provider_runtime) do
      {:ok, {:tcp, host, port}}
    end
  end

  defp provider_host_port(provider_runtime) when is_map(provider_runtime) do
    host = provider_runtime["host"] || "127.0.0.1"
    port = provider_runtime["port"]

    if is_binary(host) and is_integer(port) and port > 0 do
      {:ok, {host, port}}
    else
      {:error, {:invalid_provider_host_or_port, host, port}}
    end
  end

  defp put_missing_opts(runtime_opts, bootstrap_runtime_opts) do
    Enum.reduce(bootstrap_runtime_opts, runtime_opts, fn {key, value}, acc ->
      case Keyword.has_key?(acc, key) do
        true -> acc
        false -> Keyword.put(acc, key, value)
      end
    end)
  end

  defp merge_bootstrap_runtime_opts(runtime_opts, :telemetry, bootstrap_runtime_opts) do
    runtime_opts
    |> Keyword.drop([:output, :frame])
    |> put_missing_opts(bootstrap_runtime_opts)
  end

  defp merge_bootstrap_runtime_opts(runtime_opts, :cop1_loopback, bootstrap_runtime_opts) do
    runtime_opts
    |> Keyword.drop([:host, :port, :tc_frame_size, :segment_header_flag, :fecf])
    |> put_missing_opts(bootstrap_runtime_opts)
  end

  defp runtime_resolver_spec(runtime_mode, bootstrap_request, http_client) do
    {__MODULE__, :refresh_runtime_opts,
     [
       [
         runtime_mode: runtime_mode,
         bootstrap_request: bootstrap_request,
         http_client: http_client
       ]
     ]}
  end

  defp strip_bootstrap_keys(runtime_opts) do
    Keyword.drop(runtime_opts, @bootstrap_keys)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(nil), do: false
  defp present?(_value), do: true
end
