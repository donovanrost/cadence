defmodule Cadence.Reads.Readiness do
  @moduledoc """
  Mission setup readiness: six area tiles (fleet, catalog, comms, stations,
  data sources, apps) and findings grouped by cause, each with a typed fix
  target. The rules live in `Cadence.Reads.Readiness.Rules`.

  `evaluate/2` is unscoped and does Repo reads only (no PubSub, processes or
  caches) through each context's public read functions, so it can run inside a sandboxed change-set preview. `mission/2`
  authorizes first.
  """

  alias Cadence.Applications.ApplicationDefinition
  alias Cadence.Applications.ApplicationInstallations
  alias Cadence.Applications.SpacecraftConfiguration.{CatalogAuthority, Drafts}
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Comms.{
    FramingDrift,
    GroundStationStore,
    RoutingRuleStore,
    TransportStore
  }

  alias Cadence.DataSources.SourceHealthStatus
  alias Cadence.Projections.DataSources.Health
  alias Cadence.Reads.PlanningSetup
  alias Cadence.Reads.Readiness.Rules
  alias Cadence.SourceEndpoints

  @spec mission(Scope.t(), binary()) :: {:ok, map()} | {:error, term()}
  def mission(%Scope{organization_id: organization_id} = scope, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: organization_id,
             mission_id: mission_id
           }),
         {:ok, _mission} <- Cadence.Missions.fetch_mission(organization_id, mission_id) do
      {:ok, evaluate(organization_id, mission_id)}
    end
  end

  def mission(%Scope{}, _mission_id), do: {:error, :forbidden}

  @spec evaluate(binary(), binary()) :: map()
  def evaluate(organization_id, mission_id) do
    routing = RoutingRuleStore.readiness_counts(organization_id, mission_id)

    organization_id
    |> facts(mission_id, routing)
    |> Rules.build()
    |> Map.put(:evaluated_at, DateTime.utc_now())
  end

  defp facts(organization_id, mission_id, routing) do
    %{
      fleet: fleet(organization_id, mission_id, routing.without_routing),
      catalog: catalog(organization_id, mission_id),
      comms: %{
        transport_count: length(TransportStore.list_transports(organization_id, mission_id)),
        routing_rule_count: routing.routing_rule_count,
        framing_drift: FramingDrift.audit(organization_id, mission_id)
      },
      routing: routing,
      stations: %{
        count: length(GroundStationStore.list_ground_stations(organization_id, mission_id))
      },
      data_sources: %{
        statuses: data_source_statuses(organization_id, mission_id),
        ambiguous_endpoints: ambiguous_endpoints(organization_id, mission_id)
      },
      apps: apps(organization_id, mission_id),
      planning: PlanningSetup.setup(organization_id, mission_id)
    }
  end

  defp fleet(organization_id, mission_id, without_routing) do
    summary = Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id)
    profiles = Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)
    latest = Map.new(profiles, &{&1.spacecraft_type_id, &1.version})

    drifted =
      Enum.filter(summary.profile_version_counts, fn count ->
        version = latest[count.spacecraft_type_id]
        is_integer(version) and count.spacecraft_type_version < version
      end)

    %{
      total: summary.total,
      missing_scid: summary.missing_scid,
      missing_profile: summary.missing_profile,
      without_routing: without_routing,
      drifted: drifted |> Enum.map(& &1.count) |> Enum.sum(),
      drifted_profile_ids: drifted |> Enum.map(& &1.spacecraft_type_id) |> Enum.uniq(),
      profile_count: length(profiles)
    }
  end

  defp catalog(organization_id, mission_id) do
    databases = Cadence.Catalog.list_databases(organization_id, mission_id)
    revisions = Cadence.Catalog.list_revisions(organization_id, mission_id)

    %{
      database_count: length(databases),
      revision_count: length(revisions),
      latest_label: latest_label(organization_id, mission_id, List.first(revisions)),
      # DECISIONS #65: spacecraft not yet on the catalog their profile sets.
      not_converged: CatalogAuthority.mismatches(organization_id, mission_id)
    }
  end

  # "rev N" for catalog revisions; "rN" is reserved for mission config revisions.
  defp latest_label(_organization_id, _mission_id, nil), do: nil

  defp latest_label(organization_id, mission_id, %{catalog_revision_id: id, revision_number: n}) do
    used_by =
      organization_id
      |> Drafts.catalog_usage_entries(mission_id)
      |> Enum.count(&(&1.catalog_revision_id == id))

    if used_by > 0, do: "rev #{n} · used by #{used_by} spacecraft", else: "rev #{n}"
  end

  # L22: a spacecraft's telemetry source endpoint is derived (its only one, or its managed
  # runtime one) unless its decode configuration names one. Several endpoints, none managed and
  # none named: Cadence can't tell which carries its telemetry.
  defp ambiguous_endpoints(organization_id, mission_id) do
    ambiguous =
      organization_id
      |> SourceEndpoints.list_source_endpoints(mission_id)
      |> Enum.group_by(& &1.spacecraft_id)
      |> Enum.filter(fn {spacecraft_id, endpoints} ->
        is_binary(spacecraft_id) and length(endpoints) > 1 and
          not Enum.any?(endpoints, &TelemetryDecom.managed_runtime_source_endpoint?/1)
      end)

    ambiguous
    |> exclude_named_endpoints(organization_id, mission_id)
    |> Enum.map(fn {spacecraft_id, endpoints} ->
      %{
        spacecraft_id: spacecraft_id,
        source_endpoint_ids: Enum.map(endpoints, & &1.source_endpoint_id)
      }
    end)
    |> Enum.sort_by(& &1.spacecraft_id)
  end

  defp exclude_named_endpoints([], _organization_id, _mission_id), do: []

  defp exclude_named_endpoints(ambiguous, organization_id, mission_id) do
    named =
      for config <- TelemetryDecom.list_configs(organization_id, mission_id),
          is_binary(config.source_endpoint_id),
          into: MapSet.new(),
          do: config.spacecraft_id

    Enum.reject(ambiguous, fn {id, _endpoints} -> MapSet.member?(named, id) end)
  end

  defp data_source_statuses(organization_id, mission_id) do
    organization_id
    |> Health.list_source_health_statuses(mission_id)
    |> Enum.filter(fn %SourceHealthStatus{replay_run_id: replay} -> is_nil(replay) end)
    # Health as classified now: a read-derived status older than its short window reads unknown,
    # so one slow read doesn't leave a blocker on Now for a day (qa/api-ops 11-14).
    |> Enum.map(
      &%{data_source_id: &1.data_source_id, health: Health.classify_status(&1).source_health}
    )
  end

  defp apps(organization_id, mission_id) do
    installed =
      organization_id
      |> ApplicationInstallations.settings_application_keys(mission_id)
      |> MapSet.new()

    optional =
      :mission
      |> Cadence.ExtensionCatalog.available_applications_for_scope()
      |> Enum.filter(fn %ApplicationDefinition{} = app ->
        app.installation_policy == :optional and :mission in app.installable_scopes
      end)

    %{
      installed_count: Enum.count(optional, &MapSet.member?(installed, &1.application_key)),
      available_count: length(optional),
      missing:
        optional
        |> Enum.reject(&MapSet.member?(installed, &1.application_key))
        |> Enum.map(
          &%{key: &1.application_key, name: &1.display_name, description: &1.description}
        )
    }
  end
end
