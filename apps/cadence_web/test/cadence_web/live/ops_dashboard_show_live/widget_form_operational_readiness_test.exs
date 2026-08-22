defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormOperationalReadinessTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetFormComponents

  test "disables unselected operational observables unsupported by the dashboard scope" do
    contact_phase = operational_observable("contacts.phase", nil, "Contact phase")

    ground_connection =
      operational_observable("ground.station.connection_state", nil, "Ground station state")

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
        operational_observables: [contact_phase, ground_connection],
        filtered_operational_observables: [contact_phase, ground_connection],
        selected_operational_observables: [],
        dashboard_scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query(~s([data-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("disabled")

    assert ["true"] =
             document
             |> LazyHTML.query(~s([data-operational-observable="contacts.phase"]))
             |> LazyHTML.attribute("data-operational-observable-scope-supported")

    assert [""] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("disabled")

    assert ["false"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("data-operational-observable-scope-supported")
  end

  test "keeps selected unsupported operational observables removable" do
    ground_connection =
      operational_observable("ground.station.connection_state", nil, "Ground station state")

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
        operational_observables: [ground_connection],
        filtered_operational_observables: [ground_connection],
        selected_operational_observables: [ground_connection],
        dashboard_scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("disabled")

    assert ["false"] =
             document
             |> LazyHTML.query(
               ~s([data-selected-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("data-selected-operational-observable-scope-supported")

    assert ["ground.station.connection_state"] =
             document
             |> LazyHTML.query("[data-operational-observable-scope-warning]")
             |> LazyHTML.attribute("data-operational-observable-scope-warning-ids")

    assert "Current context does not support ground.station.connection_state." =
             document
             |> LazyHTML.query("[data-operational-observable-scope-warning]")
             |> selected_text()
  end

  test "marks readiness-focused operational observables in the editor" do
    ground_connection =
      operational_observable("ground.station.connection_state", nil, "Ground station state")

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
        operational_observables: [ground_connection],
        filtered_operational_observables: [ground_connection],
        selected_operational_observables: [ground_connection],
        dashboard_scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}},
        dashboard_editor_focus: %{
          unsupported_observables: ["ground.station.connection_state"]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["ground.station.connection_state"] =
             document
             |> LazyHTML.query("[data-operational-observable-picker]")
             |> LazyHTML.attribute("data-operational-observable-readiness-focus-ids")

    assert ["true"] =
             document
             |> LazyHTML.query(
               ~s([data-selected-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("data-selected-operational-observable-readiness-focus")

    assert ["true"] =
             document
             |> LazyHTML.query(
               ~s([data-operational-observable="ground.station.connection_state"])
             )
             |> LazyHTML.attribute("data-operational-observable-readiness-focus")
  end

  test "renders operational source capability guidance in the picker" do
    snr = operational_observable("link.snr_db", "dB", "RF SNR")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "time_series",
              "title" => "RF history",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [snr],
        filtered_operational_observables: [snr],
        selected_operational_observables: [snr],
        dashboard_editor_focus: %{
          source_empty_reason: "unsupported_source_capability",
          requested_observables: ["link.snr_db"],
          requested_sampling: "raw_series",
          requested_products: ["link_rf"],
          requested_source_products: ["link_rf_metric_history"],
          supported_products: ["operational_metric_history"]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["unsupported_source_capability"] =
             document
             |> LazyHTML.query("[data-operational-observable-picker]")
             |> LazyHTML.attribute("data-operational-observable-readiness-source-empty-reason")

    assert ["raw_series"] =
             document
             |> LazyHTML.query("[data-operational-observable-picker]")
             |> LazyHTML.attribute("data-operational-observable-readiness-requested-sampling")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query("[data-operational-observable-picker]")
             |> LazyHTML.attribute("data-operational-observable-readiness-requested-products")

    assert ["link_rf_metric_history"] =
             document
             |> LazyHTML.query("[data-operational-observable-capability-warning]")
             |> LazyHTML.attribute("data-operational-observable-capability-warning-products")

    assert "Selected source cannot satisfy raw_series for link_rf_metric_history." <>
             _rest =
             document
             |> LazyHTML.query("[data-operational-observable-capability-warning]")
             |> selected_text()

    assert ["true"] =
             document
             |> LazyHTML.query(~s([data-operational-observable="link.snr_db"]))
             |> LazyHTML.attribute("data-operational-observable-readiness-focus")
  end

  test "renders operational latest source capability guidance without history wording" do
    snr = operational_observable("link.snr_db", "dB", "RF SNR")

    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "value_tile",
              "title" => "RF latest",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [snr],
        filtered_operational_observables: [snr],
        selected_operational_observables: [snr],
        dashboard_editor_focus: %{
          source_empty_reason: "unsupported_source_capability",
          requested_observables: ["link.snr_db"],
          requested_sampling: "latest",
          requested_products: ["link_rf"],
          requested_source_products: ["link_rf_metric"],
          supported_products: ["operational_latest"]
        }
      )

    warning_text =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-operational-observable-capability-warning]")
      |> selected_text()

    assert warning_text =~
             "Selected source cannot satisfy latest for link_rf_metric."

    assert warning_text =~ "Supported source products: operational_latest."
    refute warning_text =~ "history products"
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

  defp operational_observable(observable_id, unit, name) do
    %{observable_id: observable_id, unit: unit, name: name, description: name}
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
