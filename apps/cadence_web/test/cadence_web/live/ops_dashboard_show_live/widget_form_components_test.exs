defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetFormComponents

  test "renders telemetry point widget form with selected point contract" do
    counter_point = telemetry_point("HK.counter", "ct", "Counter")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "value_tile",
              "title" => "Counter",
              "mode" => "context",
              "binding_source" => "telemetry"
            },
            as: :widget
          ),
        filtered_points: [counter_point, telemetry_point("HK.voltage", "V", "Voltage")],
        points_empty?: false,
        selected_point: counter_point
      )

    document = LazyHTML.from_fragment(html)

    assert ["validate_widget"] =
             document
             |> LazyHTML.query("#widget-form")
             |> LazyHTML.attribute("phx-change")

    assert ["save_widget"] =
             document
             |> LazyHTML.query("#widget-form")
             |> LazyHTML.attribute("phx-submit")

    assert ["telemetry"] =
             document
             |> LazyHTML.query(
               ~s(#widget-form select[name="widget[binding_source]"] option[value="telemetry"])
             )
             |> LazyHTML.attribute("value")

    assert ["operational_observables"] =
             document
             |> LazyHTML.query(
               ~s(#widget-form select[name="widget[binding_source]"] option[value="operational_observables"])
             )
             |> LazyHTML.attribute("value")

    assert ["true"] =
             document
             |> LazyHTML.query(~s(button[phx-value-point-id="HK.counter"]))
             |> LazyHTML.attribute("data-point-selected")

    assert "Add Widget" =
             document
             |> LazyHTML.query(~s(#widget-form button[type="submit"]))
             |> selected_text()
  end

  test "renders multi operational observable picker selections" do
    contact_phase = operational_observable("contacts.phase", nil, "Contact phase")

    connection_state =
      operational_observable("comms.transport.connection_state", nil, "Connection state")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "state_timeline",
              "title" => "Ops state",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [contact_phase, connection_state],
        filtered_operational_observables: [contact_phase, connection_state],
        selected_operational_observables: [contact_phase]
      )

    document = LazyHTML.from_fragment(html)

    assert [_picker] =
             document
             |> LazyHTML.query("[data-operational-observable-picker]")
             |> LazyHTML.attribute("data-operational-observable-picker")

    assert ["contacts.phase"] =
             document
             |> LazyHTML.query(~s([data-selected-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("data-selected-operational-observable")

    assert ["contact mission spacecraft ground_station source_endpoint"] =
             document
             |> LazyHTML.query(~s([data-selected-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("data-selected-operational-observable-scopes")

    assert ["true"] =
             document
             |> LazyHTML.query(~s([data-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("data-operational-observable-selected")

    assert ["contact mission spacecraft ground_station source_endpoint"] =
             document
             |> LazyHTML.query(~s([data-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("data-operational-observable-scopes")

    assert ["false"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="comms.transport.connection_state"])
             )
             |> LazyHTML.attribute("data-operational-observable-selected")

    assert html =~ "source endpoint"
  end

  test "renders operational time-series picker grouped by source metric-history contract" do
    downlink =
      operational_observable("comms.transport.downlink_bitrate", "bit/s", "Downlink bit rate")

    snr = operational_observable("link.snr_db", "dB", "RF SNR")

    ingress =
      operational_observable("ingress.processing_latency_ms", "ms", "Ingress latency")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "time_series",
              "title" => "Operational history",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [downlink, snr, ingress],
        filtered_operational_observables: [downlink, snr, ingress],
        selected_operational_observables: [snr]
      )

    document = LazyHTML.from_fragment(html)

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable-product-group="link_rf_metric_history"])
             )
             |> LazyHTML.attribute("data-operational-observable-source-product")

    assert ["link_rf"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable-product-group="link_rf_metric_history"])
             )
             |> LazyHTML.attribute("data-operational-observable-product-family")

    assert "link RF metric history" =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable-product-group-label="link_rf_metric_history"])
             )
             |> selected_text()

    assert ["transport_bitrate"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )
             |> LazyHTML.attribute("data-operational-observable-product-family")

    assert ["transport_bitrate_history"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )
             |> LazyHTML.attribute("data-operational-observable-source-product")

    assert ["ingress_processing_latency_history"] =
             document
             |> LazyHTML.query(~s([data-operational-observable="ingress.processing_latency_ms"]))
             |> LazyHTML.attribute("data-operational-observable-source-product")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query(~s([data-selected-operational-observable="link.snr_db"]))
             |> LazyHTML.attribute("data-selected-operational-observable-source-product")
  end

  test "renders pinned dashboard scope fields for widget overrides" do
    ground_connection =
      operational_observable("ground.station.connection_state", nil, "Ground station state")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "state_timeline",
              "title" => "Ground state",
              "mode" => "scope",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [ground_connection],
        filtered_operational_observables: [ground_connection],
        selected_operational_observables: [ground_connection],
        dashboard_scope_context: %{
          primary: %{kind: "ground_station", mode: "one", ids: ["ground-dss-14"]}
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["ground_station"] =
             document
             |> LazyHTML.query(~s(input[name="widget[scope_kind]"]))
             |> LazyHTML.attribute("value")

    assert ["ground-dss-14"] =
             document
             |> LazyHTML.query(~s(input[name="widget[scope_id]"]))
             |> LazyHTML.attribute("value")

    assert ["ready"] =
             document
             |> LazyHTML.query("[data-widget-scope-override]")
             |> LazyHTML.attribute("data-widget-scope-override-state")

    assert "Pins this widget to ground station ground-dss-14." =
             document
             |> LazyHTML.query("[data-widget-scope-override]")
             |> selected_text()

    assert [] =
             document
             |> LazyHTML.query(~s(#widget_mode option[value="fixed"]))
             |> LazyHTML.attribute("value")
  end

  test "renders edit placement submit label and inline error" do
    html =
      render_widget_form(
        panel: {:edit_placement, "placement-1"},
        form:
          to_form(
            %{
              "type" => "event_timeline",
              "title" => "Events"
            },
            as: :widget
          ),
        error: "Title is required"
      )

    document = LazyHTML.from_fragment(html)

    assert "Save Widget" =
             document
             |> LazyHTML.query(~s(#widget-form button[type="submit"]))
             |> selected_text()

    assert html =~ "Title is required"
    assert html =~ "No point binding required."
  end

  defp render_widget_form(attrs) do
    render_component(&WidgetFormComponents.widget_form/1, Keyword.merge(base_attrs(), attrs))
  end

  defp base_attrs do
    [
      panel: :add_widget,
      form: to_form(%{}, as: :widget),
      spacecraft: [],
      operational_observables: [],
      filtered_points: [],
      filtered_operational_observables: [],
      points_empty?: true,
      selected_point: nil,
      selected_points: [],
      selected_operational_observables: [],
      dashboard_scope_context: nil,
      error: nil,
      mission_id: "mission-1"
    ]
  end

  defp telemetry_point(point_id, unit, description) do
    %{point_id: point_id, unit: unit, description: description}
  end

  defp operational_observable(observable_id, unit, name) do
    %{observable_id: observable_id, unit: unit, name: name, description: name}
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
