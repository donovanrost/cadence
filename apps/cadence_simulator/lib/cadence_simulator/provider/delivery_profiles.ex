defmodule CadenceSimulator.Provider.DeliveryProfiles do
  @moduledoc "Provider-owned delivery profiles exposed by a simulator run."

  alias CadenceSimulator.Provider.{Contract, Ids, ServiceProfiles, Store}

  @directions ["downlink", "uplink", "bidirectional"]
  @delivery_kinds ["realtime_stream", "object_delivery", "message_bus", "provider_managed"]
  @states ["ready", "degraded", "unavailable"]
  @internal_keys ["run_id", "client_reference", "target", "framing", "configuration_snapshot"]

  @spec normalize(term()) :: {:ok, [map()]} | {:error, {:invalid, binary()}}
  def normalize(profiles) when is_list(profiles) do
    profiles
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {profile, index}, {:ok, acc} ->
      case normalize_profile(profile, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> normalized |> Enum.reverse() |> ensure_unique_ids()
      error -> error
    end
  end

  def normalize(_profiles), do: {:error, {:invalid, "delivery_profiles must be a list"}}

  @spec for_run(map()) :: [map()]
  def for_run(run) do
    configured = get_in(run, ["scenario_snapshot", "delivery_profiles"]) || []

    provisioned =
      Store.list(:delivery_profile)
      |> Enum.filter(&(&1["run_id"] == run["id"]))
      |> Enum.map(&public/1)

    configured ++ provisioned
  end

  @spec fetch(map(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(run, id) when is_binary(id) do
    case fetch_internal(run, id) do
      {:ok, profile} -> {:ok, public(profile)}
      error -> error
    end
  end

  @spec fetch_internal(map(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch_internal(run, id) when is_binary(id) do
    expected_run_id = run["id"]

    case Store.fetch(:delivery_profile, id) do
      {:ok, %{"run_id" => ^expected_run_id} = profile} ->
        {:ok, profile}

      _other ->
        case Enum.find(
               get_in(run, ["scenario_snapshot", "delivery_profiles"]) || [],
               &(&1["id"] == id)
             ) do
          nil -> {:error, :not_found}
          profile -> {:ok, profile}
        end
    end
  end

  @spec provision(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def provision(run, attrs, opts \\ []) when is_map(run) and is_map(attrs) do
    attrs = Contract.sanitize(attrs)

    case normalize_provisioning_request(run, attrs) do
      {:ok, request} -> provision_normalized(run, request, opts)
      error -> error
    end
  end

  defp provision_normalized(run, request, opts) do
    case existing_by_client_reference(run["id"], request["client_reference"]) do
      nil -> create_profile(run, request, opts)
      existing -> recover_profile(existing, request)
    end
  end

  defp create_profile(run, request, opts) do
    with {:ok, stored} <- Store.put(:delivery_profile, build_profile(run, request)) do
      emit_created(stored, Keyword.get(opts, :request_id))
      {:ok, public(stored)}
    end
  end

  defp recover_profile(existing, request) do
    if existing["configuration_snapshot"] == request do
      {:ok, public(existing)}
    else
      {:error, {:conflict, "client_reference already identifies another delivery profile"}}
    end
  end

  defp normalize_provisioning_request(run, attrs) do
    target = Map.get(attrs, "target", %{})
    framing = Map.get(attrs, "framing", %{})

    with {:ok, display_name} <- required_provisioning_text(attrs, "display_name"),
         {:ok, client_reference} <- required_provisioning_text(attrs, "client_reference"),
         :ok <- exact_value(attrs, "direction", "downlink"),
         :ok <- exact_value(attrs, "delivery_kind", "realtime_stream"),
         :ok <- exact_value(target, "protocol", "tcp", "target.protocol"),
         :ok <- exact_value(target, "mode", "provider_connects", "target.mode"),
         {:ok, host} <- required_provisioning_text(target, "host", "target.host"),
         {:ok, port} <- port(target["port"]),
         :ok <- exact_value(framing, "family", "ccsds_tm", "framing.family"),
         :ok <- exact_value(framing, "mode", "fixed_size", "framing.mode"),
         {:ok, frame_bytes} <- positive_integer(framing["frame_bytes"], "framing.frame_bytes"),
         {:ok, operator_summary} <-
           optional_provisioning_text(attrs, "operator_summary", "Streaming to Cadence"),
         {:ok, extensions} <- provisioning_object(attrs, "extensions", %{}) do
      service_refs = compatible_service_refs(run)

      if service_refs == [] do
        {:error, {:invalid, "no compatible active Service Profile is available"}}
      else
        {:ok,
         %{
           "display_name" => display_name,
           "client_reference" => client_reference,
           "direction" => "downlink",
           "delivery_kind" => "realtime_stream",
           "target" => %{
             "protocol" => "tcp",
             "mode" => "provider_connects",
             "host" => host,
             "port" => port
           },
           "framing" => %{
             "family" => "ccsds_tm",
             "mode" => "fixed_size",
             "frame_bytes" => frame_bytes
           },
           "supported_service_profile_refs" => service_refs,
           "operator_summary" => operator_summary,
           "extensions" => extensions
         }}
      end
    end
  end

  defp build_profile(run, request) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "id" => Ids.stable("delivery", [run["id"], ":", request["client_reference"]]),
      "run_id" => run["id"],
      "version" => 1,
      "display_name" => request["display_name"],
      "client_reference" => request["client_reference"],
      "direction" => request["direction"],
      "delivery_kind" => request["delivery_kind"],
      "supported_service_profile_refs" => request["supported_service_profile_refs"],
      "state" => "ready",
      "operator_summary" => request["operator_summary"],
      "diagnostics" => %{
        "protocol" => request["target"]["protocol"],
        "mode" => request["target"]["mode"],
        "host" => request["target"]["host"],
        "port" => request["target"]["port"],
        "framing_family" => request["framing"]["family"],
        "frame_bytes" => request["framing"]["frame_bytes"],
        "endpoint_health" => "healthy"
      },
      "target" => request["target"],
      "framing" => request["framing"],
      "configuration_snapshot" => request,
      "extensions" => request["extensions"],
      "created_at" => now,
      "updated_at" => now
    }
  end

  defp existing_by_client_reference(run_id, client_reference) do
    Enum.find(Store.list(:delivery_profile), fn profile ->
      profile["run_id"] == run_id and profile["client_reference"] == client_reference
    end)
  end

  defp compatible_service_refs(run) do
    run
    |> ServiceProfiles.for_run()
    |> Enum.filter(fn profile ->
      profile["state"] == "active" and profile["direction"] == "downlink" and
        "realtime_stream" in profile["supported_delivery_kinds"]
    end)
    |> Enum.map(& &1["id"])
  end

  defp public(profile), do: Map.drop(profile, @internal_keys ++ ["created_at", "updated_at"])

  defp emit_created(profile, request_id) do
    Store.append_event(%{
      "schema_version" => Contract.version(),
      "type" => "delivery_profile.created",
      "resource_type" => "delivery_profile",
      "resource_id" => profile["id"],
      "run_id" => profile["run_id"],
      "request_id" => request_id,
      "data" => %{"state" => profile["state"], "version" => profile["version"]}
    })
  end

  defp required_provisioning_text(map, key, label \\ nil) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "#{label || key} is required"}}
    end
  end

  defp optional_provisioning_text(map, key, default) do
    case Map.get(map, key, default) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "#{key} is invalid"}}
    end
  end

  defp provisioning_object(map, key, default) do
    case Map.get(map, key, default) do
      value when is_map(value) -> {:ok, value}
      _other -> {:error, {:invalid, "#{key} must be an object"}}
    end
  end

  defp exact_value(map, key, expected, label \\ nil) do
    if map[key] == expected,
      do: :ok,
      else: {:error, {:invalid, "#{label || key} must be #{expected}"}}
  end

  defp port(value) when is_integer(value) and value >= 1 and value <= 65_535, do: {:ok, value}
  defp port(_value), do: {:error, {:invalid, "target.port is invalid"}}

  defp positive_integer(value, _label) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value, label), do: {:error, {:invalid, "#{label} is invalid"}}

  defp normalize_profile(profile, index) when is_map(profile) do
    profile = Contract.sanitize(profile)

    with {:ok, id} <- required_text(profile, "id", index),
         {:ok, display_name} <- required_text(profile, "display_name", index),
         {:ok, direction} <- member(profile, "direction", @directions, "downlink", index),
         {:ok, delivery_kind} <-
           member(profile, "delivery_kind", @delivery_kinds, "realtime_stream", index),
         {:ok, state} <- member(profile, "state", @states, "ready", index),
         {:ok, version} <- positive_integer(profile, "version", 1, index),
         {:ok, service_refs} <-
           string_list(profile, "supported_service_profile_refs", [], index),
         {:ok, operator_summary} <-
           optional_text(profile, "operator_summary", "Provider-managed delivery", index),
         {:ok, diagnostics} <- object(profile, "diagnostics", %{}, index),
         {:ok, extensions} <- object(profile, "extensions", %{}, index) do
      {:ok,
       %{
         "id" => id,
         "version" => version,
         "display_name" => display_name,
         "direction" => direction,
         "delivery_kind" => delivery_kind,
         "supported_service_profile_refs" => service_refs,
         "state" => state,
         "operator_summary" => operator_summary,
         "diagnostics" => diagnostics,
         "extensions" => extensions
       }}
    end
  end

  defp normalize_profile(_profile, index),
    do: {:error, {:invalid, "delivery_profiles[#{index}] must be an object"}}

  defp required_text(map, key, index) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "delivery_profiles[#{index}].#{key} is required"}}
    end
  end

  defp member(map, key, allowed, default, index) do
    value = Map.get(map, key, default)

    if value in allowed,
      do: {:ok, value},
      else: {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}
  end

  defp positive_integer(map, key, default, index) do
    case Map.get(map, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp string_list(map, key, default, index) do
    case Map.get(map, key, default) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")),
          do: {:ok, values},
          else: {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}

      _other ->
        {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp optional_text(map, key, default, index) do
    case Map.get(map, key, default) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp object(map, key, default, index) do
    case Map.get(map, key, default) do
      value when is_map(value) -> {:ok, value}
      _other -> {:error, {:invalid, "delivery_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp ensure_unique_ids(profiles) do
    ids = Enum.map(profiles, & &1["id"])

    if MapSet.size(MapSet.new(ids)) == length(ids),
      do: {:ok, profiles},
      else: {:error, {:invalid, "delivery_profiles ids must be unique"}}
  end
end
