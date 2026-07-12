defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormPresentationTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Dashboards.OperationalObservable
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation

  test "exposes stable widget type, mode, precision, and window options" do
    assert WidgetFormPresentation.type_options() == [
             {"Value tile", "value_tile"},
             {"Time series chart", "time_series"},
             {"Status matrix", "status_matrix"},
             {"Data table", "data_table"},
             {"State timeline", "state_timeline"},
             {"Event timeline", "event_timeline"},
             {"Constellation health", "constellation_health"}
           ]

    assert WidgetFormPresentation.mode_options() == [
             {"Follow dashboard context", "context"},
             {"Pin current dashboard context", "scope"},
             {"Pin to one spacecraft", "fixed"}
           ]

    assert WidgetFormPresentation.precision_options() == [
             {"0 decimals", "0"},
             {"1 decimals", "1"},
             {"2 decimals", "2"},
             {"3 decimals", "3"},
             {"4 decimals", "4"},
             {"5 decimals", "5"},
             {"6 decimals", "6"}
           ]

    assert WidgetFormPresentation.window_options() == [
             {"5 minutes", "300"},
             {"15 minutes", "900"},
             {"1 hour", "3600"},
             {"1 minute", "60"}
           ]
  end

  test "exposes pinned scope options and summaries from the active dashboard context" do
    form =
      to_form(
        %{"type" => "state_timeline", "binding_source" => "operational_observables"},
        as: :widget
      )

    scope_context = %{primary: %{kind: "ground_station", mode: "one", ids: ["ground-1"]}}

    assert WidgetFormPresentation.mode_options(form) == [
             {"Follow dashboard context", "context"},
             {"Pin current dashboard context", "scope"}
           ]

    assert WidgetFormPresentation.scope_override_kind(scope_context) == :ground_station
    assert WidgetFormPresentation.scope_override_id(scope_context) == "ground-1"
    assert WidgetFormPresentation.scope_override_available?(scope_context)

    assert WidgetFormPresentation.scope_override_summary(scope_context) ==
             "Pins this widget to ground station ground-1."

    refute WidgetFormPresentation.scope_override_available?(nil)

    assert WidgetFormPresentation.scope_override_summary(nil) ==
             "Choose a dashboard context before pinning this widget."
  end

  test "resolves supported binding source options from widget frame contracts" do
    value_tile = to_form(%{"type" => "value_tile"}, as: :widget)
    state_timeline = to_form(%{"type" => "state_timeline"}, as: :widget)
    event_timeline = to_form(%{"type" => "event_timeline"}, as: :widget)
    unknown = to_form(%{"type" => "unknown"}, as: :widget)

    assert WidgetFormPresentation.binding_source_options(value_tile) == [
             {"Telemetry points", "telemetry"},
             {"Operational observables", "operational_observables"}
           ]

    assert WidgetFormPresentation.binding_source_options(state_timeline) == [
             {"Telemetry limit history", "limits"},
             {"Operational observables", "operational_observables"}
           ]

    assert WidgetFormPresentation.binding_source_options(event_timeline) == [
             {"Events", "events"}
           ]

    assert WidgetFormPresentation.binding_source_options(unknown) == [
             {"Telemetry points", "telemetry"}
           ]
  end

  test "derives binding source and picker shape from the active widget form" do
    value_tile = to_form(%{"type" => "value_tile", "binding_source" => ""}, as: :widget)

    state_timeline_operational =
      to_form(
        %{"type" => "state_timeline", "binding_source" => "operational_observables"},
        as: :widget
      )

    event_timeline = to_form(%{"type" => "event_timeline"}, as: :widget)

    assert WidgetFormPresentation.point_widget?(value_tile)
    assert WidgetFormPresentation.binding_source_value(value_tile) == "telemetry"
    assert WidgetFormPresentation.binding_source_select?(value_tile)
    refute WidgetFormPresentation.multi_point_widget?(value_tile)

    assert WidgetFormPresentation.point_widget?(state_timeline_operational)
    assert WidgetFormPresentation.operational_observable_widget?(state_timeline_operational)
    assert WidgetFormPresentation.multi_point_widget?(state_timeline_operational)

    assert WidgetFormPresentation.point_picker_legend(state_timeline_operational) ==
             "Telemetry Points"

    refute WidgetFormPresentation.point_widget?(event_timeline)
    refute WidgetFormPresentation.binding_source_select?(event_timeline)

    assert WidgetFormPresentation.non_point_widget_help(event_timeline) =~
             "Event timelines render"
  end

  test "filters and selects telemetry points" do
    points = [
      %{point_id: "HK.temp", description: "Battery temperature", unit: "degC"},
      %{point_id: "HK.voltage", description: "Bus voltage", unit: "V"}
    ]

    assert WidgetFormPresentation.filter_points(points, "temp") == [Enum.at(points, 0)]
    assert WidgetFormPresentation.filter_points(points, "bus") == [Enum.at(points, 1)]
    assert WidgetFormPresentation.selected_point(points, "HK.voltage") == Enum.at(points, 1)
    assert WidgetFormPresentation.selected_point(points, "missing") == nil

    assert WidgetFormPresentation.selected_points(points, ["HK.voltage", "missing", "HK.temp"]) ==
             [
               Enum.at(points, 1),
               Enum.at(points, 0)
             ]
  end

  test "filters operational observables through widget compatibility constraints" do
    observables = OperationalObservable.list()

    state_timeline_results =
      WidgetFormPresentation.filter_operational_observables(
        observables,
        nil,
        "state_timeline"
      )

    assert Enum.map(state_timeline_results, & &1.observable_id) == [
             "comms.transport.execution_state",
             "comms.transport.connection_state",
             "ground.station.connection_state",
             "ground.station.antenna_pointing_state",
             "link.rf_lock_state",
             "link.frame_sync_state",
             "contacts.phase",
             "runtime.managed_activity",
             "runtime.transport_activity"
           ]

    assert WidgetFormPresentation.filter_operational_observables(
             observables,
             "latency",
             "state_timeline"
           ) == []

    assert [
             %OperationalObservable{observable_id: "ingress.processing_latency_ms"}
           ] =
             WidgetFormPresentation.filter_operational_observables(
               observables,
               "latency",
               "value_tile"
             )
  end

  test "groups operational time-series observables by source capability product family" do
    form =
      to_form(
        %{"type" => "time_series", "binding_source" => "operational_observables"},
        as: :widget
      )

    observables =
      OperationalObservable.list()
      |> WidgetFormPresentation.filter_operational_observables(nil, "time_series")

    assert [
             %{
               id: "link_rf_metric_history",
               label: "link RF metric history",
               product: :link_rf_metric_history,
               product_family: :link_rf,
               source_product_value: "link_rf_metric_history",
               product_family_value: "link_rf",
               observables: [
                 %OperationalObservable{observable_id: "link.snr_db"},
                 %OperationalObservable{observable_id: "link.eb_n0_db"},
                 %OperationalObservable{observable_id: "link.symbol_rate_sps"},
                 %OperationalObservable{observable_id: "link.doppler_hz"}
               ]
             },
             %{
               id: "transport_bitrate_history",
               label: "transport bitrate metric history",
               product: :transport_bitrate_history,
               product_family: :transport_bitrate,
               source_product_value: "transport_bitrate_history",
               product_family_value: "transport_bitrate",
               observables: [
                 %OperationalObservable{observable_id: "comms.transport.downlink_bitrate"},
                 %OperationalObservable{observable_id: "comms.transport.uplink_bitrate"}
               ]
             },
             %{
               id: "ingress_processing_latency_history",
               label: "runtime ingress metric history",
               product: :ingress_processing_latency_history,
               product_family: :runtime_ingress,
               source_product_value: "ingress_processing_latency_history",
               product_family_value: "runtime_ingress",
               observables: [
                 %OperationalObservable{observable_id: "ingress.processing_latency_ms"}
               ]
             }
           ] = WidgetFormPresentation.operational_observable_picker_groups(observables, form)

    assert WidgetFormPresentation.operational_observable_source_product_value(
             Enum.find(observables, &(&1.observable_id == "link.snr_db"))
           ) == "link_rf_metric_history"

    assert WidgetFormPresentation.operational_observable_product_family_value(
             Enum.find(observables, &(&1.observable_id == "link.snr_db"))
           ) == "link_rf"
  end

  test "selection predicates drive picker button state" do
    multi_form = to_form(%{"type" => "status_matrix"}, as: :widget)
    single_form = to_form(%{"type" => "value_tile"}, as: :widget)
    point = %{point_id: "HK.temp"}
    selected_points = [%{point_id: "HK.temp"}]
    observable = %OperationalObservable{observable_id: "contacts.phase"}
    selected_observables = [%OperationalObservable{observable_id: "contacts.phase"}]

    assert WidgetFormPresentation.selected_point?(multi_form, point, selected_points, nil)
    refute WidgetFormPresentation.selected_point?(single_form, point, [], nil)
    assert WidgetFormPresentation.selected_point?(single_form, point, [], point)

    assert WidgetFormPresentation.point_button_class(multi_form, point, selected_points, nil)
           |> Enum.member?("bg-primary/10 text-primary")

    assert WidgetFormPresentation.selected_operational_observable?(
             observable,
             selected_observables
           )

    assert WidgetFormPresentation.operational_observable_button_class(
             observable,
             selected_observables
           )
           |> Enum.member?("bg-primary/10 text-primary")
  end

  test "exposes operational observable scope labels for picker rows" do
    assert {:ok, observable} = OperationalObservable.fetch("ground.station.connection_state")

    assert WidgetFormPresentation.operational_observable_scope_values(observable) ==
             "ground_station mission source_endpoint transport link"

    assert WidgetFormPresentation.operational_observable_scope_badges(observable) == [
             "ground station",
             "mission",
             "source endpoint",
             "transport",
             "link"
           ]

    assert WidgetFormPresentation.operational_observable_scope_title(observable) ==
             "Scopes: ground station, mission, source endpoint, transport, link"
  end

  test "checks operational observable compatibility with the active dashboard scope" do
    assert {:ok, contact_phase} = OperationalObservable.fetch("contacts.phase")

    assert {:ok, ground_connection} =
             OperationalObservable.fetch("ground.station.connection_state")

    spacecraft_scope = %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}}
    mission_scope = %{primary: %{kind: "mission", mode: "one", ids: ["mission-1"]}}

    assert WidgetFormPresentation.operational_observable_scope_supported?(
             contact_phase,
             spacecraft_scope
           )

    refute WidgetFormPresentation.operational_observable_scope_supported?(
             ground_connection,
             spacecraft_scope
           )

    assert WidgetFormPresentation.operational_observable_selectable?(
             ground_connection,
             [ground_connection],
             spacecraft_scope
           )

    assert WidgetFormPresentation.operational_observable_selectable?(
             ground_connection,
             [],
             mission_scope
           )

    assert WidgetFormPresentation.unsupported_selected_operational_observable_ids(
             [contact_phase, ground_connection],
             spacecraft_scope
           ) == ["ground.station.connection_state"]

    assert WidgetFormPresentation.selected_operational_observable_scope_warning(
             [ground_connection],
             spacecraft_scope
           ) == "Current context does not support ground.station.connection_state."
  end
end
