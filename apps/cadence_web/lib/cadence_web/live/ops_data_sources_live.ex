defmodule CadenceWeb.OpsDataSourcesLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDataSourcesLive.Page

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data Sources")
     |> assign(:ops_nav_item, :data_sources)
     |> assign(:federated_query_params, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :federated_query_params, Map.take(params, ["data_source_id"]))}
  end

  @impl true
  def render(assigns), do: Page.render(assigns)
end
