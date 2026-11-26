defmodule Cadence.Reads.SpacecraftDetail do
  @moduledoc """
  One spacecraft for the Setup detail view: identity, pinned profile (and the
  profile's latest version), routing rules with transport names, their origin
  (`legacy | profile | spacecraft`), the extra route's `route_id` and the station
  (ux U79), and a small set of readiness checks. Callers authorize first.

  Readiness checks: `identity` (SCID set), `profile` (pinned and available),
  `routing` (at least one active, enabled rule), `telemetry` (ever heard).
  Statuses: `ready | blocker | caution | not_set_up`.
  """

  alias Cadence.Comms.{GroundStationStore, RoutingRule}
  alias Cadence.Reads.{FleetStatus, OperationalState, SpacecraftMetadata}
  alias Cadence.{Spacecraft, SpacecraftType}

  @spec load(binary(), binary(), binary()) :: {:ok, map()} | {:error, :spacecraft_not_found}
  def load(organization_id, mission_id, spacecraft_id) do
    with {:ok, %Spacecraft{} = craft} <-
           Cadence.SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      rules =
        organization_id
        |> OperationalState.list_routing_rules(mission_id)
        |> Enum.filter(&(&1.spacecraft_id == spacecraft_id))

      {last_received, telemetry} =
        FleetStatus.last_received_with_status(organization_id, mission_id)

      {:ok,
       %{
         spacecraft: craft,
         profiles: Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id),
         routing_rules: rules,
         transports: OperationalState.list_transports(organization_id, mission_id),
         stations: GroundStationStore.list_ground_stations(organization_id, mission_id),
         last_received_at: Map.get(last_received, spacecraft_id)
       }
       |> build()
       # :degraded: the durable store didn't answer in time; last_received_at is live-only.
       |> Map.put(:telemetry, telemetry)}
    end
  end

  @doc "Pure builder; see `load/3` for the inputs."
  @spec build(map()) :: map()
  def build(%{spacecraft: %Spacecraft{} = craft} = input) do
    latest =
      Enum.find(
        Map.get(input, :profiles, []),
        &(&1.spacecraft_type_id == craft.spacecraft_type_id)
      )

    transports = Map.new(Map.get(input, :transports, []), &{&1.transport_id, &1})
    stations = Map.new(Map.get(input, :stations, []), &{&1.ground_station_id, &1})
    rules = Map.get(input, :routing_rules, [])
    metadata = craft.metadata || %{}
    last_received_at = Map.get(input, :last_received_at)

    %{
      spacecraft: %{
        id: craft.spacecraft_id,
        name: craft.display_name,
        scid: craft.scid,
        norad_id: SpacecraftMetadata.integer(metadata, "norad_id"),
        plane: SpacecraftMetadata.integer(metadata, "plane"),
        slot: SpacecraftMetadata.integer(metadata, "slot"),
        last_received_at: last_received_at
      },
      profile: profile(craft, latest),
      routing_rules:
        rules
        |> Enum.sort_by(&{&1.lifecycle_state != :active, &1.display_name || ""})
        |> Enum.map(&rule(&1, transports, stations)),
      readiness: readiness(craft, latest, rules, last_received_at)
    }
  end

  defp profile(%Spacecraft{spacecraft_type_id: nil}, _latest), do: nil

  defp profile(%Spacecraft{} = craft, latest) do
    %{
      id: craft.spacecraft_type_id,
      name: latest && latest.display_name,
      version: craft.spacecraft_type_version,
      latest_version: latest && latest.version
    }
  end

  defp rule(%RoutingRule{} = rule, transports, stations) do
    transport = Map.get(transports, rule.transport_id)

    %{
      id: rule.routing_rule_id,
      # ux U79: tags read the origin; an extra route's legs share its route_id (Edit/Remove).
      origin: Atom.to_string(rule.origin),
      route_id: if(rule.origin == :spacecraft, do: rule.profile_rule_id),
      station: station(rule.ground_station_id, stations),
      name: rule.display_name,
      purpose: rule.purpose_label,
      direction: rule.direction,
      role: rule.role,
      enabled: rule.enabled?,
      active: rule.lifecycle_state == :active,
      # No version: a route names its transport and the current version resolves at apply
      # (DECISIONS, routing drop (a), 11-16).
      transport: %{id: rule.transport_id, name: transport && transport.display_name}
    }
  end

  # A station that's gone keeps its id; the console words it without a code or name.
  defp station(nil, _stations), do: nil

  defp station(id, stations) do
    case Map.get(stations, id) do
      nil -> %{id: id, code: nil, name: nil}
      station -> %{id: id, code: station.code, name: station.display_name}
    end
  end

  defp readiness(craft, latest, rules, last_received_at) do
    checks = [
      identity_check(craft),
      profile_check(craft, latest),
      routing_check(Enum.count(rules, &usable?/1)),
      telemetry_check(last_received_at)
    ]

    # Ready when identity, profile and routing have no blocker (a caution, such as an older
    # profile version, is still ready), as the directory's `ready` (setup.md).
    %{ready: not Enum.any?(Enum.take(checks, 3), &(&1.status == :blocker)), checks: checks}
  end

  defp identity_check(%Spacecraft{scid: scid}) when is_integer(scid),
    do: check(:identity, :ready, "SCID #{scid}", "The spacecraft has a SCID.")

  defp identity_check(_craft),
    do:
      check(
        :identity,
        :blocker,
        "No SCID",
        "Telemetry and commands can't be matched to it without a SCID."
      )

  defp profile_check(%Spacecraft{spacecraft_type_id: nil}, _latest),
    do: check(:profile, :blocker, "No profile", "Bind a profile so its frames can be decoded.")

  defp profile_check(_craft, nil),
    do: check(:profile, :blocker, "Profile unavailable", "The pinned profile no longer exists.")

  defp profile_check(
         %Spacecraft{spacecraft_type_version: pinned},
         %SpacecraftType{version: latest} = profile
       )
       when is_integer(pinned) and pinned < latest,
       do:
         check(
           :profile,
           :caution,
           "#{profile.display_name} v#{pinned}",
           "Pinned to v#{pinned}; the latest is v#{latest}."
         )

  defp profile_check(_craft, %SpacecraftType{} = profile),
    do: check(:profile, :ready, profile.display_name, "Pinned to the latest version.")

  defp routing_check(0),
    do:
      check(
        :routing,
        :blocker,
        "No routing rule",
        "It can't be contacted until a rule covers it."
      )

  defp routing_check(count),
    do:
      check(
        :routing,
        :ready,
        "#{count} routing #{plural(count, "rule")}",
        "Active, enabled rules cover it."
      )

  defp telemetry_check(nil),
    do: check(:telemetry, :not_set_up, "Never heard", "No telemetry has been received yet.")

  defp telemetry_check(_received),
    do: check(:telemetry, :ready, "Telemetry received", "Telemetry has been received.")

  defp check(key, status, title, body), do: %{key: key, status: status, title: title, body: body}

  defp usable?(%RoutingRule{lifecycle_state: :active, enabled?: true}), do: true
  defp usable?(_rule), do: false

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"
end
