defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>Placeholder — implemented in Task 4.</div>
    """
  end
end
