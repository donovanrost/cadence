defmodule CadenceWeb.OpsTelemetryExploreLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @query_params [
    "point_id",
    "spacecraft_id",
    "scope_kind",
    "scope_id",
    "time_mode",
    "time_axis",
    "from",
    "to",
    "replay_run_id",
    "order",
    "limit",
    "selection_view",
    "validity_state",
    "realm",
    "logical_source",
    "data_source_id",
    "source_binding_id",
    "source_dashboard_id",
    "sample_id",
    "selected_time",
    "question",
    "limit_mode"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Telemetry Explore")
     |> assign(:ops_nav_item, :explore)
     |> assign(:federated_query_params, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :federated_query_params, Map.take(params, @query_params))}
  end

  @impl true
  def render(assigns), do: CadenceWeb.OpsTelemetryExploreComponents.page(assigns)
end
