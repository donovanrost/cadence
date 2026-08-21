defmodule Cadence.Dashboards.DataSourcesDefaultCacheCompatibilityTest do
  use Cadence.ConfigCase, async: false

  import Cadence.DataSourcesFixtures

  alias Cadence.Dashboards.{DataSourceRegistry, RuntimeCache}
  alias Cadence.Management.DataSources

  alias Cadence.DataSources.DataBinding

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    RuntimeCache.reset()
    on_exit(&RuntimeCache.reset/0)
    :ok
  end

  test "bootstraps default managed telemetry source idempotently" do
    assert %{data_source: data_source, data_binding: data_binding} =
             DataSources.ensure_default_managed_sources!()

    assert data_source.data_source_id == "managed_questdb_primary"
    assert data_source.kind == :managed_tsdb
    assert data_source.adapter == :telemetry
    assert data_source.isolation_level == :shared
    assert data_source.metadata["bootstrap_default?"]

    assert data_binding.binding_id == "default_flight_telemetry"
    assert data_binding.realm == :flight
    assert data_binding.logical_source == :telemetry
    assert data_binding.data_source_id == "managed_questdb_primary"
    assert data_binding.dataset == "flight"
    assert data_binding.metadata["bootstrap_default?"]

    assert limits_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_limits_projection")
             )

    assert limits_source.kind == :projection
    assert limits_source.adapter == :limits
    assert limits_source.capabilities["latest_state?"]
    assert limits_source.capabilities["definition_intervals?"]
    assert limits_source.metadata["bootstrap_default?"]

    assert limits_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_limits")
             )

    assert limits_binding.realm == :flight
    assert limits_binding.logical_source == :limits
    assert limits_binding.data_source_id == "managed_limits_projection"
    assert limits_binding.dataset == "telemetry_latest_limit_states"
    assert limits_binding.metadata["bootstrap_default?"]

    assert events_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_events_projection")
             )

    assert events_source.kind == :projection
    assert events_source.adapter == :events
    assert events_source.capabilities["contact_intervals?"]
    assert events_source.capabilities["mission_timeline?"]
    assert events_source.capabilities["source_health_transitions?"]
    assert events_source.metadata["bootstrap_default?"]

    assert events_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_events")
             )

    assert events_binding.realm == :flight
    assert events_binding.logical_source == :events
    assert events_binding.data_source_id == "managed_events_projection"
    assert events_binding.dataset == "mission_events"
    assert events_binding.metadata["bootstrap_default?"]

    assert %{data_source: second_source, data_binding: second_binding} =
             DataSources.ensure_default_managed_sources!()

    assert second_source.data_source_id == data_source.data_source_id
    assert second_binding.binding_id == data_binding.binding_id
  end

  test "persisted registry resolves from bootstrapped defaults" do
    _defaults = DataSources.ensure_default_managed_sources!()

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "default_flight_telemetry"
    assert resolved.data_source.data_source_id == "managed_questdb_primary"
    assert resolved.realm == :flight
    assert resolved.dataset == "flight"

    assert {:ok, limits_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :limits, sampling: %{mode: :latest_state}),
               persisted?: true
             )

    assert limits_resolved.binding.binding_id == "default_flight_limits"
    assert limits_resolved.data_source.data_source_id == "managed_limits_projection"
    assert limits_resolved.realm == :flight
    assert limits_resolved.dataset == "telemetry_latest_limit_states"

    assert {:ok, events_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :events, sampling: %{mode: :event_history}),
               persisted?: true
             )

    assert events_resolved.binding.binding_id == "default_flight_events"
    assert events_resolved.data_source.data_source_id == "managed_events_projection"
    assert events_resolved.realm == :flight
    assert events_resolved.dataset == "mission_events"
  end

  test "persisting a data binding invalidates matching default runtime caches only" do
    persist_source("mission-questdb", :mission_isolated)
    persist_limits_source("mission-limits")

    matching_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-flight-telemetry",
        data_source_id: "mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    matching_frame_key = dashboard_frame_key(matching_key, "frame-mission-flight")

    other_realm_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-rehearsal-telemetry",
        data_source_id: "mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    other_realm_frame_key = dashboard_frame_key(other_realm_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "mission-flight-limits",
        data_source_id: "mission-limits",
        realm: :flight,
        dataset: "telemetry_latest_limit_states"
      )

    limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")

    matching_result = dashboard_source_result(matching_key)
    matching_frames = dashboard_frames(:telemetry, "frame-mission-flight")
    other_realm_result = dashboard_source_result(other_realm_key)
    other_realm_frames = dashboard_frames(:telemetry, "frame-rehearsal")
    limits_result = dashboard_source_result(limits_key)
    limits_frames = dashboard_frames(:limits, "frame-limits")

    assert :ok = RuntimeCache.put_source_result(matching_key, matching_result)
    assert :ok = RuntimeCache.put_frame(matching_frame_key, matching_frames)
    assert :ok = RuntimeCache.put_source_result(other_realm_key, other_realm_result)
    assert :ok = RuntimeCache.put_frame(other_realm_frame_key, other_realm_frames)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames)

    assert {:ok, binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "mission-flight",
               priority: 0,
               metadata: %{reason: :updated_primary}
             })

    assert RuntimeCache.get_source_result(matching_key) == :miss
    assert RuntimeCache.get_frame(matching_frame_key) == :miss
    assert {:ok, ^other_realm_result} = RuntimeCache.get_source_result(other_realm_key)
    assert {:ok, ^other_realm_frames} = RuntimeCache.get_frame(other_realm_frame_key)
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key)

    assert [event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert event.event_type == :registered
    assert binding.current_event_id == event.data_binding_event_id
  end
end
