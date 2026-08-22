defmodule CadenceWeb.OrganizationLive.Show do
  use CadenceWeb, :live_view

  alias Cadence.{Missions, Organizations}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    organization = Organizations.get_organization!(id)
    missions = Missions.list_missions(organization.id)
    stats = Organizations.get_organization_stats(organization)

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:organization, organization)
     |> assign(:missions, missions)
     |> assign(:stats, stats)}
  end

  defp page_title(:show), do: "Show Organization"
  defp page_title(:edit), do: "Edit Organization"
end
