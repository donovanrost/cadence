defmodule CadenceWeb.OpsDashboardShowLive.RouteHydration do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery
  alias CadenceWeb.OpsDashboardShowLive.SelectionHydration
  alias CadenceWeb.OpsDashboardShowLive.WidgetEditing

  def handle_params(socket, params, opts \\ []) when is_map(params) do
    cond do
      socket.assigns[:dashboard_document] == nil ->
        socket

      dashboard_editor_panel?(params) ->
        hydrate_dashboard_editor(socket, params, opts)

      socket.assigns.edit_mode? ->
        socket

      true ->
        hydrate_runtime_route(socket, params, opts)
    end
  end

  def assign_runtime_context(socket, runtime_context) do
    context_changed? = runtime_context_changed?(socket, runtime_context)
    runtime_assigns = RuntimeContext.field_assigns(runtime_context)

    selected_ref =
      DataLinkSelection.selected_ref_for_runtime_context(
        socket.assigns[:dashboard_selected_data_ref],
        runtime_context
      )

    socket
    |> maybe_increment_chart_epoch(context_changed?)
    |> maybe_mark_runtime_context_changed(context_changed?)
    |> assign(runtime_assigns)
    |> DocumentLifecycle.assign_render_items()
    |> assign(:dashboard_selected_data_ref, selected_ref)
  end

  defp assign_review_activity_panel(socket, %{"panel" => "versions"} = params) do
    activity_filter = ActivityViewModel.normalize_filter(params["activity_filter"])

    socket
    |> assign(:panel, :versions)
    |> assign(:dashboard_activity_filter, activity_filter)
    |> assign(:dashboard_activity_event_id, text_param(params["activity_event"]))
    |> assign(:dashboard_readiness_return_intent, readiness_return_intent(params))
    |> assign(:dashboard_selected_publish_issue_id, text_param(params["selected_publish_issue"]))
    |> assign(
      :dashboard_review_placement_id,
      selected_review_placement(params["selected_placement"], activity_filter)
    )
  end

  defp assign_review_activity_panel(socket, _params) do
    socket
    |> assign(:dashboard_activity_filter, nil)
    |> assign(:dashboard_activity_event_id, nil)
    |> assign(:dashboard_readiness_return_intent, nil)
    |> assign(:dashboard_review_placement_id, nil)
    |> assign(:dashboard_selected_publish_issue_id, nil)
  end

  defp hydrate_runtime_route(socket, params, opts) do
    runtime_context = runtime_context_from_params(socket, params, opts)
    panel_query = DataLinkSelection.panel_from_params(params)
    selection_query = DataLinkSelection.selection_query_from_params(params, panel_query)
    evidence_query = DataLinkSelection.evidence_query_from_params(params, panel_query)
    context_changed? = runtime_context_changed?(socket, runtime_context)

    socket =
      socket
      |> assign_review_activity_panel(params)
      |> assign(:dashboard_selection_query, selection_query)
      |> assign(:dashboard_evidence_query, evidence_query)
      |> assign(:dashboard_editor_focus, nil)
      |> assign_runtime_context(runtime_context)

    if context_changed? or is_nil(socket.assigns.dashboard_engine_result) do
      socket =
        resolve_engine(socket, resolve_mode(socket), [reason: :runtime_context_changed], opts)

      if socket.assigns[:dashboard_engine_result] do
        SelectionHydration.hydrate_from_query(socket, opts)
      else
        socket
      end
    else
      SelectionHydration.hydrate_from_query(socket, opts)
    end
  end

  defp hydrate_dashboard_editor(socket, params, opts) do
    socket =
      socket
      |> assign(:dashboard_activity_filter, nil)
      |> assign(:dashboard_activity_event_id, nil)
      |> assign(:dashboard_readiness_return_intent, nil)
      |> assign(:dashboard_review_placement_id, nil)
      |> assign(
        :dashboard_selected_publish_issue_id,
        text_param(params["selected_publish_issue"])
      )
      |> assign(:dashboard_selection_query, nil)
      |> assign(:dashboard_evidence_query, nil)
      |> assign(:dashboard_editor_focus, dashboard_editor_focus(params))
      |> maybe_enter_edit_mode(opts)

    case dashboard_editor_placement_id(params) do
      placement_id when is_binary(placement_id) ->
        open_widget_config_fn(opts).(socket, placement_id)

      _missing ->
        socket
    end
  end

  defp maybe_enter_edit_mode(%{assigns: %{edit_mode?: true}} = socket, _opts), do: socket

  defp maybe_enter_edit_mode(socket, opts) do
    enter_edit_mode_fn(opts).(socket, opts)
  end

  defp dashboard_editor_panel?(%{"panel" => panel}), do: text_param(panel) == "dashboard_editor"
  defp dashboard_editor_panel?(_params), do: false

  defp dashboard_editor_placement_id(params) do
    text_param(params["selected_placement"]) || text_param(params["placement_id"])
  end

  defp dashboard_editor_focus(params) do
    %{
      placement_id: dashboard_editor_placement_id(params),
      publish_issue_id: text_param(params["selected_publish_issue"]),
      source_empty_reason: text_param(params["source_empty_reason"]),
      unsupported_observables: text_list_param(params["unsupported_observables"]),
      requested_observables: text_list_param(params["requested_observables"]),
      requested_sampling: text_param(params["requested_sampling"]),
      supported_sampling: text_list_param(params["supported_sampling"]),
      requested_products: text_list_param(params["requested_products"]),
      requested_source_products: text_list_param(params["requested_source_products"]),
      supported_products: text_list_param(params["supported_products"]),
      requested_product_families: text_list_param(params["requested_product_families"]),
      supported_product_families: text_list_param(params["supported_product_families"])
    }
    |> Enum.reject(fn {_key, value} -> empty_focus_value?(value) end)
    |> Map.new()
    |> case do
      focus when map_size(focus) == 0 -> nil
      focus -> focus
    end
  end

  defp text_list_param(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&text_param/1)
    |> Enum.reject(&is_nil/1)
  end

  defp text_list_param(values) when is_list(values) do
    values
    |> Enum.map(&text_param/1)
    |> Enum.reject(&is_nil/1)
  end

  defp text_list_param(_value), do: []

  defp empty_focus_value?(nil), do: true
  defp empty_focus_value?([]), do: true
  defp empty_focus_value?(_value), do: false

  defp readiness_return_intent(%{"refresh_readiness" => "source_return"}),
    do: "source_return"

  defp readiness_return_intent(_params), do: nil

  defp selected_review_placement(value, :open_comparison_reviews), do: text_param(value)
  defp selected_review_placement(_value, _activity_filter), do: nil

  def runtime_context_for_document(socket, %Document{} = document, opts \\ []) do
    runtime_context_from_params(socket, %{}, Keyword.put(opts, :document, document))
  end

  def runtime_context_from_params(socket, params, opts \\ []) do
    RuntimeQuery.runtime_context_from_params(
      params,
      socket.assigns.current_scope,
      socket.assigns.current_mission,
      socket.assigns.spacecraft,
      socket.assigns.dashboard_data_realms,
      socket.assigns.dashboard_data_bindings,
      Keyword.get(opts, :document, socket.assigns.dashboard_document),
      valid_contact?: valid_contact_callback(opts),
      valid_operational_resource_scope?: valid_operational_resource_scope_callback(opts)
    )
  end

  def runtime_context_changed?(socket, runtime_context) do
    RuntimeContext.changed?(socket.assigns, runtime_context)
  end

  defp resolve_engine(socket, mode, resolve_opts, opts) do
    case Keyword.get(opts, :resolve_engine) do
      callback when is_function(callback, 3) -> callback.(socket, mode, resolve_opts)
      _missing -> Runtime.resolve_engine(socket, mode, resolve_opts)
    end
  end

  defp resolve_mode(socket) do
    if socket.assigns.dashboard_engine_result, do: :context_change, else: :initial
  end

  defp maybe_increment_chart_epoch(socket, true),
    do: assign(socket, :chart_epoch, socket.assigns.chart_epoch + 1)

  defp maybe_increment_chart_epoch(socket, false), do: socket

  defp maybe_mark_runtime_context_changed(socket, true),
    do: assign(socket, :dashboard_runtime_context_since, DateTime.utc_now())

  defp maybe_mark_runtime_context_changed(socket, false), do: socket

  defp valid_contact_callback(opts) do
    Keyword.get(opts, :valid_contact?, fn _scope, _mission, _contact_id -> false end)
  end

  defp valid_operational_resource_scope_callback(opts) do
    Keyword.get(opts, :valid_operational_resource_scope?, fn
      _scope, _mission, _scope_kind, _scope_id -> true
    end)
  end

  defp enter_edit_mode_fn(opts),
    do: Keyword.get(opts, :enter_edit_mode, &WidgetEditing.enter_edit_mode/2)

  defp open_widget_config_fn(opts),
    do: Keyword.get(opts, :open_widget_config, &WidgetEditing.open_widget_config/2)

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(_value), do: nil
end
