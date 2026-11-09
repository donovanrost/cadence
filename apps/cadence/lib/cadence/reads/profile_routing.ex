defmodule Cadence.Reads.ProfileRouting do
  @moduledoc """
  Profile routing (P2) and overrides (P3) for the Setup profile page
  (`docs/apogee/domain/profile-routing.md` §5). Callers authorize first.

  - `rules/3`: the profile's rules with station codes, legs, the number of routes they
    generate for spacecraft on the current version, and three sample route names.
  - `overrides/3`: every override held by a spacecraft on the profile, with the profile value it
    replaces, "since rN" from the change-set ledger (nil when set outside change sets), and
    `redundant` when it now equals the profile value.
  """

  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore}
  alias Cadence.Configuration.Ledger
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftType.Schema

  @samples 3

  @spec rules(String.t(), String.t(), SpacecraftType.t()) :: [map()]
  def rules(organization_id, mission_id, %SpacecraftType{} = profile) do
    stations =
      organization_id
      |> GroundStationStore.list_ground_stations(mission_id)
      |> Map.new(&{&1.ground_station_id, &1})

    counts =
      RoutingRuleStore.profile_route_counts(
        organization_id,
        mission_id,
        profile.spacecraft_type_id,
        profile.version
      )

    Enum.map(profile.routing_rules, fn rule ->
      %{
        id: rule["id"],
        label: rule["label"],
        name_template: rule["name_template"],
        enabled: rule["enabled"],
        stations: Enum.map(rule["stations"], &station(&1, stations)),
        legs:
          Enum.map(rule["legs"], &%{direction: &1["direction"], role: &1["role"] || "primary"}),
        route_count: Map.get(counts, rule["id"], 0),
        samples:
          RoutingRuleStore.profile_route_samples(
            organization_id,
            mission_id,
            profile.spacecraft_type_id,
            profile.version,
            rule["id"],
            @samples
          )
      }
    end)
  end

  @spec overrides(String.t(), String.t(), SpacecraftType.t()) :: [map()]
  def overrides(organization_id, mission_id, %SpacecraftType{} = profile) do
    spacecraft =
      SpacecraftStore.list_pinned_to_profile(
        organization_id,
        mission_id,
        profile.spacecraft_type_id
      )

    by_id = Map.new(spacecraft, &{&1.spacecraft_id, &1})
    overrides = Overrides.list(organization_id, mission_id, Map.keys(by_id))

    for {spacecraft_id, paths} <- overrides,
        {path, override} <- paths do
      profile_value = profile_value(profile, path)

      %{
        spacecraft: %{id: spacecraft_id, name: by_id[spacecraft_id].display_name},
        section: section(path),
        path: path,
        profile_value: profile_value,
        spacecraft_value: override.value,
        reason: override.reason,
        since_revision: since(mission_id, spacecraft_id, path),
        set_at: override.set_at,
        actor: override.set_by,
        redundant: profile_value == override.value
      }
    end
    |> Enum.sort_by(&{&1.spacecraft.name, &1.path})
  end

  defp station(%{"ground_station_id" => id, "transport_id" => transport}, stations) do
    case Map.get(stations, id) do
      nil ->
        %{id: id, code: nil, name: nil, transport_id: transport}

      station ->
        %{id: id, code: station.code, name: station.display_name, transport_id: transport}
    end
  end

  defp profile_value(profile, "routing." <> rest) do
    [rule_id, field] = String.split(rest, ".", parts: 2)

    case Enum.find(profile.routing_rules, &(&1["id"] == rule_id)) do
      nil -> nil
      _rule when field == "excluded_stations" -> []
      rule -> rule["enabled"]
    end
  end

  defp profile_value(profile, path), do: Schema.value(profile, path)

  defp section("routing." <> _), do: :routing
  defp section("frame_parameters." <> _), do: :framing
  defp section(path) when path in ["downlink_protocol", "uplink_protocol"], do: :framing
  defp section("catalog_revision_id"), do: :catalog
  defp section(_path), do: :other

  # The newest change-set revision that set or changed this override.
  defp since(mission_id, spacecraft_id, path) do
    key = String.replace(path, ".", "/")

    mission_id
    |> Ledger.entity_entries("spacecraft_override", spacecraft_id)
    |> Enum.find(
      &(key in &1.paths or Enum.any?(&1.paths, fn p -> String.starts_with?(p, key <> ".") end))
    )
    |> case do
      nil -> nil
      entry -> entry.revision_number
    end
  end
end
