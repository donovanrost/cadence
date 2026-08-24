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

    presentation = widget_form_presentation(html)
    root = presentation["root"]
    fields = fields_by_key(presentation["fields"])
    point_widget = presentation["point_widget"]
    binding_fields = fields_by_key(point_widget["binding_fields"])
    trailing_fields = fields_by_key(point_widget["trailing_fields"])

    assert root["attrs"]["phx-change"] == "validate_widget"
    assert root["attrs"]["phx-submit"] == "save_widget"
    assert root["id"] == "widget-form"
    assert root["class"] == "space-y-4"
    assert root["param"] == "widget"

    assert root["params"] == %{
             "binding_source" => "telemetry",
             "mode" => "context",
             "point_q" => "",
             "precision" => "",
             "scope_id" => "",
             "scope_kind" => "",
             "show_unit" => "false",
             "title" => "Counter",
             "type" => "value_tile"
           }

    assert fields["type"] ==
             select_field(
               "widget_type",
               "widget[type]",
               "Widget Type",
               [
                 {"Value tile", "value_tile"},
                 {"Time series chart", "time_series"},
                 {"Status matrix", "status_matrix"},
                 {"Data table", "data_table"},
                 {"State timeline", "state_timeline"},
                 {"Event timeline", "event_timeline"},
                 {"Constellation health", "constellation_health"}
               ],
               "value_tile"
             )

    assert fields["title"] ==
             text_field("widget_title", "widget[title]", "Title", "Counter", true)

    assert option_contract(binding_fields["binding_source"]) == [
             {"Telemetry points", "telemetry"},
             {"Operational observables", "operational_observables"}
           ]

    assert selected_option_value(binding_fields["binding_source"]) == "telemetry"

    assert binding_fields["binding_source"]["control"]["attrs"]["name"] ==
             "widget[binding_source]"

    point_options = point_options_by_id(point_widget["point_picker"])

    assert Enum.map(point_widget["point_picker"]["list"]["options"], & &1["point_id"]) == [
             "HK.counter",
             "HK.voltage"
           ]

    assert point_options["HK.counter"]["attrs"]["data-point-selected"] == "true"
    assert point_options["HK.counter"]["attrs"]["aria-pressed"] == "true"
    assert point_options["HK.counter"]["attrs"]["phx-click"] == "pick_point"
    assert point_options["HK.counter"]["attrs"]["phx-value-point-id"] == "HK.counter"
    assert point_options["HK.counter"]["type"] == "button"

    assert trailing_fields["show_unit"]["hidden_control"]["attrs"] == %{
             "type" => "hidden",
             "name" => "widget[show_unit]",
             "value" => "false"
           }

    assert trailing_fields["show_unit"]["control"]["attrs"]["value"] == "true"
    refute Map.has_key?(trailing_fields["show_unit"]["control"]["attrs"], "checked")
    assert presentation["actions"]["submit"]["text"] == "Add Widget"
    assert presentation["actions"]["submit"]["type"] == "submit"
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

    picker =
      html
      |> widget_form_presentation()
      |> get_in(["point_widget", "operational_observable_picker"])

    selected = selected_observables_by_id(picker)
    options = observable_options_by_id(picker)

    assert picker["attrs"]["data-operational-observable-picker"] == ""

    assert selected["contacts.phase"]["attrs"]["data-selected-operational-observable"] ==
             "contacts.phase"

    assert selected["contacts.phase"]["attrs"]["phx-click"] == "pick_point"
    assert selected["contacts.phase"]["attrs"]["phx-value-point-id"] == "contacts.phase"
    assert selected["contacts.phase"]["attrs"]["aria-label"] == "Remove contacts.phase"

    assert selected["contacts.phase"]["attrs"]["data-selected-operational-observable-scopes"] ==
             "contact mission spacecraft ground_station source_endpoint"

    assert options["contacts.phase"]["attrs"]["data-operational-observable-selected"] == "true"

    assert options["contacts.phase"]["attrs"]["data-operational-observable-scopes"] ==
             "contact mission spacecraft ground_station source_endpoint"

    assert options["comms.transport.connection_state"]["attrs"][
             "data-operational-observable-selected"
           ] == "false"

    assert "source endpoint" in options["contacts.phase"]["scope_badges"]
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

    picker =
      html
      |> widget_form_presentation()
      |> get_in(["point_widget", "operational_observable_picker"])

    groups = Map.new(picker["list"]["groups"], &{&1["key"], &1})
    options = observable_options_by_id(picker)
    selected = selected_observables_by_id(picker)
    link_group = groups["link_rf_metric_history"]

    assert link_group["attrs"]["data-operational-observable-source-product"] ==
             "link_rf_metric_history"

    assert link_group["attrs"]["data-operational-observable-product-family"] == "link_rf"
    assert link_group["label"]["text"] == "link RF metric history"

    assert options["comms.transport.downlink_bitrate"]["attrs"][
             "data-operational-observable-product-family"
           ] == "transport_bitrate"

    assert options["comms.transport.downlink_bitrate"]["attrs"][
             "data-operational-observable-source-product"
           ] == "transport_bitrate_history"

    assert options["ingress.processing_latency_ms"]["attrs"][
             "data-operational-observable-source-product"
           ] == "ingress_processing_latency_history"

    assert selected["link.snr_db"]["attrs"][
             "data-selected-operational-observable-source-product"
           ] == "link_rf_metric_history"
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

    point_widget = html |> widget_form_presentation() |> Map.fetch!("point_widget")
    [scope_kind, scope_id] = point_widget["hidden_fields"]
    mode = point_widget["binding_fields"] |> fields_by_key() |> Map.fetch!("mode")

    assert scope_kind["attrs"]["value"] == "ground_station"
    assert scope_kind["attrs"]["name"] == "widget[scope_kind]"
    assert scope_id["attrs"]["value"] == "ground-dss-14"
    assert scope_id["attrs"]["name"] == "widget[scope_id]"
    assert point_widget["scope_override"]["attrs"]["data-widget-scope-override-state"] == "ready"

    assert point_widget["scope_override"]["text"] ==
             "Pins this widget to ground station ground-dss-14."

    refute "fixed" in option_values(mode)
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

    presentation = widget_form_presentation(html)

    assert presentation["actions"]["submit"]["text"] == "Save Widget"
    assert presentation["actions"]["submit"]["type"] == "submit"
    assert presentation["error"]["text"] == "Title is required"
    assert presentation["error"]["class"] == "text-sm text-error"
    assert presentation["non_point_help"]["text"] =~ "No point binding required."
    assert presentation["point_widget"] == nil
  end

  test "renders section, repeat, chart presentation, and binding preview controls" do
    html =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "time_series",
              "title" => "Fleet voltage",
              "mode" => "repeat",
              "binding_source" => "telemetry",
              "section_id" => "power",
              "repeat_over" => "spacecraft",
              "repeat_layout" => "wrap_grid",
              "repeat_max_instances" => "12",
              "precision" => "2",
              "window_seconds" => "300",
              "legend_mode" => "auto",
              "line_width" => "normal",
              "fill_opacity" => "0",
              "axis_mode" => "unit",
              "show_min_max_band" => "true",
              "show_points" => "false",
              "span_gaps" => "false",
              "shared_tooltip" => "true"
            },
            as: :widget
          ),
        dashboard_document: %{
          sections: [%{section_id: "power", title: "Power"}]
        },
        binding_preview: %{
          status: :ready,
          title: "Binding is producing data",
          message: "1 source request produced 1 primary frame with renderable values.",
          planned_request_count: 1,
          frame_count: 1,
          warning_count: 0
        }
      )

    presentation = widget_form_presentation(html)
    fields = fields_by_key(presentation["fields"])
    point_widget = presentation["point_widget"]
    binding_fields = fields_by_key(point_widget["binding_fields"])
    trailing_fields = fields_by_key(point_widget["trailing_fields"])
    chart_options = point_widget["chart_options"]
    chart_selects = fields_by_key(chart_options["select_fields"])
    chart_checkboxes = fields_by_key(chart_options["checkbox_fields"])
    repeat_fields = fields_by_key(point_widget["repeat"]["fields"])

    assert selected_option_value(fields["section_id"]) == "power"

    assert option_contract(fields["section_id"]) == [
             {"Unsectioned canvas", ""},
             {"Power", "power"}
           ]

    assert selected_option_value(binding_fields["mode"]) == "repeat"

    assert option_contract(binding_fields["mode"]) == [
             {"Follow dashboard context", "context"},
             {"Pin current dashboard context", "scope"},
             {"Pin to one spacecraft", "fixed"},
             {"Repeat for selected resources", "repeat"}
           ]

    assert point_widget["repeat"]["id"] == "widget-repeat-options"

    assert option_contract(repeat_fields["repeat_over"]) == [
             {"Spacecraft", "spacecraft"},
             {"Contacts", "contact"},
             {"Ground stations", "ground_station"},
             {"Transports", "transport"},
             {"Links", "link"}
           ]

    assert option_contract(repeat_fields["repeat_layout"]) == [
             {"Wrap grid", "wrap_grid"},
             {"Single row", "row"},
             {"Single column", "column"}
           ]

    assert option_contract(repeat_fields["repeat_max_instances"]) == [
             {"Up to 4", "4"},
             {"Up to 8", "8"},
             {"Up to 12", "12"},
             {"Up to 16", "16"},
             {"Up to 24", "24"}
           ]

    assert chart_options["id"] == "time-series-presentation-options"
    assert presentation["binding_preview"]["attrs"]["data-binding-preview-status"] == "ready"

    assert presentation["actions"]["preview"]["attrs"]["phx-click"] ==
             "preview_widget_binding"

    assert option_contract(trailing_fields["window_seconds"]) == [
             {"5 minutes", "300"},
             {"15 minutes", "900"},
             {"1 hour", "3600"},
             {"1 minute", "60"}
           ]

    assert option_contract(trailing_fields["precision"]) ==
             Enum.map(0..6, &{"#{&1} decimals", to_string(&1)})

    assert option_contract(chart_selects["legend_mode"]) == [
             {"Auto", "auto"},
             {"Always", "always"},
             {"Hidden", "hidden"}
           ]

    assert option_contract(chart_selects["line_width"]) == [
             {"Thin", "thin"},
             {"Normal", "normal"},
             {"Bold", "bold"}
           ]

    assert option_contract(chart_selects["fill_opacity"]) == [
             {"None", "0"},
             {"Subtle", "8"},
             {"Medium", "16"},
             {"Strong", "30"}
           ]

    assert option_contract(chart_selects["axis_mode"]) == [
             {"Group by engineering unit", "unit"},
             {"Shared value axis", "shared"}
           ]

    assert selected_option_value(repeat_fields["repeat_over"]) == "spacecraft"
    assert selected_option_value(repeat_fields["repeat_layout"]) == "wrap_grid"
    assert selected_option_value(repeat_fields["repeat_max_instances"]) == "12"
    assert selected_option_value(trailing_fields["precision"]) == "2"
    assert selected_option_value(trailing_fields["window_seconds"]) == "300"
    assert selected_option_value(chart_selects["legend_mode"]) == "auto"
    assert selected_option_value(chart_selects["line_width"]) == "normal"
    assert selected_option_value(chart_selects["fill_opacity"]) == "0"
    assert selected_option_value(chart_selects["axis_mode"]) == "unit"

    assert Map.keys(chart_checkboxes) |> Enum.sort() == [
             "shared_tooltip",
             "show_min_max_band",
             "show_points",
             "span_gaps"
           ]

    Enum.each(chart_checkboxes, fn {field, checkbox} ->
      assert checkbox["hidden_control"]["attrs"] == %{
               "type" => "hidden",
               "name" => "widget[#{field}]",
               "value" => "false"
             }

      assert checkbox["control"]["attrs"]["value"] == "true"
    end)

    assert Map.has_key?(chart_checkboxes["show_min_max_band"]["control"]["attrs"], "checked")
    refute Map.has_key?(chart_checkboxes["show_points"]["control"]["attrs"], "checked")
    refute Map.has_key?(chart_checkboxes["span_gaps"]["control"]["attrs"], "checked")
    assert Map.has_key?(chart_checkboxes["shared_tooltip"]["control"]["attrs"], "checked")

    all_fields =
      presentation["fields"] ++
        point_widget["binding_fields"] ++
        point_widget["repeat"]["fields"] ++
        point_widget["trailing_fields"] ++
        chart_options["select_fields"] ++ chart_options["checkbox_fields"]

    Enum.each(all_fields, fn field ->
      assert field["control"]["attrs"]["id"] == "widget_#{field["key"]}"
      assert field["control"]["attrs"]["name"] == "widget[#{field["key"]}]"
    end)

    assert presentation["actions"]["preview"] == %{
             "id" => "test-widget-binding",
             "type" => "button",
             "class" => "btn btn-secondary",
             "attrs" => %{"phx-click" => "preview_widget_binding"},
             "icon" => %{
               "name" => "hero-beaker",
               "class" => "-ml-0.5 mr-1 h-4 w-4"
             },
             "text" => "Test binding"
           }

    assert presentation["actions"]["submit"]["id"] == "save-dashboard-widget"
    assert presentation["actions"]["submit"]["attrs"] == %{}
    refute Map.has_key?(presentation["actions"]["submit"]["attrs"], "disabled")
  end

  test "renders every empty, filtered-empty, and missing-scope picker state" do
    empty_points =
      render_widget_form(
        form: to_form(%{"type" => "value_tile", "mode" => "context"}, as: :widget)
      )
      |> widget_form_presentation()
      |> get_in(["point_widget", "point_picker"])

    assert empty_points["empty"]["before_link"] ==
             "No telemetry points available. Activate packet definitions in"

    assert empty_points["empty"]["link"] == %{
             "href" => "/missions/mission-1/catalog",
             "class" => "text-primary hover:underline",
             "text" => "Catalog",
             "attrs" => %{
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push"
             }
           }

    assert empty_points["search"] == nil
    assert empty_points["list"] == nil

    filtered_empty =
      render_widget_form(
        form: to_form(%{"type" => "value_tile", "mode" => "context"}, as: :widget),
        points_empty?: false
      )
      |> widget_form_presentation()
      |> get_in(["point_widget", "point_picker"])

    assert filtered_empty["empty"] == nil
    assert filtered_empty["search"]["control"]["attrs"]["phx-debounce"] == "150"
    assert filtered_empty["list"]["empty"]
    assert filtered_empty["list"]["empty_text"] == "No points match the filter."

    counter = telemetry_point("HK.counter", "ct", "Counter")
    voltage = telemetry_point("HK.voltage", "V", "Voltage")

    multi_selected =
      render_widget_form(
        form: to_form(%{"type" => "status_matrix", "mode" => "context"}, as: :widget),
        filtered_points: [counter, voltage],
        points_empty?: false,
        selected_points: [counter, voltage]
      )
      |> widget_form_presentation()
      |> get_in(["point_widget", "point_picker", "selected_points", "buttons"])
      |> Map.new(&{&1["key"], &1})

    assert multi_selected["HK.counter"]["attrs"] == %{
             "aria-label" => "Remove HK.counter",
             "data-selected-point" => "HK.counter",
             "phx-click" => "pick_point",
             "phx-value-point-id" => "HK.counter"
           }

    assert multi_selected["HK.counter"]["type"] == "button"

    assert multi_selected["HK.counter"]["icon"] == %{
             "name" => "hero-x-mark",
             "class" => "h-3 w-3"
           }

    empty_observables =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "state_timeline",
              "binding_source" => "operational_observables"
            },
            as: :widget
          )
      )
      |> widget_form_presentation()
      |> get_in(["point_widget", "operational_observable_picker"])

    assert empty_observables["empty"]["text"] ==
             "No backed operational observables are available for dashboard binding."

    assert empty_observables["search"] == nil
    assert empty_observables["list"] == nil
    assert empty_observables["capability_warning"] == nil
    assert empty_observables["selected"] == nil
    assert empty_observables["scope_warning"] == nil

    observable = operational_observable("contacts.phase", nil, "Contact phase")

    filtered_empty_observables =
      render_widget_form(
        form:
          to_form(
            %{
              "type" => "state_timeline",
              "binding_source" => "operational_observables"
            },
            as: :widget
          ),
        operational_observables: [observable],
        filtered_operational_observables: []
      )
      |> widget_form_presentation()
      |> get_in(["point_widget", "operational_observable_picker"])

    assert filtered_empty_observables["empty"] == nil
    assert filtered_empty_observables["search"]["control"]["attrs"]["phx-debounce"] == "150"
    assert filtered_empty_observables["list"]["empty"]

    assert filtered_empty_observables["list"]["empty_text"] ==
             "No operational observables match the filter."

    missing_scope =
      render_widget_form(form: to_form(%{"type" => "value_tile", "mode" => "scope"}, as: :widget))
      |> widget_form_presentation()
      |> get_in(["point_widget", "scope_override"])

    assert missing_scope["attrs"]["data-widget-scope-override-state"] == "missing_context"
    assert missing_scope["attrs"]["data-widget-scope-override-kind"] == ""
    assert missing_scope["attrs"]["data-widget-scope-override-id"] == ""
    assert missing_scope["text"] == "Choose a dashboard context before pinning this widget."

    constellation =
      render_widget_form(form: to_form(%{"type" => "constellation_health"}, as: :widget))
      |> widget_form_presentation()

    assert constellation["point_widget"] == nil

    assert constellation["non_point_help"]["text"] ==
             "Constellation health rolls every spacecraft up to its worst current limit state. No point binding required."
  end

  test "renders fixed spacecraft, validation error, and checked checkbox contracts" do
    form =
      to_form(
        %{
          "type" => "value_tile",
          "title" => "",
          "mode" => "fixed",
          "spacecraft_id" => "sc-2",
          "show_unit" => "true"
        },
        as: :widget,
        errors: [title: {"can't be blank", []}]
      )

    presentation =
      render_widget_form(
        form: form,
        spacecraft: [
          %{spacecraft_id: "sc-1", display_name: "SC One"},
          %{spacecraft_id: "sc-2", display_name: "SC Two"}
        ]
      )
      |> widget_form_presentation()

    fields = fields_by_key(presentation["fields"])
    fixed_fields = fields_by_key(presentation["point_widget"]["fixed_fields"])
    trailing_fields = fields_by_key(presentation["point_widget"]["trailing_fields"])

    assert fields["title"]["control"]["class"] == "w-full input input-error"

    assert fields["title"]["errors"] == [
             %{"class" => "mt-1.5 text-sm text-error", "text" => "can't be blank"}
           ]

    assert option_values(fixed_fields["spacecraft_id"]) == ["", "sc-1", "sc-2"]

    assert option_contract(fixed_fields["spacecraft_id"]) == [
             {"Select a spacecraft", ""},
             {"SC One", "sc-1"},
             {"SC Two", "sc-2"}
           ]

    assert selected_option_value(fixed_fields["spacecraft_id"]) == "sc-2"
    assert trailing_fields["show_unit"]["control"]["attrs"]["checked"] == ""

    assert trailing_fields["show_unit"]["hidden_control"]["attrs"] == %{
             "type" => "hidden",
             "name" => "widget[show_unit]",
             "value" => "false"
           }
  end

  test "renders every binding preview status from server presentation" do
    no_data =
      render_widget_form(binding_preview: binding_preview(:no_data))
      |> widget_form_presentation()
      |> Map.fetch!("binding_preview")

    assert no_data["attrs"]["data-binding-preview-status"] == "no_data"

    assert no_data["class"] ==
             "rounded border px-3 py-2 border-warning/40 bg-warning/10 text-warning"

    assert no_data["icon"]["name"] == "hero-information-circle"
    assert no_data["summary"]["text"] == "1 requests / 0 frames / 1 warnings"

    error =
      render_widget_form(binding_preview: binding_preview(:error))
      |> widget_form_presentation()
      |> Map.fetch!("binding_preview")

    assert error["attrs"]["data-binding-preview-status"] == "error"

    assert error["class"] ==
             "rounded border px-3 py-2 border-error/40 bg-error/10 text-error"

    assert error["icon"]["name"] == "hero-exclamation-triangle"
  end

  test "keeps WidgetForm a deterministic wrapper-free renderer" do
    source =
      Path.expand("../../../../assets/vue/WidgetForm.vue", __DIR__)
      |> File.read!()

    assert source =~ ~s(<form\n    :id="presentation.root.id")
    assert source =~ ~s|defineProps<{presentation: Presentation}>()|
    refute source =~ "v-model"
    refute source =~ "reactive("
    refute source =~ "ref("
    refute source =~ "watch("
    refute source =~ "fetch("
    refute source =~ "@submit.prevent"
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

  defp binding_preview(status) do
    %{
      status: status,
      title: "Binding preview",
      message: "Server-owned preview result.",
      planned_request_count: 1,
      frame_count: 0,
      warning_count: 1
    }
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

    presentation = Map.fetch!(vue.props, "presentation")

    assert Map.keys(presentation) |> Enum.sort() == [
             "actions",
             "binding_preview",
             "error",
             "fields",
             "non_point_help",
             "point_widget",
             "root"
           ]

    assert_widget_form_param_contract(presentation)
    presentation
  end

  defp assert_widget_form_param_contract(presentation) do
    root = presentation["root"]
    fields = rendered_fields(presentation)
    hidden_fields = get_in(presentation, ["point_widget", "hidden_fields"]) || []

    expected_keys =
      Enum.map(fields, & &1["key"]) ++
        Enum.map(hidden_fields, &form_param_key(&1["attrs"]["name"], root["param"]))

    assert Enum.sort(Map.keys(root["params"])) == Enum.sort(expected_keys)

    Enum.each(hidden_fields, fn field ->
      key = form_param_key(field["attrs"]["name"], root["param"])
      assert root["params"][key] == field["attrs"]["value"]
    end)

    Enum.each(fields, fn field ->
      assert field["control"]["attrs"]["name"] == "#{root["param"]}[#{field["key"]}]"

      if field["type"] == "checkbox" do
        expected_value =
          if Map.has_key?(field["control"]["attrs"], "checked"), do: "true", else: "false"

        assert root["params"][field["key"]] == expected_value
      end
    end)
  end

  defp rendered_fields(presentation) do
    case presentation["point_widget"] do
      nil ->
        presentation["fields"]

      point_widget ->
        presentation["fields"] ++
          point_widget["binding_fields"] ++
          point_widget["fixed_fields"] ++
          optional_fields(point_widget["repeat"]) ++
          optional_picker_search(point_widget["point_picker"]) ++
          optional_picker_search(point_widget["operational_observable_picker"]) ++
          point_widget["trailing_fields"] ++ optional_chart_fields(point_widget["chart_options"])
    end
  end

  defp optional_fields(nil), do: []
  defp optional_fields(section), do: section["fields"]

  defp optional_picker_search(nil), do: []
  defp optional_picker_search(%{"search" => nil}), do: []
  defp optional_picker_search(picker), do: [picker["search"]]

  defp optional_chart_fields(nil), do: []

  defp optional_chart_fields(chart) do
    chart["select_fields"] ++ chart["checkbox_fields"]
  end

  defp form_param_key(name, param) do
    name
    |> String.trim_leading("#{param}[")
    |> String.trim_trailing("]")
  end

  defp fields_by_key(fields), do: Map.new(fields, &{&1["key"], &1})

  defp point_options_by_id(picker) do
    Map.new(picker["list"]["options"], &{&1["point_id"], &1})
  end

  defp observable_options_by_id(picker) do
    picker["list"]["groups"]
    |> Enum.flat_map(& &1["options"])
    |> Map.new(&{&1["observable_id"], &1})
  end

  defp selected_observables_by_id(picker) do
    Map.new(picker["selected"]["buttons"], &{&1["text"], &1})
  end

  defp option_values(field) do
    Enum.map(field["control"]["options"], & &1["attrs"]["value"])
  end

  defp option_contract(field) do
    Enum.map(field["control"]["options"], &{&1["text"], &1["attrs"]["value"]})
  end

  defp selected_option_value(field) do
    field["control"]["options"]
    |> Enum.find(&Map.has_key?(&1["attrs"], "selected"))
    |> get_in(["attrs", "value"])
  end

  defp select_field(id, name, label, options, selected) do
    %{
      "key" => id |> String.replace_prefix("widget_", ""),
      "type" => "select",
      "wrapper_class" => "fieldset mb-3",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "control" => %{
        "class" => "w-full select",
        "attrs" => %{"id" => id, "name" => name},
        "options" =>
          Enum.map(options, fn {text, value} ->
            attrs = %{"value" => value}
            attrs = if value == selected, do: Map.put(attrs, "selected", ""), else: attrs
            %{"key" => value, "text" => text, "attrs" => attrs}
          end)
      },
      "hidden_control" => nil,
      "description" => nil,
      "errors" => []
    }
  end

  defp text_field(id, name, label, value, required) do
    attrs = %{"id" => id, "name" => name, "type" => "text", "value" => value}
    attrs = if required, do: Map.put(attrs, "required", ""), else: attrs

    %{
      "key" => id |> String.replace_prefix("widget_", ""),
      "type" => "text",
      "wrapper_class" => "fieldset mb-3",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "control" => %{"class" => "w-full input", "attrs" => attrs, "options" => []},
      "hidden_control" => nil,
      "description" => nil,
      "errors" => []
    }
  end
end
