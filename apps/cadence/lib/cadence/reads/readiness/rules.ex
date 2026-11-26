defmodule Cadence.Reads.Readiness.Rules do
  @moduledoc """
  Pure readiness rules: turns mission facts into six area tiles and findings
  grouped by cause. Inputs are plain data gathered by `Cadence.Reads.Readiness`.

  Severities, worst first: `blocker > caution > stale > not_set_up > optional`.
  An area's status is its worst non-optional finding, `ready` when it has none,
  or `unknown` when its facts could not be assessed (never defaulted to ready).
  """

  @area_order [:fleet, :catalog, :comms, :stations, :data_sources, :apps]
  @severity_rank %{blocker: 0, caution: 1, stale: 2, not_set_up: 3, optional: 4}

  @spec build(map()) :: %{areas: [map()], findings: [map()], verdict: map()}
  def build(facts) do
    findings =
      [
        fleet_findings(facts),
        catalog_findings(facts),
        comms_findings(facts),
        routing_findings(facts),
        station_findings(facts),
        data_source_findings(facts),
        endpoint_findings(facts),
        app_findings(facts),
        planning_findings(facts)
      ]
      |> List.flatten()
      |> Enum.sort_by(&{Map.fetch!(@severity_rank, &1.severity), area_index(&1.area)})

    %{
      areas: Enum.map(@area_order, &area(&1, facts, findings)),
      findings: findings,
      verdict:
        Map.new(Map.keys(@severity_rank), fn severity ->
          {severity, Enum.count(findings, &(&1.severity == severity))}
        end)
    }
  end

  # -- findings ---------------------------------------------------------------

  defp fleet_findings(%{fleet: %{total: 0}}) do
    [
      finding(
        :fleet,
        :blocker,
        :no_spacecraft,
        "No spacecraft",
        "Add spacecraft to start operating this mission.",
        0,
        fix(:spacecraft_new)
      )
    ]
  end

  defp fleet_findings(%{fleet: fleet}) do
    [
      count_finding(
        :fleet,
        :blocker,
        :spacecraft_missing_scid,
        fleet.missing_scid,
        "have no SCID",
        "Telemetry and commands can't be matched to them.",
        fix(:spacecraft_list)
      ),
      count_finding(
        :fleet,
        :blocker,
        :spacecraft_without_profile,
        fleet.missing_profile,
        "have no profile",
        "Their frames can't be decoded until a profile is bound.",
        fix(:spacecraft_list)
      ),
      count_finding(
        :fleet,
        :blocker,
        :spacecraft_without_routing_rule,
        fleet.without_routing,
        "have no routing rule",
        "They can't be contacted until a rule covers them.",
        fix(:comms)
      ),
      count_finding(
        :fleet,
        :caution,
        :spacecraft_on_older_profile_version,
        fleet.drifted,
        "are pinned to an older profile version",
        "They miss the latest profile changes.",
        drift_fix(fleet.drifted_profile_ids)
      )
    ]
  end

  defp catalog_findings(%{catalog: %{database_count: 0}}) do
    [
      finding(
        :catalog,
        :blocker,
        :no_catalog,
        "No command and telemetry catalog",
        "Import an XTCE catalog so telemetry can be decoded and commands built.",
        0,
        fix(:catalog_import)
      )
    ]
  end

  defp catalog_findings(%{catalog: %{revision_count: 0}}) do
    [
      finding(
        :catalog,
        :blocker,
        :catalog_without_revision,
        "The catalog has no revisions",
        "Import a catalog file to create the first revision.",
        0,
        fix(:catalog_import)
      )
    ]
  end

  defp catalog_findings(%{catalog: %{not_converged: [_ | _] = mismatches}}) do
    count = length(mismatches)

    [
      Map.put(
        finding(
          :catalog,
          :caution,
          :catalog_not_converged,
          "#{count} #{plural(count, "spacecraft runs", "spacecraft run")} a different catalog than #{plural(count, "its", "their")} profile sets",
          "They keep decoding with their current catalog. A change set that touches them " <>
            "(a pin or an override) moves them onto their profile's catalog.",
          count,
          fix(:change_set)
        ),
        :affected,
        mismatches
      )
    ]
  end

  defp catalog_findings(_facts), do: []

  defp comms_findings(%{comms: %{transport_count: 0}}) do
    [
      finding(
        :comms,
        :blocker,
        :no_transports,
        "No transports",
        "Add a transport so ground stations can reach the spacecraft.",
        0,
        fix(:comms)
      )
    ]
  end

  # DECISIONS #33: profile framing that differs from the transports feeding its spacecraft.
  # Decode still uses the transport values; this tells operators what a profile-authoritative
  # generation would change.
  defp comms_findings(%{comms: %{framing_drift: [_ | _] = drift}}) do
    drift
    |> Enum.group_by(& &1.profile)
    |> Enum.map(fn {profile, items} ->
      count = items |> Enum.map(& &1.spacecraft_count) |> Enum.sum()
      fields = items |> Enum.flat_map(& &1.differences) |> Enum.map(& &1.path) |> Enum.uniq()

      :comms
      |> finding(
        :caution,
        :framing_drift,
        "#{profile.name} framing differs from its transports",
        "#{Enum.join(fields, ", ")} on #{length(items)} transport(s). Decode uses the transport values today.",
        count,
        fix(:profile, profile.id)
      )
      |> Map.put(:id, "comms.framing_drift.#{profile.id}")
    end)
  end

  defp comms_findings(_facts), do: []

  defp routing_findings(%{routing: routing}) do
    [
      count_finding(
        :comms,
        :caution,
        :spacecraft_with_multiple_uplinks,
        routing.multiple_uplinks,
        "have more than one primary uplink route",
        "Cadence can't choose which route carries commands.",
        fix(:comms)
      ),
      count_finding(
        :comms,
        :blocker,
        :spacecraft_without_downlink,
        routing.without_downlink,
        "have no downlink route",
        "Add a downlink route so Cadence can receive their telemetry.",
        fix(:comms)
      ),
      count_finding(
        :comms,
        :caution,
        :spacecraft_with_disabled_route,
        routing.disabled_route,
        "have a disabled route",
        "Review the disabled routes and enable the ones they need.",
        fix(:comms)
      )
    ]
  end

  defp routing_findings(_facts), do: []

  defp station_findings(%{stations: %{count: 0}}) do
    [
      finding(
        :stations,
        :not_set_up,
        :no_ground_stations,
        "No ground stations",
        "Add the stations you contact spacecraft through.",
        0,
        fix(:station)
      )
    ]
  end

  defp station_findings(_facts), do: []

  defp data_source_findings(%{data_sources: %{statuses: statuses}}) do
    statuses
    |> Enum.filter(&(&1.health in [:unavailable, :degraded]))
    |> Enum.group_by(& &1.health)
    |> Enum.map(fn {health, rows} ->
      {severity, noun} =
        if health == :unavailable, do: {:blocker, "unavailable"}, else: {:caution, "degraded"}

      count = length(rows)
      ids = rows |> Enum.map(& &1.data_source_id) |> Enum.uniq()

      finding(
        :data_sources,
        severity,
        :"data_source_#{health}",
        "#{count} data #{plural(count, "source")} #{noun}",
        "Telemetry stored or read through #{plural(count, "it", "them")} may be missing.",
        count,
        if(length(ids) == 1, do: fix(:data_source, hd(ids)), else: fix(:data_source))
      )
    end)
  end

  defp data_source_findings(_facts), do: []

  # L22: which source endpoint carries a spacecraft's telemetry is derived; this is the one case
  # where it can't be.
  defp endpoint_findings(%{data_sources: %{ambiguous_endpoints: [_ | _] = ambiguous}}) do
    count = length(ambiguous)

    [
      Map.put(
        finding(
          :data_sources,
          :caution,
          :source_endpoint_ambiguous,
          "#{count} #{plural(count, "spacecraft has", "spacecraft have")} several source endpoints and none is their own",
          "Cadence can't tell which one carries their telemetry. Retire the extra endpoints in Data sources.",
          count,
          fix(:data_source)
        ),
        :affected,
        ambiguous
      )
    ]
  end

  defp endpoint_findings(_facts), do: []

  # Apps whose absence turns off a safety function are `not_set_up`; the rest
  # are optional (domain decision, Setup.md).
  @essential_apps %{
    "limits" => "Ground limit checks are off. Alarms come only from flight events."
  }

  defp app_findings(%{apps: %{missing: missing}}) do
    Enum.map(missing, fn app ->
      {severity, body} =
        case Map.fetch(@essential_apps, app.key) do
          {:ok, consequence} -> {:not_set_up, consequence}
          :error -> {:optional, app.description || "Install it to enable its features."}
        end

      finding(
        :apps,
        severity,
        :"app_not_installed:#{app.key}",
        "#{app.name} not installed",
        body,
        0,
        fix(:app, app.key)
      )
    end)
  end

  defp app_findings(_facts), do: []

  # Contact planning has no area tile (the six areas are the contract); its
  # finding still shows in the list (DECISIONS #27).
  defp planning_findings(%{planning: %{ready: false, missing: missing}}) do
    [
      finding(
        :planning,
        :not_set_up,
        :planning_not_set_up,
        "Contact planning isn't set up",
        "Drafting contact plans needs " <>
          Enum.map_join(missing, " and ", &missing_label/1) <> ".",
        0,
        fix(:contact_planning)
      )
    ]
  end

  defp planning_findings(_facts), do: []

  defp missing_label("fleet_planning_policy"), do: "an active fleet planning policy"
  defp missing_label("contact_requirements"), do: "at least one contact requirement or template"
  defp missing_label(other), do: other

  # -- areas ------------------------------------------------------------------

  defp area(key, facts, findings) do
    own = Enum.filter(findings, &(&1.area == key))
    tile = tile(key, Map.get(facts, key))

    status =
      cond do
        tile == :unknown -> :unknown
        worst = worst_status(own) -> worst
        not assessable?(key) -> :unknown
        true -> :ready
      end

    tile = if tile == :unknown, do: unknown_tile(key), else: tile
    Map.merge(%{key: key, status: status}, tile)
  end

  # Station health isn't tracked yet, so a mission with stations can't be
  # called ready on that area (never ready by default).
  defp assessable?(:stations), do: false
  defp assessable?(_key), do: true

  defp worst_status(findings) do
    findings
    |> Enum.reject(&(&1.severity == :optional))
    |> Enum.min_by(&Map.fetch!(@severity_rank, &1.severity), fn -> nil end)
    |> case do
      nil -> nil
      finding -> finding.severity
    end
  end

  defp tile(_key, nil), do: :unknown

  defp tile(:fleet, fleet),
    do: tile(fleet.total, "spacecraft", fleet.profile_count, "profiles", fleet_detail(fleet))

  defp tile(:catalog, catalog),
    do:
      tile(
        catalog.revision_count,
        "revisions",
        catalog.database_count,
        "catalogs",
        catalog.latest_label
      )

  defp tile(:comms, comms),
    do: tile(comms.transport_count, "transports", comms.routing_rule_count, "routing rules", nil)

  defp tile(:stations, stations),
    do: tile(stations.count, "stations", nil, nil, "Station health isn't tracked yet.")

  defp tile(:data_sources, %{statuses: []}), do: :unknown

  defp tile(:data_sources, %{statuses: statuses}) do
    healthy = Enum.count(statuses, &(&1.health == :healthy))
    tile(length(statuses), "sources", nil, nil, "#{healthy} of #{length(statuses)} healthy")
  end

  defp tile(:apps, apps),
    do:
      tile(
        apps.installed_count,
        "installed",
        apps.available_count,
        "available",
        missing_apps(apps)
      )

  defp tile(count, unit, secondary_count, secondary_unit, detail),
    do: %{
      count: count,
      unit: unit(count, unit),
      secondary_count: secondary_count,
      secondary_unit: secondary_count && unit(secondary_count, secondary_unit),
      detail: detail
    }

  @singular %{
    "profiles" => "profile",
    "catalogs" => "catalog",
    "revisions" => "revision",
    "transports" => "transport",
    "routing rules" => "routing rule",
    "stations" => "station",
    "sources" => "source"
  }

  defp unit(1, unit), do: Map.get(@singular, unit, unit)
  defp unit(_count, unit), do: unit

  defp unknown_tile(:data_sources),
    do: tile(nil, "sources", nil, nil, "No data-source health has been reported yet.")

  defp unknown_tile(key),
    do: tile(nil, to_string(key), nil, nil, "This area couldn't be assessed.")

  defp missing_apps(%{missing: []}), do: nil
  defp missing_apps(%{missing: [app]}), do: "#{app.name} isn't installed"

  defp missing_apps(%{missing: missing}) do
    {rest, [last]} = missing |> Enum.map(& &1.name) |> Enum.split(-1)
    "#{Enum.join(rest, ", ")} and #{last} aren't installed"
  end

  defp missing_apps(_apps), do: nil

  defp fleet_detail(%{total: 0}), do: nil

  defp fleet_detail(fleet) do
    if fleet.missing_scid + fleet.missing_profile + fleet.without_routing == 0,
      do: "Every spacecraft has a SCID, a profile and a routing rule",
      else: nil
  end

  # -- helpers ----------------------------------------------------------------

  defp count_finding(_area, _severity, _cause, 0, _what, _body, _fix), do: []

  defp count_finding(area, severity, cause, count, what, body, fix) do
    finding(area, severity, cause, "#{count} spacecraft #{what}", body, count, fix)
  end

  defp finding(area, severity, cause, title, body, affected_count, fix) do
    %{
      id: "#{area}.#{cause}",
      area: area,
      severity: severity,
      cause: cause,
      title: title,
      body: body,
      affected_count: affected_count,
      fix: fix
    }
  end

  defp drift_fix([profile_id]), do: fix(:profile, profile_id)
  defp drift_fix(_profile_ids), do: fix(:spacecraft_list)

  defp fix(kind, id \\ nil), do: %{kind: kind, id: id, label: nil}

  defp area_index(area), do: Enum.find_index(@area_order, &(&1 == area)) || length(@area_order)

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"
  defp plural(1, one, _many), do: one
  defp plural(_count, _one, many), do: many
end
