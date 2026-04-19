defmodule CadenceWeb.MissionNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :nav_item, :missions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Mission creation — implemented in a later task.</div>
    """
  end
end
