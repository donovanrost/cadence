defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    summary = load_summary(socket.assigns)

    {:ok,
     socket
     |> assign(:page_title, "Comms")
     |> assign(:nav_item, :comms_overview)
     |> assign(summary)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-overview-page" class="space-y-6">
      <.comms_header current_mission={@current_mission} active={:overview} />

      <section id="mission-network-resources" class="card bg-base-200 border border-base-300">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Network Resources</p>
              <h2 class="text-lg font-semibold">Shared mission connectivity</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Providers, protocol behaviors, and link templates are mission-owned.
                Spacecraft-specific interpretation stays on each spacecraft.
              </p>
            </div>
            <.status_badge status={if @blocking_findings == 0, do: :ready, else: :warning} />
          </div>

          <div class="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <.network_resource_card
              id="mission-network-links"
              title="Links"
              value={@path_template_count}
              description="Create shared mission paths without editing raw objects."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/links/new"}
            />
            <.network_resource_card
              id="mission-network-protocol-behaviors"
              title="Protocol Behaviors"
              value={@transport_profile_count}
              description="Reusable path-local protocol behavior."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors"}
            />
            <.network_resource_card
              id="mission-network-validation"
              title="Validation"
              value={@finding_count}
              description="Mission network, assignment, and interpretation findings."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/validation"}
            />
            <.network_resource_card
              id="mission-network-advanced"
              title="Advanced"
              value={@source_endpoint_count}
              description="Runtime identities and routing internals."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/advanced/runtime-identities"}
            />
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :description, :string, required: true
  attr :navigate, :string, required: true

  defp network_resource_card(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="rounded border border-base-300 bg-base-100/40 p-4 transition hover:border-primary/50 hover:bg-base-100"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <p class="hud-label mb-2">{@title}</p>
          <p class="text-sm text-base-content/60">{@description}</p>
        </div>
        <span class="font-mono text-xl font-bold">{@value}</span>
      </div>
    </.link>
    """
  end

  defp load_summary(%{current_scope: scope, current_mission: mission}) do
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

    findings =
      CadenceWeb.CommsValidationLive.findings_for_resources(
        scope.organization_id,
        mission.mission_id,
        spacecraft,
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles
      )

    %{
      source_endpoint_count: length(source_endpoints),
      transport_profile_count: length(transport_profiles),
      path_template_count: length(path_templates),
      finding_count: length(findings),
      blocking_findings: Enum.count(findings, &(&1.severity == :missing))
    }
  end
end
