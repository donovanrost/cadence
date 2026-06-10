defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

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
      <div class="border-b border-primary/20 pb-4">
        <p class="hud-label text-base-content/50">Communications</p>
        <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
          {@current_mission.display_name} &middot;
          <span class="text-base-content/40 font-normal">Mission Comms</span>
        </h1>
      </div>

      <section id="comms-transports" class="card bg-base-200 border border-base-300 hud-corners">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Transport</p>
              <div class="flex items-baseline gap-4">
                <span class="mc-value-large text-primary">{@transport_count}</span>
                <span class="text-sm text-base-content/60">
                  transport<%= if @transport_count == 1, do: "", else: "s" %> configured
                </span>
              </div>
              <p class="mt-3 max-w-2xl text-sm text-base-content/60">
                Transports describe durable capabilities for moving bytes. Routing rules will decide how spacecraft use those capabilities.
              </p>
            </div>
            <.status_badge status={if @transport_count > 0, do: :ready, else: :attention} />
          </div>

          <%= if @transports == [] do %>
            <div class="mt-6 rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
              <p class="hud-label mb-2 text-base-content/60">No transports configured</p>
              <p class="text-sm text-base-content/60 max-w-md mx-auto">
                Add a transport to describe a byte-moving capability for this mission.
              </p>
              <div class="mt-5">
                <.link
                  navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
                  class="btn btn-primary btn-sm hover-glow-cyan transition-glow"
                >
                  Add a transport
                </.link>
              </div>
            </div>
          <% else %>
            <ul class="mt-6 grid gap-3 md:grid-cols-2">
              <li :for={transport <- @transports}>
                <.link
                  navigate={
                    ~p"/missions/#{@current_mission.mission_id}/comms/transports/#{transport.transport_id}"
                  }
                  class="block rounded border border-base-300 bg-base-100/40 p-4 border-l-2 border-l-transparent hover:border-l-primary/60 hover-glow-cyan transition-glow"
                >
                  <p class="font-medium">{transport.display_name}</p>
                  <p class="mt-1 font-mono text-xs text-base-content/50">
                    {transport.transport_kind} · {transport.direction_capability} · v{transport.version}
                  </p>
                </.link>
              </li>
            </ul>

            <div class="mt-5 flex gap-4 text-sm">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports"}
                class="text-primary hover:underline"
              >
                Manage transports &rarr;
              </.link>
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}/comms/transports/new"}
                class="text-primary hover:underline"
              >
                + Add a transport
              </.link>
            </div>
          <% end %>
        </div>
      </section>

      <section id="comms-validation-page" class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Setup Checks</p>
              <h2 class="text-lg font-semibold">What's missing or broken</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Checks on saved configuration for spacecraft on this mission.
              </p>
            </div>
            <.status_badge
              status={if @findings == [], do: :ready, else: :attention}
              label={if @findings == [], do: "No Findings", else: "#{length(@findings)} Findings"}
            />
          </div>

          <%= if @findings == [] do %>
            <div class="mt-6 rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
              <p class="hud-label mb-2 text-success">All clear</p>
              <p class="text-sm text-base-content/60 max-w-md mx-auto">
                The saved configuration looks consistent.
              </p>
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

  defp load_summary(%{current_scope: scope, current_mission: mission}) do
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    transports = Cadence.list_transports(scope.organization_id, mission.mission_id)
    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)
    routing_rules = Cadence.list_routing_rules(scope.organization_id, mission.mission_id)

    findings =
      CommsValidation.findings_for_resources(
        scope.organization_id,
        mission.mission_id,
        %{
          spacecraft: spacecraft,
          source_endpoints: source_endpoints,
          path_templates: path_templates,
          provider_profiles: provider_profiles,
          transport_profiles: transport_profiles,
          transports: transports,
          routing_rules: routing_rules
        }
      )

    %{
      transports: Enum.take(transports, 6),
      transport_count: length(transports),
      findings: findings,
      finding_groups: CommsValidation.finding_groups(findings)
    }
  end
end
