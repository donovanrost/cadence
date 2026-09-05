defmodule CadenceWeb.OpsDashboardViewerLive do
  @moduledoc """
  Read-oriented dashboard route boundary.

  Document-authoring events are rejected here; the protected editor route owns
  those mutations.
  """

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDashboardShowLive.Controller

  @editor_events ~w(
    layout_changed
    open_add_widget
    open_dashboard_sections
    edit_dashboard_section
    validate_dashboard_section
    save_dashboard_section
    remove_dashboard_section
    move_dashboard_section
    open_widget_config
    open_rename
    validate_widget
    pick_point
    preview_widget_binding
    save_widget
    remove_widget
    rename
    archive_dashboard
    publish_dashboard
    publish_dashboard_version
    save_runtime_defaults
    restore_version_as_draft
    save_editor
    review_editor
    discard_editor
    reload_editor
  )

  @impl true
  def mount(params, session, socket) do
    with {:ok, socket} <- Controller.mount(params, session, socket) do
      {:ok, assign(socket, :federated_query_params, %{})}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    with {:noreply, socket} <- Controller.handle_params(params, uri, socket) do
      {:noreply, assign(socket, :federated_query_params, Map.take(params, ~w(
         dashboard_id panel activity_filter activity_event selected_publish_issue selected_time
         time_mode time_axis from to limit_mode replay_run_id selection_view selected_widget
         selected_target selected_id selected_placement selected_data_view selected_scope_kind
         selected_scope_id selected_resource_id selected_spacecraft_id selected_contact_id
         selected_transport_id selected_source_endpoint_id selected_ground_station_id
         selected_scope_link_id realm data_source_id source_binding_id
       )))}
    end
  end

  @impl true
  defdelegate handle_info(message, socket), to: Controller

  @impl true
  defdelegate handle_async(name, result, socket), to: Controller

  @impl true
  def handle_event(event, _params, socket) when event in @editor_events do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Dashboard authoring actions require the protected Dashboard Editor."
     )}
  end

  def handle_event(event, params, socket), do: Controller.handle_event(event, params, socket)

  @impl true
  defdelegate terminate(reason, socket), to: Controller

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-show-surface"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={@federated_query_params}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
