defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  alias CadenceWeb.CommsValidation

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

          <div class="mt-5 grid gap-3 md:grid-cols-2">
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
          </div>
        </div>
      </section>

      <section id="comms-validation-page" class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Setup Checks</p>
              <h2 class="text-lg font-semibold">Comms Validation</h2>
              <p class="mt-1 text-sm text-base-content/60">
                These checks focus on whether saved comms setup can produce usable operational
                paths later. Runtime contact health belongs under the future ops workspace.
              </p>
            </div>
            <.status_badge
              status={if @findings == [], do: :ready, else: :warning}
              label={if @findings == [], do: "No Findings", else: "#{length(@findings)} Findings"}
            />
          </div>

          <%= if @findings == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-check-circle"
                title="No comms setup findings"
                description="This mission has enough comms setup structure for the current validation rules."
              />
            </div>
          <% else %>
            <div id="comms-validation-findings" class="mt-6 space-y-5">
              <section :for={group <- @finding_groups} id={group.id} class="space-y-3">
                <div>
                  <p class="hud-label mb-1">{group.title}</p>
                  <p class="text-sm text-base-content/60">{group.description}</p>
                </div>

                <div
                  :for={finding <- group.findings}
                  class="border border-base-300 bg-base-100/40 p-4"
                >
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <h3 class="font-semibold">{finding.title}</h3>
                      <p class="mt-1 text-sm text-base-content/60">{finding.body}</p>
                      <.link
                        :if={Map.get(finding, :action_navigate)}
                        navigate={finding.action_navigate}
                        class="btn btn-primary btn-xs mt-3"
                      >
                        {Map.get(finding, :action_label, "Review")}
                      </.link>
                    </div>
                    <.status_badge
                      status={finding.severity}
                      label={CommsValidation.finding_label(finding.severity)}
                    />
                  </div>
                </div>
              </section>
            </div>
          <% end %>
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
      CommsValidation.findings_for_resources(
        scope.organization_id,
        mission.mission_id,
        spacecraft,
        source_endpoints,
        path_templates,
        provider_profiles,
        transport_profiles
      )

    %{
      transport_profile_count: length(transport_profiles),
      path_template_count: length(path_templates),
      findings: findings,
      finding_groups: CommsValidation.finding_groups(findings),
      blocking_findings: Enum.count(findings, &(&1.severity == :missing))
    }
  end
end
