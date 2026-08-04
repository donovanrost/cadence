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
  defdelegate mount(params, session, socket), to: Controller

  @impl true
  defdelegate handle_params(params, uri, socket), to: Controller

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
  defdelegate render(assigns), to: Controller
end
