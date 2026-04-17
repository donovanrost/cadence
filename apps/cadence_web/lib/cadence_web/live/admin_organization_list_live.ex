defmodule CadenceWeb.AdminOrganizationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Organizations")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Admin placeholder</div>
    """
  end
end
