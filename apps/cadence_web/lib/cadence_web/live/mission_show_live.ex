defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Mission")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Mission overview — implemented in a later task.</div>
    """
  end
end
