defmodule CadenceWeb.OpsDashboardEditorLive do
  @moduledoc """
  Dashboard authoring route boundary.

  The router mounts this LiveView only after the dashboard-author policy check.
  """

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDashboardShowLive.Controller

  @impl true
  defdelegate mount(params, session, socket), to: Controller

  @impl true
  defdelegate handle_params(params, uri, socket), to: Controller

  @impl true
  defdelegate handle_info(message, socket), to: Controller

  @impl true
  defdelegate handle_async(name, result, socket), to: Controller

  @impl true
  defdelegate handle_event(event, params, socket), to: Controller

  @impl true
  defdelegate terminate(reason, socket), to: Controller

  @impl true
  defdelegate render(assigns), to: Controller
end
