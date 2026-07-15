defmodule CadenceWeb.CommsProviderListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.GroundNetworks

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    providers = GroundNetworks.list_providers(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Ground Network Providers")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_count, length(providers))
     |> assign(:providers_empty?, providers == [])
     |> stream_configure(:providers, dom_id: &"mission-provider-#{&1.provider_id}")
     |> stream(:providers, providers)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-providers-page" class="space-y-6">
      <.page_header
        title="Ground Network Providers"
        subtitle="Provider control planes for scheduling, inventory discovery, and delivery profile negotiation."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Comms", ~p"/missions/#{@current_mission.mission_id}/comms"},
          {"Providers", nil}
        ]}
      >
        <:title_suffix>{@provider_count} configured</:title_suffix>
        <:actions>
          <.button
            id="new-provider-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
            class="gap-1"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Provider
          </.button>
        </:actions>
      </.page_header>

      <.empty_state
        :if={@providers_empty?}
        title="No ground network providers"
        description="Connect this mission to a simulator or commercial ground network control plane."
        action_label="Configure the first provider"
        action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers/new"}
      />

      <.card :if={!@providers_empty?} padding={:none}>
        <.table id="mission-providers-table" rows={@streams.providers}>
          <:col :let={provider} label="Provider" class="font-medium">
            <.link
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/comms/providers/#{provider.provider_id}"
              }
              class="text-primary hover:underline"
            >
              {provider.display_name}
            </.link>
            <span class="ml-2 font-mono text-[0.65rem] uppercase tracking-wide text-info">
              Simulated
            </span>
          </:col>
          <:col :let={provider} label="Control Plane">
            <.status_badge
              status={control_plane_status(provider)}
              label={control_plane_label(provider)}
            />
          </:col>
          <:col :let={provider} label="Environment" mono>
            {provider.environment_ref}
          </:col>
          <:col :let={provider} label="Inventory Sync" mono>
            {timestamp_label(provider.last_synced_at)}
          </:col>
          <:col :let={provider} label="Version" mono>v{provider.version}</:col>
        </.table>
      </.card>
    </div>
    """
  end

  defp control_plane_status(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> :ready
      "failed" -> :attention
      _other -> :blocked
    end
  end

  defp control_plane_label(provider) do
    case get_in(provider.metadata, ["control_plane", "status"]) do
      "healthy" -> "Healthy"
      "failed" -> "Validation failed"
      _other -> "Not validated"
    end
  end

  defp timestamp_label(nil), do: "Never"

  defp timestamp_label(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%MZ")
end
