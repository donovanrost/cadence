defmodule CadenceWeb.OpsDashboardShowLive.WidgetEditing do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Cadence.Dashboards.{Document, Placement, PlacementEditor}
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation
  alias Phoenix.HTML.Form

  def enter_edit_mode(socket, opts) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case Cadence.Dashboards.fetch_document_for_mode(
           scope.organization_id,
           mission.mission_id,
           document.dashboard_id,
           :edit
         ) do
      {:ok, draft_document} ->
        socket
        |> DocumentLifecycle.assign_document(draft_document, :draft)
        |> assign_runtime_context(opts, draft_document)
        |> assign(:edit_mode?, true)
        |> assign(:panel, nil)

      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard not found.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, :dashboard_archived} ->
        socket
        |> put_flash(:error, "Dashboard is archived.")
        |> push_navigate(to: dashboard_list_path(opts, socket))
    end
  end

  def exit_edit_mode(socket, opts) do
    socket =
      socket
      |> assign(:edit_mode?, false)
      |> assign(:panel, nil)
      |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)

    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    case DocumentLifecycle.fetch_operator_document(scope, mission, document.dashboard_id) do
      {:ok, operator_document, document_mode} ->
        socket
        |> DocumentLifecycle.assign_document(operator_document, document_mode)
        |> assign_runtime_context(opts, operator_document)
        |> Runtime.resolve_engine(:context_change, reason: :edit_mode_closed)

      {:error, :dashboard_not_found} ->
        socket
        |> put_flash(:error, "Dashboard not found.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, :dashboard_archived} ->
        socket
        |> put_flash(:error, "Dashboard is archived.")
        |> push_navigate(to: dashboard_list_path(opts, socket))

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to load dashboard: #{inspect(reason)}")
        |> push_navigate(to: dashboard_list_path(opts, socket))
    end
  end

  def layout_changed(socket, layouts, opts) when is_list(layouts) do
    if socket.assigns.edit_mode? do
      document = Document.apply_layouts(socket.assigns.dashboard_document, layouts)
      persist_document_socket(opts, socket, document, change_summary: "Updated layout")
    else
      socket
    end
  end

  def open_add_widget(socket) do
    socket
    |> assign(:panel, :add_widget)
    |> assign(:widget_error, nil)
    |> assign(:selected_point_id, nil)
    |> assign(:selected_point_ids, [])
    |> assign(:widget_form, to_form(WidgetFormPresentation.widget_form_defaults(), as: :widget))
  end

  def open_widget_config(socket, placement_id) do
    case find_render_item(socket, placement_id) do
      nil ->
        socket

      %{placement: placement} ->
        socket
        |> assign(:panel, {:edit_placement, placement_id})
        |> assign(:widget_error, nil)
        |> assign(:selected_point_id, PlacementEditor.selected_observable(placement))
        |> assign(:selected_point_ids, PlacementEditor.selected_observables(placement))
        |> assign(
          :widget_form,
          to_form(WidgetFormPresentation.placement_to_form_params(placement), as: :widget)
        )
    end
  end

  def validate_widget(socket, params) when is_map(params) do
    assign(socket, :widget_form, to_form(params, as: :widget))
  end

  def pick_point(socket, point_id) do
    selected_point_ids =
      if multi_select_widget_form?(socket) do
        toggle_selected_point_id(socket.assigns.selected_point_ids, point_id)
      else
        [point_id]
      end

    socket
    |> assign(:selected_point_id, List.first(selected_point_ids))
    |> assign(:selected_point_ids, selected_point_ids)
  end

  def save_widget(socket, params, opts) when is_map(params) do
    selected_observables = selected_observables_for_save(socket)

    case PlacementEditor.build_placement(
           params,
           selected_observables,
           socket.assigns.panel,
           editable_placement(socket),
           authoring_opts(socket)
         ) do
      {:ok, %Placement{} = placement} ->
        document = Document.put_placement(socket.assigns.dashboard_document, placement)
        change_summary = widget_change_summary(socket.assigns.panel)

        case persist_document(opts, socket, document, change_summary: change_summary) do
          {:ok, socket} ->
            socket
            |> reset_widget_editor()
            |> refresh_widget_data(opts)

          {:error, socket} ->
            socket
        end

      {:error, {_kind, message}} ->
        assign(socket, :widget_error, message)
    end
  end

  def remove_widget(socket, placement_id, opts) do
    document = Document.remove_placement(socket.assigns.dashboard_document, placement_id)

    persist_document_socket(
      opts,
      socket,
      document,
      [change_summary: "Removed widget"],
      &refresh_widget_data(&1, opts)
    )
  end

  def refresh_widget_data(socket) do
    socket
    |> assign(:chart_epoch, socket.assigns.chart_epoch + 1)
    |> Runtime.resolve_engine(:context_change, reason: :dashboard_document_changed)
  end

  def selected_observables_for_save(%{assigns: %{selected_point_ids: point_ids}})
      when is_list(point_ids) and point_ids != [],
      do: point_ids

  def selected_observables_for_save(%{assigns: %{selected_point_id: point_id}})
      when is_binary(point_id),
      do: point_id

  def selected_observables_for_save(
        %{assigns: %{panel: {:edit_placement, placement_id}}} = socket
      ) do
    socket
    |> existing_placement(placement_id)
    |> PlacementEditor.selected_observables()
  end

  def selected_observables_for_save(_socket), do: []

  def multi_select_widget_form?(socket) do
    type = widget_form_type(socket)

    type in ["status_matrix", "data_table"] or
      (type == "state_timeline" and
         widget_form_binding_source(socket) == "operational_observables")
  end

  def toggle_selected_point_id(point_ids, point_id) do
    point_ids = List.wrap(point_ids)

    if point_id in point_ids do
      Enum.reject(point_ids, &(&1 == point_id))
    else
      point_ids ++ [point_id]
    end
  end

  def editable_placement(%{assigns: %{panel: {:edit_placement, placement_id}}} = socket) do
    existing_placement(socket, placement_id)
  end

  def editable_placement(_socket), do: nil

  def existing_placement(socket, placement_id) do
    case find_render_item(socket, placement_id) do
      %{placement: %Placement{} = placement} -> placement
      _missing -> nil
    end
  end

  def find_render_item(socket, placement_id) do
    Enum.find(socket.assigns.dashboard_render_items, &(&1.placement_id == placement_id))
  end

  defp reset_widget_editor(socket) do
    socket
    |> assign(:panel, nil)
    |> assign(:widget_error, nil)
    |> assign(:selected_point_id, nil)
    |> assign(:selected_point_ids, [])
    |> assign(:widget_form, to_form(WidgetFormPresentation.widget_form_defaults(), as: :widget))
  end

  defp widget_change_summary({:edit_placement, _placement_id}), do: "Updated widget"
  defp widget_change_summary(_panel), do: "Added widget"

  defp authoring_opts(socket) do
    [authoring_scope_context: Map.get(socket.assigns, :dashboard_scope_context)]
  end

  defp widget_form_type(socket), do: Form.input_value(socket.assigns.widget_form, :type)

  defp widget_form_binding_source(socket),
    do: Form.input_value(socket.assigns.widget_form, :binding_source)

  defp assign_runtime_context(socket, opts, document) do
    opts
    |> Keyword.fetch!(:assign_runtime_context)
    |> then(& &1.(socket, document))
  end

  defp persist_document_socket(opts, socket, %Document{} = document, persist_opts) do
    persist_document_socket(opts, socket, document, persist_opts, & &1)
  end

  defp persist_document_socket(opts, socket, %Document{} = document, persist_opts, on_success) do
    case persist_document(opts, socket, document, persist_opts) do
      {:ok, socket} -> on_success.(socket)
      {:error, socket} -> socket
    end
  end

  defp persist_document(opts, socket, %Document{} = document, persist_opts) do
    opts
    |> Keyword.fetch!(:persist_document)
    |> then(& &1.(socket, document, persist_opts))
  end

  defp refresh_widget_data(socket, opts) do
    case Keyword.get(opts, :refresh_widget_data) do
      nil -> refresh_widget_data(socket)
      callback when is_function(callback, 1) -> callback.(socket)
    end
  end

  defp dashboard_list_path(opts, socket) do
    opts
    |> Keyword.fetch!(:dashboard_list_path)
    |> then(& &1.(socket))
  end
end
