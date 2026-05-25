defmodule CadenceWeb.CommsSourceEndpointListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)
    link_assignments = Cadence.list_link_assignments(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Runtime Identities")
     |> assign(:nav_item, :comms_runtime_identities)
     |> assign(:source_endpoints, source_endpoints)
     |> assign(:path_templates, path_templates)
     |> assign(:link_assignments, link_assignments)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-source-endpoints-page" class="space-y-6">
      <section class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Runtime Mapping</p>
              <h2 class="text-lg font-semibold">Runtime Identities</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Runtime identities map packet ingress into mission and spacecraft ownership.
                Provider network settings belong with mission providers, not here.
              </p>
            </div>
            <.status_badge
              status={if @source_endpoints == [], do: :blocked, else: :ready}
              label={if @source_endpoints == [], do: "None", else: "Configured"}
            />
          </div>
          <div class="mt-4">
            <.link
              id="new-source-endpoint-link"
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/comms/runtime-identities/new"
              }
              class="btn btn-primary btn-sm"
            >
              New Runtime Identity
            </.link>
          </div>

          <%= if @source_endpoints == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-identification"
                title="No runtime identities"
                description="Telemetry interpretation and link templates need runtime identities before operations can resolve packet ownership."
                action_label="New Runtime Identity"
                action_navigate={
                  ~p"/missions/#{@current_mission.mission_id}/comms/runtime-identities/new"
                }
              />
            </div>
          <% else %>
            <div class="mt-6 overflow-x-auto">
              <table id="source-endpoints-table" class="table">
                <thead>
                  <tr>
                    <th class="hud-label">Name</th>
                    <th class="hud-label">Runtime Identity ID</th>
                    <th class="hud-label">Spacecraft</th>
                    <th class="hud-label">SCID</th>
                    <th class="hud-label">Source Ref</th>
                    <th class="hud-label text-right">Link Assignments</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={endpoint <- @source_endpoints}>
                    <td class="font-medium">{endpoint.display_name || endpoint.source_endpoint_id}</td>
                    <td class="font-mono text-xs text-base-content/70">
                      {endpoint.source_endpoint_id}
                    </td>
                    <td class="font-mono text-xs">{endpoint.spacecraft_id || "Mission"}</td>
                    <td class="font-mono text-xs">{endpoint.scid || "Not set"}</td>
                    <td class="font-mono text-xs">{endpoint.source_ref || "Not set"}</td>
                    <td class="text-right font-mono text-sm">
                      {link_assignment_count(
                        endpoint.source_endpoint_id,
                        @link_assignments,
                        @path_templates
                      )}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </section>
    </div>
    """
  end

  defp link_assignment_count(source_endpoint_id, link_assignments, path_templates) do
    explicit_count = Enum.count(link_assignments, &(&1.source_endpoint_ref == source_endpoint_id))
    legacy_count = Enum.count(path_templates, &(&1.source_endpoint_ref == source_endpoint_id))

    explicit_count + legacy_count
  end
end
