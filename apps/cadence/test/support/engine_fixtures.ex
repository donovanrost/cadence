defmodule Cadence.Dashboards.EngineFixtures do
  @moduledoc false

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    Document
  }

  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Telemetry.Sample

  @fixture_dir Path.expand("../fixtures/dashboards", __DIR__)

  def resolve_request(%Document{} = document, overrides \\ []) do
    attrs =
      %{
        organization_id: document.organization_id,
        mission_id: document.mission_id,
        dashboard_id: document.dashboard_id,
        document: document,
        scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
      }

    struct!(DashboardResolveRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  def source_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.values()
  end

  def source_cache_statuses(result) do
    result
    |> source_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  def source_cache_entry_by_source(result, logical_source) do
    request = request_by_source(result.planned_source_requests, logical_source)

    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.fetch!(request.request_id)
  end

  def frame_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :frame_cache_by_placement])
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
  end

  def frame_cache_statuses(result) do
    result
    |> frame_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  def telemetry_latest_values(result) do
    result.frames_by_placement
    |> Map.fetch!("placement_battery_voltage")
    |> Map.fetch!(:primary)
    |> List.first()
    |> Map.fetch!(:fields)
    |> Enum.find(&(&1.name == "tlm.hk.battery_voltage"))
    |> Map.fetch!(:values)
  end

  def telemetry_sample(mission_id, point_id, value \\ 12.25) do
    %Sample{
      sample_id: "sample-cache-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-1",
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  def limit_event(mission_id, point_id) do
    %Event{
      limit_event_id: "limit-cache-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-cache-1",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 12.25,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  def limit_definition_interval(mission_id, point_id) do
    %DefinitionInterval{
      definition_activation_key: "limit-activation-cache-1",
      limit_definition_lifecycle_event_id: "limit-lifecycle-cache-1",
      organization_id: "org_dashboards",
      mission_id: mission_id,
      point_id: point_id,
      limit_set_name: "ops",
      event_type: :registered,
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      active_from: ~U[2026-06-17 12:00:00Z],
      active_to: nil,
      observed_at: ~U[2026-06-17 12:00:00Z],
      thresholds: %{"yellow_high" => 15, "red_high" => 25},
      metadata: %{},
      complete?: true
    }
  end

  def best_effort_watermark(cursor) do
    {:ok,
     %{
       complete_through: cursor,
       latest_receipt_time: cursor,
       retention_starts_at: ~U[2026-06-17 11:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  def request_by_source(requests, logical_source) do
    Enum.find(requests, &(&1.logical_source == logical_source))
  end

  def request_by_source_product(requests, logical_source, product) do
    Enum.find(requests, fn request ->
      request.logical_source == logical_source and
        product in Map.get(request.sampling, :products, [])
    end)
  end

  def telemetry_data_source(data_source_id, capabilities) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: Map.new(capabilities)
    }
  end

  def test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  def limits_data_source do
    %DataSource{
      data_source_id: "managed_limits_projection",
      adapter: Cadence.Dashboards.Sources.Limits,
      kind: :projection,
      capabilities: %{latest_state?: true, event_history?: true, definition_intervals?: true}
    }
  end

  def events_data_source do
    %DataSource{
      data_source_id: "managed_events_projection",
      adapter: Cadence.Dashboards.Sources.Events,
      kind: :projection,
      capabilities: %{
        contact_intervals?: true,
        mission_timeline?: true,
        source_health_transitions?: true
      }
    }
  end

  def telemetry_binding(data_source_id, realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm)
    }
  end

  def limits_binding(realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-limits",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :limits,
      data_source_id: "managed_limits_projection",
      dataset: "telemetry_latest_limit_states"
    }
  end

  def events_binding(realm \\ :flight) do
    %DataBinding{
      binding_id: "flight-events",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: realm,
      logical_source: :events,
      data_source_id: "managed_events_projection",
      dataset: "mission_events"
    }
  end

  def load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> Dashboards.load_document!()
  end

  def mixed_latest_and_history_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    history_placement =
      put_in(history_placement, ["content", "widget_def", "binding", "sampling"], "raw_series")

    latest_attrs
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  def mixed_telemetry_execution_document do
    latest_attrs = load_fixture_map!("value_tile_latest.v1.json")
    [latest_placement] = latest_attrs["placements"]
    [history_placement] = load_fixture_map!("time_series_with_limits.v1.json")["placements"]

    latest_placement =
      put_in(latest_placement, ["content", "widget_def", "binding", "overlays"], [])

    history_placement =
      history_placement
      |> put_in(["content", "widget_def", "binding", "sampling"], "raw_series")
      |> put_in(["content", "widget_def", "binding", "overlays"], [])

    latest_attrs
    |> Map.put("placements", [latest_placement, history_placement])
    |> Document.from_map()
  end

  def load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
