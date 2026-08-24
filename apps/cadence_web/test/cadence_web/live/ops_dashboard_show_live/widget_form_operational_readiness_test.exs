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

    options = html |> operational_picker() |> observable_options_by_id()
    contact_attrs = options["contacts.phase"]["attrs"]
    ground_attrs = options["ground.station.connection_state"]["attrs"]

    refute Map.has_key?(contact_attrs, "disabled")
    assert contact_attrs["data-operational-observable-scope-supported"] == "true"
    assert ground_attrs["disabled"] == ""
    assert ground_attrs["data-operational-observable-scope-supported"] == "false"
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

    picker = operational_picker(html)
    options = observable_options_by_id(picker)
    selected = selected_observables_by_id(picker)

    refute Map.has_key?(options["ground.station.connection_state"]["attrs"], "disabled")

    assert selected["ground.station.connection_state"]["attrs"][
             "data-selected-operational-observable-scope-supported"
           ] == "false"

    assert picker["scope_warning"]["attrs"][
             "data-operational-observable-scope-warning-ids"
           ] == "ground.station.connection_state"

    assert picker["scope_warning"]["text"] ==
             "Current context does not support ground.station.connection_state."
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

    picker = operational_picker(html)
    selected = selected_observables_by_id(picker)
    options = observable_options_by_id(picker)

    assert picker["attrs"]["data-operational-observable-readiness-focus-ids"] ==
             "ground.station.connection_state"

    assert selected["ground.station.connection_state"]["attrs"][
             "data-selected-operational-observable-readiness-focus"
           ] == "true"

    assert options["ground.station.connection_state"]["attrs"][
             "data-operational-observable-readiness-focus"
           ] == "true"
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

    picker = operational_picker(html)
    warning = picker["capability_warning"]
    options = observable_options_by_id(picker)

    assert picker["attrs"]["data-operational-observable-readiness-source-empty-reason"] ==
             "unsupported_source_capability"

    assert picker["attrs"]["data-operational-observable-readiness-requested-sampling"] ==
             "raw_series"

    assert picker["attrs"]["data-operational-observable-readiness-requested-products"] ==
             "link_rf_metric_history"

    assert warning["attrs"]["data-operational-observable-capability-warning-products"] ==
             "link_rf_metric_history"

    assert "Selected source cannot satisfy raw_series for link_rf_metric_history." <>
             _rest = warning["text"]

    assert options["link.snr_db"]["attrs"][
             "data-operational-observable-readiness-focus"
           ] == "true"
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

    warning_text = html |> operational_picker() |> get_in(["capability_warning", "text"])

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

  defp operational_picker(html) do
    html
    |> widget_form_presentation()
    |> get_in(["point_widget", "operational_observable_picker"])
  end

  defp widget_form_presentation(html) do
    assert ["widget-form-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#widget-form-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "widget-form-component")

    assert vue.component == "WidgetForm"
    assert vue.id == "widget-form-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp observable_options_by_id(picker) do
    picker["list"]["groups"]
    |> Enum.flat_map(& &1["options"])
    |> Map.new(&{&1["observable_id"], &1})
  end

  defp selected_observables_by_id(picker) do
    Map.new(picker["selected"]["buttons"], &{&1["text"], &1})
  end
end
