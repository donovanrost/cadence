defmodule CadenceWeb.OpsDashboardShowLive.ViewTestSupport do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1, flunk: 1, refute: 1]
  import Phoenix.LiveViewTest, only: [has_element?: 2, render: 1]

  alias CadenceWeb.AsyncLiveViewTestSupport

  @default_timeout 5_000
  @resolved_runtime_selector ~s(#ops-dashboard-show-page[data-runtime-status="idle"][data-runtime-resolved="true"])

  defmacro __using__(_opts) do
    quote do
      alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport, as: DashboardViewTestSupport

      import Phoenix.LiveViewTest, except: [live: 2]
      import DashboardViewTestSupport

      defmacrop live(conn, path) do
        quote do
          DashboardViewTestSupport.await_live_result(
            Phoenix.LiveViewTest.live(unquote(conn), unquote(path))
          )
        end
      end
    end
  end

  def await_live_result(result, timeout \\ @default_timeout) do
    case result do
      {:ok, view, html} ->
        await_dashboard_resolved(view, timeout)
        {:ok, view, html}

      other ->
        other
    end
  end

  def render_dashboard_async(view, timeout \\ @default_timeout) do
    AsyncLiveViewTestSupport.render_async(view, timeout)
  end

  def await_dashboard_resolved(view, timeout \\ @default_timeout) do
    render_dashboard_async(view, timeout)

    if has_element?(view, @resolved_runtime_selector) do
      view
    else
      flunk("dashboard runtime did not resolve within #{timeout}ms")
    end
  end

  defdelegate track_dashboard_view(view), to: AsyncLiveViewTestSupport, as: :track_async_view

  def stop_dashboard_views(views, timeout \\ @default_timeout) when is_list(views) do
    AsyncLiveViewTestSupport.stop_async_views(views, timeout)
  end

  def stop_dashboard_view(view, timeout \\ @default_timeout) do
    AsyncLiveViewTestSupport.stop_async_view(view, timeout)
  end

  def widget_point_presentation(rendered, component_id) do
    vue = LiveVue.Test.get_vue(rendered, id: component_id)

    assert vue.component == "WidgetPoint"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["component_id"] == component_id

    vue.props["presentation"]
  end

  def widget_point_chart_props(rendered, component_id) do
    rendered
    |> widget_point_presentation(component_id)
    |> Map.fetch!("chart")
    |> Map.fetch!("props")
  end

  def widget_point_presentation_by_kind(rendered, kind) do
    html = rendered_html(rendered)

    Enum.find_value(widget_point_host_ids(html), fn component_id ->
      presentation = widget_point_presentation(html, component_id)

      if presentation["kind"] == kind, do: presentation
    end)
  end

  def widget_point_value_text(rendered, placement_id) do
    rendered
    |> widget_point_presentation("widget-point-#{placement_id}-component")
    |> Map.fetch!("value")
    |> Map.fetch!("text")
  end

  def widget_header_presentation(rendered, placement_id) do
    component_id = "dashboard-widget-header-#{placement_id}-component"
    vue = LiveVue.Test.get_vue(rendered, id: component_id)

    assert vue.component == "DashboardWidgetHeader"
    assert vue.id == component_id
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["component_id"] == component_id

    vue.props["presentation"]
  end

  def widget_query_presentation(rendered, placement_id) do
    rendered
    |> widget_header_presentation(placement_id)
    |> get_in(["actions", "details", "body", "actions", "query"])
  end

  def widget_header_source_presentation(rendered, placement_id) do
    rendered
    |> widget_header_presentation(placement_id)
    |> get_in(["actions", "details", "body", "indicators", "source"])
  end

  def widget_frame_evidence_presentation(rendered, placement_id) do
    rendered
    |> widget_header_presentation(placement_id)
    |> get_in(["actions", "details", "body", "actions", "frame_evidence"])
  end

  def assert_widget_frame_evidence(rendered, placement_id, expected_attrs) do
    presentation = widget_frame_evidence_presentation(rendered, placement_id)
    assert presentation
    assert attrs_match?(presentation["attrs"], expected_attrs)
    presentation
  end

  def widget_header_action_event_params(%{"attrs" => attrs}) do
    attrs
    |> Enum.flat_map(fn
      {"phx-value-" <> name, value} -> [{name, value}]
      {_name, _value} -> []
    end)
    |> Map.new()
  end

  def widget_warning_presentation(rendered, placement_id, component_id) do
    rendered
    |> widget_header_presentation(placement_id)
    |> find_component_presentation(component_id)
  end

  def widget_warning_presentations(rendered, placement_id) do
    rendered
    |> widget_header_presentation(placement_id)
    |> get_in(["actions", "details", "body", "indicators", "warnings"])
  end

  def widget_rows_presentation(rendered, kind, placement_id) do
    component_id = "widget-rows-#{String.replace(kind, "_", "-")}-#{placement_id}-component"
    vue = LiveVue.Test.get_vue(rendered, id: component_id)

    assert vue.component == "WidgetRows"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["kind"] == kind
    assert vue.props["presentation"]["component_id"] == component_id

    vue.props["presentation"]
  end

  def assert_widget_row(rendered, kind, placement_id, expected_attrs) do
    row =
      rendered
      |> widget_rows_presentation(kind, placement_id)
      |> widget_rows()
      |> Enum.find(&attrs_match?(&1["attrs"], expected_attrs))

    assert row
    row
  end

  def refute_widget_row(rendered, kind, placement_id, expected_attrs) do
    row =
      rendered
      |> widget_rows_presentation(kind, placement_id)
      |> widget_rows()
      |> Enum.find(&attrs_match?(&1["attrs"], expected_attrs))

    refute row
  end

  def widget_row_field(row, key) do
    Enum.find(Map.get(row, "cells", []), &(&1["key"] == key))
  end

  def assert_widget_row_field(row, key, expected_text) do
    field = widget_row_field(row, key)
    assert field

    texts =
      [field["text"] | Enum.map(Map.get(field, "badges", []), & &1["text"])]
      |> Enum.reject(&is_nil/1)

    assert expected_text in texts
    field
  end

  def widget_data_link_presentation(rendered, component_id) do
    html = rendered_html(rendered)

    direct_widget_data_link_presentation(html, component_id) ||
      Enum.find_value(widget_header_host_ids(html), fn host_id ->
        html
        |> LiveVue.Test.get_vue(id: host_id)
        |> Map.fetch!(:props)
        |> Map.fetch!("presentation")
        |> find_component_presentation(component_id)
      end) ||
      Enum.find_value(widget_rows_host_ids(html), fn host_id ->
        html
        |> LiveVue.Test.get_vue(id: host_id)
        |> Map.fetch!(:props)
        |> Map.fetch!("presentation")
        |> find_component_presentation(component_id)
      end)
  end

  def dashboard_runtime_controls(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> get_in([
      "viewer",
      "operational_scope",
      "panel",
      "body",
      "query_options",
      "panel",
      "runtime_controls"
    ])
  end

  def dashboard_toolbar_presentation(view_or_html) do
    vue = LiveVue.Test.get_vue(view_or_html, id: "dashboard-toolbar-component")

    assert vue.component == "DashboardToolbar"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  def dashboard_time_picker_presentation(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> get_in(["viewer", "time_picker"])
  end

  def dashboard_context_selector_presentation(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> get_in(["viewer", "operational_scope", "panel", "body", "context"])
  end

  def dashboard_editor_actions_presentation(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> Map.get("editor_actions")
  end

  def dashboard_comparison_toggle_presentation(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> Map.get("comparison_toggle")
  end

  def dashboard_toolbar_data_health(view_or_html) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> Map.get("data_health")
  end

  def dashboard_toolbar_menu_item(view_or_html, id) do
    view_or_html
    |> dashboard_toolbar_presentation()
    |> get_in(["menu", "panel", "items"])
    |> Enum.find(&(&1["key"] == id))
  end

  def dashboard_runtime_control(runtime_controls, id) do
    form = Map.fetch!(runtime_controls, "form")

    fields =
      form["hidden_fields"] ++
        form["source"]["fields"] ++
        form["representation"]["fields"] ++
        form["semantics"]["fields"] ++ form["markers"]["toggles"]["fields"]

    Enum.find(fields, fn field -> dashboard_runtime_control_attrs(field)["id"] == id end)
  end

  def dashboard_runtime_control_attrs(%{"attrs" => attrs}), do: attrs
  def dashboard_runtime_control_attrs(%{"input_attrs" => attrs}), do: attrs

  def dashboard_runtime_option(runtime_controls, id, value) do
    runtime_controls
    |> dashboard_runtime_control(id)
    |> Map.fetch!("options")
    |> Enum.find(&(&1["value"] == value))
  end

  def dashboard_runtime_change_params(runtime_controls, values_by_id) do
    Enum.reduce(values_by_id, %{}, fn {id, value}, params ->
      field = dashboard_runtime_control(runtime_controls, id)

      if field do
        validate_dashboard_runtime_value!(id, field, value, values_by_id)

        put_dashboard_runtime_param(
          params,
          dashboard_runtime_control_attrs(field)["name"],
          value
        )
      else
        raise ArgumentError, "unknown dashboard runtime control #{inspect(id)}"
      end
    end)
  end

  def render_dashboard_runtime_change(view, runtime_controls, values_by_id) do
    event = runtime_controls["form"]["attrs"]["phx-change"]
    params = dashboard_runtime_change_params(runtime_controls, values_by_id)
    Phoenix.LiveViewTest.render_change(view, event, params)
  end

  defp validate_dashboard_runtime_value!(
         "dashboard-source-binding",
         _field,
         _value,
         values_by_id
       )
       when is_map_key(values_by_id, "dashboard-data-realm"),
       do: :ok

  defp validate_dashboard_runtime_value!(
         "dashboard-compare-data-view",
         _field,
         _value,
         values_by_id
       )
       when is_map_key(values_by_id, "dashboard-data-view"),
       do: :ok

  defp validate_dashboard_runtime_value!(_id, %{"options" => options}, value, _values_by_id) do
    if Enum.any?(options, &(&1["value"] == value and not &1["disabled"])) do
      :ok
    else
      raise ArgumentError, "unavailable dashboard runtime option #{inspect(value)}"
    end
  end

  defp validate_dashboard_runtime_value!(
         _id,
         %{"input_attrs" => %{"type" => "checkbox"}},
         value,
         _values_by_id
       )
       when value in ["true", "false"],
       do: :ok

  defp validate_dashboard_runtime_value!(_id, _field, _value, _values_by_id), do: :ok

  defp put_dashboard_runtime_param(params, name, value) do
    case Regex.run(~r/^([^\[]+)\[([^\]]+)\]$/, name) do
      [_match, parent, child] ->
        Map.update(params, parent, %{child => value}, &Map.put(&1, child, value))

      nil ->
        Map.put(params, name, value)
    end
  end

  defp widget_rows(%{"kind" => "state_timeline", "lanes" => lanes}) do
    Enum.flat_map(lanes, & &1["rows"])
  end

  defp widget_rows(%{"rows" => rows}), do: rows

  defp attrs_match?(attrs, expected_attrs) do
    Enum.all?(expected_attrs, fn {name, value} -> attrs[name] == value end)
  end

  defp rendered_html(rendered) when is_binary(rendered), do: rendered
  defp rendered_html(view), do: render(view)

  defp widget_rows_host_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([phx-hook="VueHook"][data-name="WidgetRows"]))
    |> LazyHTML.attribute("id")
  end

  defp widget_point_host_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([id^="widget-point-"][id$="-component"]))
    |> LazyHTML.attribute("id")
  end

  defp widget_header_host_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([id^="dashboard-widget-header-"][id$="-component"]))
    |> LazyHTML.attribute("id")
  end

  defp direct_widget_data_link_presentation(html, component_id) do
    vue = LiveVue.Test.get_vue(html, id: component_id)

    if vue.component == "WidgetDataLinks" do
      vue.props["presentation"]
    end
  rescue
    RuntimeError -> nil
  end

  defp find_component_presentation(
         %{"component_id" => component_id} = presentation,
         component_id
       ),
       do: presentation

  defp find_component_presentation(value, component_id) when is_map(value) do
    Enum.find_value(value, fn {_key, nested} ->
      find_component_presentation(nested, component_id)
    end)
  end

  defp find_component_presentation(value, component_id) when is_list(value) do
    Enum.find_value(value, &find_component_presentation(&1, component_id))
  end

  defp find_component_presentation(_value, _component_id), do: nil
end
