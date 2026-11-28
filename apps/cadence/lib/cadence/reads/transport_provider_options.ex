defmodule Cadence.Reads.TransportProviderOptions do
  @moduledoc """
  The console's provider-managed transport form (comms parity 2; contract
  docs/apogee/api/changes.md §Transport provider options): the dependent choices and the derived
  preview, read-only.

    * `providers`: the mission's providers, `[{id, version, name}]`;
    * `services`: the chosen provider's active downlink service profiles, `[{id, version, name}]`
      (`[]` until a provider is chosen);
    * `deliveries`: its ready downlink delivery profiles that support the chosen service and that
      the transport kind can use, `[{id, version, name, egress_addresses_ready}]` (`[]` until a
      service is chosen). One the kind could use but for its egress addresses (#990) is listed
      with `egress_addresses_ready: false`; choosing it answers a coded field error;
    * `preview`: `Management.Transports.derive/3`'s result (the caller passes it in) once provider, service and delivery
      are all chosen, rendered as `{configuration: [{label, value}], direction_capability,
      provider_version, summary: [{label, value}]}`, else `nil`;
    * `errors`: derive's field errors `[{path, message}]`, plus `code` where one applies (`path` one of `mission_provider_id`,
      `mission_provider_version`, `service_profile_ref`, `delivery_profile_ref`, or `nil`).

  The preview is the same derivation the change set's apply uses, so preview and stored
  configuration can't disagree.
  """

  alias Cadence.ExtensionCatalog
  alias Cadence.Management.Providers

  @kind "tcp_socket"

  @type choice :: %{id: binary(), version: pos_integer() | nil, name: binary()}

  @typedoc "`Management.Transports.derive/3`, handed in by the caller (reads don't reach Management's composition)."
  @type derive :: (binary(), binary(), map() -> {:ok, map()} | {:error, [map()]})

  @spec load(binary(), binary(), map(), derive()) :: map()
  def load(org, mission, selection, derive) when is_function(derive, 3) do
    providers = Providers.list_providers(org, mission)
    provider = Enum.find(providers, &(&1.provider_id == selection[:provider_id]))
    services = if provider, do: services(provider), else: []
    service = Enum.find(services, &(&1["id"] == selection[:service_profile_id]))
    deliveries = if service, do: deliveries(provider, service), else: []
    delivery = Enum.find(deliveries, &(&1["id"] == selection[:delivery_profile_id]))
    {preview, errors} = preview(derive, org, mission, provider, service, delivery)

    %{
      providers: Enum.map(providers, &provider_choice/1),
      services: Enum.map(services, &profile_choice/1),
      deliveries: Enum.map(deliveries, &delivery_choice/1),
      preview: preview,
      errors: unknown_choices(selection, provider, service, delivery) ++ errors
    }
  end

  defp preview(derive, org, mission, %{} = provider, %{} = service, %{} = delivery) do
    document = %{
      "mission_provider_id" => provider.provider_id,
      "mission_provider_version" => provider.version,
      "service_profile_ref" => Map.take(service, ["id", "version"]),
      "delivery_profile_ref" => Map.take(delivery, ["id", "version"])
    }

    case derive.(org, mission, document) do
      {:ok, derived} -> {render(derived), []}
      {:error, errors} -> {nil, Enum.map(errors, &error/1)}
    end
  end

  defp preview(_derive, _org, _mission, _provider, _service, _delivery), do: {nil, []}

  # A chosen id that isn't on offer: the console puts it on its field.
  defp unknown_choices(selection, provider, service, delivery) do
    [
      {:provider_id, provider, "mission_provider_id",
       "That provider isn't one of this mission's."},
      {:service_profile_id, service, "service_profile_ref",
       "That service isn't offered by the provider."},
      {:delivery_profile_id, delivery, "delivery_profile_ref",
       "That delivery doesn't fit the service."}
    ]
    |> Enum.filter(fn {key, found, _path, _message} ->
      chosen?(selection[key]) and is_nil(found)
    end)
    |> Enum.map(fn {_key, _found, path, message} -> %{path: path, message: message} end)
  end

  defp chosen?(value), do: is_binary(value) and value != ""

  defp render(%{summary: summary} = derived) do
    %{
      configuration: configuration_rows(derived.configuration, summary),
      direction_capability: to_string(derived.direction_capability),
      provider_version: derived.provider_version,
      summary:
        rows([
          {"Endpoint", summary.endpoint},
          {"Mode", summary.mode},
          {"Framing", summary.framing},
          {"TLS", tls(summary)}
        ])
    }
  end

  defp configuration_rows(configuration, summary) do
    rows([
      {"Endpoint", summary.endpoint},
      {"Mode", summary.mode},
      {"Direction", summary.direction_capability},
      {"Framing", summary.framing},
      {"Frame bytes", configuration["fixed_message_bytes"] || "Not fixed"},
      {"Reconnect", get_in(configuration, ["reconnect", "policy"]) || "Not configured"},
      {"TLS", tls(summary)}
    ])
  end

  defp tls(summary), do: if(Map.get(summary, :tls_enabled?), do: "Enabled", else: "Disabled")

  defp rows(pairs),
    do: Enum.map(pairs, fn {label, value} -> %{label: label, value: text(value)} end)

  defp text(nil), do: ""
  defp text(value), do: to_string(value)

  defp error(%{path: path, message: message, code: code}),
    do: %{path: path, message: message, code: code}

  defp error(%{path: path, message: message}), do: %{path: path, message: message}
  defp error(other), do: %{path: nil, message: inspect(other)}

  defp provider_choice(provider),
    do: %{id: provider.provider_id, version: provider.version, name: provider.display_name}

  defp profile_choice(profile),
    do: %{
      id: profile["id"],
      version: profile["version"],
      name: profile["display_name"] || profile["id"]
    }

  # A delivery choice says whether the provider named usable egress addresses (#990), so an
  # unusable one shows why instead of being missing from the list.
  defp delivery_choice(delivery),
    do:
      Map.put(
        profile_choice(delivery),
        :egress_addresses_ready,
        Map.get(delivery, "egress_addresses_ready", true)
      )

  defp services(provider) do
    provider
    |> profile_items("service_profiles")
    |> Enum.filter(&(&1["state"] == "active" and &1["direction"] == "downlink"))
  end

  defp deliveries(provider, service) do
    case ExtensionCatalog.fetch_transport_kind(@kind) do
      {:ok, entry} ->
        provider
        |> profile_items("delivery_profiles")
        |> Enum.filter(fn delivery ->
          delivery["state"] == "ready" and delivery["direction"] == "downlink" and
            service["id"] in (delivery["supported_service_profile_refs"] || []) and
            usable?(entry.module, delivery)
        end)
        |> Enum.map(
          &Map.put(&1, "egress_addresses_ready", egress_refusal(entry.module, &1) == nil)
        )

      _unknown ->
        []
    end
  end

  # Usable, or unusable only for its egress addresses (#990): those are listed flagged
  # (`egress_addresses_ready: false`) so the operator sees why, and choosing one gets the coded
  # field error.
  defp usable?(module, delivery),
    do:
      match?({:ok, _}, module.from_delivery_profile(delivery)) or
        egress_refusal(module, delivery) != nil

  defp egress_refusal(module, delivery) do
    if function_exported?(module, :egress_refusal, 1), do: module.egress_refusal(delivery)
  end

  defp profile_items(provider, key) do
    case get_in(provider.inventory_sync_document || %{}, [key, "items"]) do
      items when is_list(items) -> items
      _other -> []
    end
  end
end
