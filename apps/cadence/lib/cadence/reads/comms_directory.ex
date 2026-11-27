defmodule Cadence.Reads.CommsDirectory do
  @moduledoc """
  Ground stations, transports and routing rules for the Setup comms screens.
  Edits go through mission change sets (`ground_station` / `transport` kinds);
  these are the reads. Callers authorize first.

  The model has no station↔transport link, so a station's `transport_count`
  and a transport's `station` are `nil` (unknown) rather than invented.
  """

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    StationCode,
    Transport,
    TransportStore
  }

  alias Cadence.Auth.Scope
  alias Cadence.Configuration.Kinds

  alias Cadence.GroundNetworks.{
    EphemerisStates,
    ProviderAccountGrants,
    ProviderAccounts
  }

  alias Cadence.Reads.Comms.ProviderHealth
  alias Cadence.Reads.OperationalState

  @default_limit 100
  @max_limit 500

  @spec stations(binary(), binary(), keyword()) :: [map()]
  def stations(organization_id, mission_id, opts \\ []) do
    stations =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id, opts)
      |> archived_last()

    taken = stations |> Enum.map(& &1.code) |> Enum.reject(&is_nil/1)

    stations
    |> Enum.map(fn %GroundStation{} = station ->
      %{
        id: station.ground_station_id,
        display_name: station.display_name,
        code: station.code,
        # U25: never invent a code; offer one only where none is set.
        suggested_code:
          if(is_nil(station.code), do: StationCode.suggest(station.display_name, taken)),
        provider: station.provider,
        region: station.region,
        lifecycle_state: station.lifecycle_state,
        transport_count: nil,
        routing_rule_count: nil,
        health: nil,
        # #890: the location pass prediction uses (the mission's, else the provider's), the
        # provider's own report, and the elevation mask.
        location: GroundStation.effective_location(station),
        provider_location: provider_location(station.provider_location),
        elevation_mask_deg: station.elevation_mask_deg
      }
    end)
  end

  defp provider_location(nil), do: nil

  defp provider_location(location),
    do: Map.take(location, [:latitude_deg, :longitude_deg, :height_m, :reported_at])

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

    grants = grant_states(organization_id, mission_id)
    ephemeris = EphemerisStates.buckets(organization_id, mission_id)

    organization_id
    |> Cadence.GroundNetworks.list_providers(mission_id)
    |> Enum.map(&provider_row(scope, &1, station_counts, grants, ephemeris))
  end

  @doc "One provider's row, as `providers/2` lists it (L12 writes answer with it)."
  @spec provider(Scope.t(), struct()) :: map()
  def provider(scope, provider) do
    station_counts =
      scope.organization_id
      |> GroundStationStore.list_ground_stations(provider.mission_id)
      |> Enum.frequencies_by(& &1.provider)

    provider_row(
      scope,
      provider,
      station_counts,
      grant_states(scope.organization_id, provider.mission_id),
      EphemerisStates.buckets(scope.organization_id, provider.mission_id)
    )
  end

  defp provider_row(scope, provider, station_counts, grants, ephemeris) do
    %{
      id: provider.provider_id,
      name: provider.display_name,
      provider_type: provider.provider_type,
      version: provider.version,
      # A policy without a mode is approval_required, as DeliveryPolicy.normalize/1 reads it.
      policy_mode: (provider.delivery_policy_document || %{})["mode"] || "approval_required",
      # null for a direct binding (no account; grant is null too). fe-setup 377e08c79.
      account:
        provider.provider_account_id &&
          %{
            id: provider.provider_account_id,
            name: account_name(scope, provider.provider_account_id)
          },
      grant:
        provider.provider_account_grant_id &&
          %{
            id: provider.provider_account_grant_id,
            version: provider.provider_account_grant_version,
            state: Map.get(grants, provider.provider_account_grant_id, :revoked)
          },
      status: %{
        lifecycle_state: provider.lifecycle_state,
        last_validated_at: provider.last_validated_at,
        last_synced_at: provider.last_synced_at
      },
      health: ProviderHealth.of(provider),
      station_count: Map.get(station_counts, provider.display_name, 0),
      ephemeris: ephemeris(provider, Map.get(ephemeris, provider.provider_id, %{}))
    }
  end

  # How the provider gets orbits (#968) and its bound spacecraft with a current element set, by
  # bucket (`EphemerisStates.buckets/2`). Counts, never rows (500 floor). `orbit_source` is what
  # the provider declared: nil when it declared nothing, though it then behaves as lookup.
  @orbit_sources ~w(accepts_ephemeris_upload looks_up_by_norad_id)

  defp ephemeris(provider, buckets) do
    declared = get_in(provider.capabilities_document || %{}, ["orbit", "source"])

    %{
      orbit_source: if(declared in @orbit_sources, do: declared),
      uploaded: Map.get(buckets, "uploaded", 0),
      failed: Map.get(buckets, "failed", 0),
      pending: Map.get(buckets, "pending", 0),
      not_ready: Map.get(buckets, "not_ready", 0),
      lookup: Map.get(buckets, "lookup", 0),
      norad_id_missing: Map.get(buckets, "norad_id_missing", 0)
    }
  end

  # The grant's current state; a grant with no active version reads as revoked.
  defp grant_states(organization_id, mission_id) do
    organization_id
    |> ProviderAccountGrants.list_for_mission(mission_id, active_only?: false)
    |> Map.new(&{&1.provider_account_grant_id, &1.lifecycle_state})
  end

  defp account_name(scope, account_id) do
    case ProviderAccounts.fetch(scope, account_id) do
      {:ok, account, _version} -> account.display_name
      _unavailable -> nil
    end
  end

  @spec transports(binary(), binary(), keyword()) :: [map()]
  def transports(organization_id, mission_id, opts \\ []) do
    rule_counts =
      organization_id
      |> OperationalState.list_routing_rules(mission_id)
      |> Enum.filter(&(&1.lifecycle_state == :active))
      |> Enum.frequencies_by(& &1.transport_id)

    organization_id
    |> TransportStore.list_transports(mission_id, opts)
    |> archived_last()
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

  @doc """
  Active routing rules grouped by transport, direction and role (ux pass-2 #10), so a
  thousand per-spacecraft rules read as a few lines:
  `[%{transport: %{id, name}, direction, role, enabled_count, disabled_count, spacecraft_count}]`.
  """
  @spec routing_rule_groups(binary(), binary()) :: [map()]
  def routing_rule_groups(organization_id, mission_id) do
    transports =
      organization_id
      |> TransportStore.list_transports(mission_id)
      |> Map.new(&{&1.transport_id, &1.display_name})

    organization_id
    |> OperationalState.list_routing_rules(mission_id)
    |> group_rules(transports)
  end

  @doc "Pure: active `rules` grouped, with `transports` mapping ids to names."
  @spec group_rules([RoutingRule.t()], map()) :: [map()]
  def group_rules(rules, transports) do
    rules
    |> Enum.filter(&(&1.lifecycle_state == :active))
    |> Enum.group_by(&{&1.transport_id, &1.direction, &1.role})
    |> Enum.map(fn {{transport_id, direction, role}, rules} ->
      enabled = Enum.count(rules, & &1.enabled?)

      %{
        # An archived transport has no name in the active list; its id keeps `name` non-null.
        transport: %{id: transport_id, name: transports[transport_id] || transport_id},
        direction: direction,
        role: role,
        enabled_count: enabled,
        disabled_count: length(rules) - enabled,
        spacecraft_count: rules |> Enum.map(& &1.spacecraft_id) |> Enum.uniq() |> length()
      }
    end)
    |> Enum.sort_by(&{&1.transport.name || "", to_string(&1.direction), to_string(&1.role)})
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

  # U82: with ?include_archived, archived rows follow the active ones (each group keeps its order).
  defp archived_last(rows), do: Enum.sort_by(rows, &(&1.lifecycle_state == :archived))
end
