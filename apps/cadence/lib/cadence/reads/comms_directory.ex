defmodule Cadence.Reads.CommsDirectory do
  @moduledoc """
  Ground stations, transports and routing rules for the Setup comms screens.
  Edits go through mission change sets (`ground_station` / `transport` kinds);
  these are the reads. Callers authorize first.

  The model has no station↔transport link, so a station's `transport_count`
  and a transport's `station` are `nil` (unknown) rather than invented.
  """

  alias Cadence.Comms.{GroundStation, GroundStationStore, RoutingRule, Transport, TransportStore}
  alias Cadence.Configuration.Kinds
  alias Cadence.GroundNetworks.ProviderAccounts
  alias Cadence.Reads.OperationalState

  @default_limit 100
  @max_limit 500

  @spec stations(binary(), binary()) :: [map()]
  def stations(organization_id, mission_id) do
    organization_id
    |> GroundStationStore.list_ground_stations(mission_id)
    |> Enum.map(fn %GroundStation{} = station ->
      %{
        id: station.ground_station_id,
        display_name: station.display_name,
        code: station.code,
        provider: station.provider,
        region: station.region,
        lifecycle_state: station.lifecycle_state,
        transport_count: nil,
        routing_rule_count: nil,
        health: nil
      }
    end)
  end

  @doc """
  The mission's ground-network providers with their account and station count.
  `account.name` is `nil` when the scope can't read organization accounts
  (organization admins can). Status fields are the provider's own: lifecycle
  plus the last validation and sync times; nothing is inferred.
  """
  @spec providers(Cadence.Auth.Scope.t(), binary()) :: [map()]
  def providers(scope, mission_id) do
    organization_id = scope.organization_id

    station_counts =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> Enum.frequencies_by(& &1.provider)

    organization_id
    |> Cadence.GroundNetworks.list_providers(mission_id)
    |> Enum.map(fn provider ->
      %{
        id: provider.provider_id,
        name: provider.display_name,
        provider_type: provider.provider_type,
        account: %{
          id: provider.provider_account_id,
          name: account_name(scope, provider.provider_account_id)
        },
        status: %{
          lifecycle_state: provider.lifecycle_state,
          last_validated_at: provider.last_validated_at,
          last_synced_at: provider.last_synced_at
        },
        station_count: Map.get(station_counts, provider.display_name, 0)
      }
    end)
  end

  defp account_name(_scope, nil), do: nil

  defp account_name(scope, account_id) do
    case ProviderAccounts.fetch(scope, account_id) do
      {:ok, account, _version} -> account.display_name
      _unavailable -> nil
    end
  end

  @spec transports(binary(), binary()) :: [map()]
  def transports(organization_id, mission_id) do
    rule_counts =
      organization_id
      |> OperationalState.list_routing_rules(mission_id)
      |> Enum.filter(&(&1.lifecycle_state == :active))
      |> Enum.frequencies_by(& &1.transport_id)

    organization_id
    |> TransportStore.list_transports(mission_id)
    |> Enum.map(fn %Transport{} = transport ->
      %{
        id: transport.transport_id,
        display_name: transport.display_name,
        version: transport.version,
        origin: transport.origin,
        transport_kind: transport.transport_kind,
        direction_capability: transport.direction_capability,
        lifecycle_state: transport.lifecycle_state,
        station: nil,
        routing_rule_count: Map.get(rule_counts, transport.transport_id, 0)
      }
    end)
  end

  @doc """
  One transport with its editable document, exactly as the `transport`
  change-set kind loads it, so the edit form prefills with the same paths it
  stages (see `Cadence.Reads.ConfigKindSchema`).
  """
  @spec transport(binary(), binary(), binary()) :: {:ok, map()} | {:error, :transport_not_found}
  def transport(organization_id, mission_id, transport_id) do
    with {:ok, %Transport{} = transport} <-
           TransportStore.fetch_transport(organization_id, mission_id, transport_id),
         %{} = document <-
           "transport"
           |> Kinds.fetch!()
           |> then(& &1.load(organization_id, mission_id, [transport_id]))
           |> Map.get(transport_id) do
      {:ok,
       %{
         id: transport.transport_id,
         version: transport.version,
         lifecycle_state: transport.lifecycle_state,
         document:
           Map.take(
             document,
             ~w(display_name origin transport_kind direction_capability configuration)
           )
       }}
    else
      _missing -> {:error, :transport_not_found}
    end
  end

  @doc "Paged routing rules. `cursor` is an opaque offset string from the previous page."
  @spec routing_rules(binary(), binary(), map()) :: {:ok, map()} | {:error, map()}
  def routing_rules(organization_id, mission_id, params) do
    with {:ok, limit} <- limit(params["limit"]),
         {:ok, offset} <- offset(params["cursor"]) do
      names =
        organization_id
        |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
        |> Map.new(&{&1.spacecraft_id, &1.display_name})

      transports =
        organization_id
        |> TransportStore.list_transports(mission_id)
        |> Map.new(&{&1.transport_id, &1.display_name})

      rules =
        organization_id
        |> OperationalState.list_routing_rules(mission_id)
        |> Enum.filter(&matches?(&1, params))
        |> Enum.sort_by(
          &{names[&1.spacecraft_id] || "", &1.display_name || "", &1.routing_rule_id}
        )

      page = rules |> Enum.drop(offset) |> Enum.take(limit)
      next = offset + length(page)

      {:ok,
       %{
         rules: Enum.map(page, &rule(&1, names, transports)),
         total: length(rules),
         next_cursor: if(next < length(rules), do: Integer.to_string(next))
       }}
    end
  end

  defp rule(%RoutingRule{} = rule, names, transports) do
    %{
      id: rule.routing_rule_id,
      display_name: rule.display_name,
      purpose: rule.purpose_label,
      direction: rule.direction,
      role: rule.role,
      enabled: rule.enabled?,
      active: rule.lifecycle_state == :active,
      spacecraft: %{id: rule.spacecraft_id, name: names[rule.spacecraft_id]},
      transport: %{
        id: rule.transport_id,
        display_name: transports[rule.transport_id],
        version: rule.transport_version
      }
    }
  end

  defp matches?(rule, params) do
    filter_ok?(rule.spacecraft_id, params["spacecraft_id"]) and
      filter_ok?(rule.transport_id, params["transport_id"])
  end

  defp filter_ok?(_value, filter) when filter in [nil, ""], do: true
  defp filter_ok?(value, filter), do: value == filter

  defp limit(nil), do: {:ok, @default_limit}

  defp limit(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n in 1..@max_limit -> {:ok, n}
      _other -> {:error, %{limit: "must be an integer from 1 to #{@max_limit}"}}
    end
  end

  defp offset(nil), do: {:ok, 0}

  defp offset(cursor) do
    case Integer.parse(to_string(cursor)) do
      {n, ""} when n >= 0 -> {:ok, n}
      _other -> {:error, %{cursor: "is not a valid cursor"}}
    end
  end
end
