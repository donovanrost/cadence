defmodule CadenceWeb.CommsProtocolBehaviorListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Protocol Behaviors")
     |> assign(:nav_item, :comms)
     |> assign(:transport_profiles, transport_profiles)
     |> assign(:path_templates, path_templates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-protocol-behaviors-page" class="space-y-6">
      <section class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Path-Local Protocol Behavior</p>
              <h2 class="text-lg font-semibold">Protocol Behaviors</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Protocol behaviors configure reusable link-local behavior, such as uplink
                gateways or heartbeat monitors.
              </p>
            </div>
            <.status_badge
              status={if @transport_profiles == [], do: :attention, else: :ready}
              label={if @transport_profiles == [], do: "Not Started", else: "Configured"}
            />
          </div>
          <div class="mt-4">
            <.link
              id="new-protocol-behavior-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors/new"}
              class="btn btn-primary btn-sm"
            >
              New Protocol Behavior
            </.link>
          </div>

          <%= if @transport_profiles == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-cpu-chip"
                title="No protocol behaviors"
                description="Create protocol behaviors before attaching reusable behavior to uplink or downlink links."
                action_label="New Protocol Behavior"
                action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors/new"}
              />
            </div>
          <% else %>
            <div class="mt-6 overflow-x-auto">
              <table id="protocol-behaviors-table" class="table">
                <thead>
                  <tr>
                    <th class="hud-label">Name</th>
                    <th class="hud-label">Family</th>
                    <th class="hud-label">Scope</th>
                    <th class="hud-label">Behavior ID</th>
                    <th class="hud-label">Version</th>
                    <th class="hud-label text-right">Linked Templates</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={profile <- @transport_profiles}>
                    <td class="font-medium">
                      <.link
                        navigate={
                          ~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors/#{profile.transport_profile_id}"
                        }
                        class="text-primary hover:underline"
                      >
                        {display_name(profile, :transport_profile_id)}
                      </.link>
                    </td>
                    <td><.status_badge status={:info} label={human_atom(profile.family_key)} /></td>
                    <td class="text-sm">{human_atom(profile.target_scope)}</td>
                    <td class="font-mono text-xs text-base-content/70">
                      {profile.transport_profile_id}
                    </td>
                    <td class="font-mono text-sm">v{profile.version}</td>
                    <td class="text-right font-mono text-sm">
                      {linked_path_count(profile.transport_profile_id, @path_templates)}
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

  defp linked_path_count(transport_profile_id, path_templates) do
    Enum.count(path_templates, &(transport_profile_id in &1.transport_profile_ids))
  end
end
