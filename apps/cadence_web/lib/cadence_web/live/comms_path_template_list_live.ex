defmodule CadenceWeb.CommsPathTemplateListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    provider_profiles = Cadence.list_provider_profiles(scope.organization_id, mission.mission_id)

    transport_profiles =
      Cadence.list_transport_profiles(scope.organization_id, mission.mission_id)

    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Link Templates")
     |> assign(:nav_item, :comms_link_templates)
     |> assign(:source_endpoints_by_id, Map.new(source_endpoints, &{&1.source_endpoint_id, &1}))
     |> assign(
       :provider_profiles_by_id,
       Map.new(provider_profiles, &{&1.provider_profile_id, &1})
     )
     |> assign(
       :transport_profiles_by_id,
       Map.new(transport_profiles, &{&1.transport_profile_id, &1})
     )
     |> assign(:path_templates, path_templates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-path-templates-page" class="space-y-6">
      <section class="card bg-base-200">
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label mb-2">Reusable Mission Links</p>
              <h2 class="text-lg font-semibold">Link Templates</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Link templates define reusable uplink and downlink options backed by mission
                providers and protocol behavior versions. Spacecraft use them through
                explicit link assignments.
              </p>
            </div>
            <.status_badge
              status={if @path_templates == [], do: :missing, else: :ready}
              label={if @path_templates == [], do: "None", else: "Configured"}
            />
          </div>
          <div class="mt-4">
            <.link
              id="new-shared-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/links/new"}
              class="btn btn-primary btn-sm"
            >
              New Shared Link
            </.link>
            <.link
              id="new-path-template-link"
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates/new"}
              class="btn btn-ghost btn-sm"
            >
              Advanced Template
            </.link>
          </div>

          <%= if @path_templates == [] do %>
            <div class="mt-6">
              <.empty_state
                icon="hero-arrows-right-left"
                title="No link templates"
                description="Create link templates to define the uplink and downlink options that scheduled contacts can use."
                action_label="New Shared Link"
                action_navigate={~p"/missions/#{@current_mission.mission_id}/comms/links/new"}
              />
            </div>
          <% else %>
            <div class="mt-6 overflow-x-auto">
              <table id="path-templates-table" class="table">
                <thead>
                  <tr>
                    <th class="hud-label">Name</th>
                    <th class="hud-label">Direction</th>
                    <th class="hud-label">Role</th>
                    <th class="hud-label">Scope</th>
                    <th class="hud-label">Providers</th>
                    <th class="hud-label">Protocol Behaviors</th>
                    <th class="hud-label">Version</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={template <- @path_templates}>
                    <td>
                      <.link
                        navigate={
                          ~p"/missions/#{@current_mission.mission_id}/comms/link-templates/#{template.path_template_id}"
                        }
                        class="font-medium text-primary hover:underline"
                      >
                        {display_name(template, :path_id)}
                      </.link>
                      <div class="font-mono text-xs text-base-content/50">
                        {template.path_template_id}
                      </div>
                    </td>
                    <td><.status_badge status={:info} label={human_atom(template.direction)} /></td>
                    <td class="text-sm">{human_atom(template.selection_role)}</td>
                    <td class="text-sm">
                      {source_endpoint_label(template.source_endpoint_ref, @source_endpoints_by_id)}
                    </td>
                    <td class="font-mono text-xs">
                      <%= if template.provider_profile_refs == [] do %>
                        <span class="text-base-content/40">None</span>
                      <% else %>
                        <div :for={ref <- template.provider_profile_refs}>
                          {profile_ref_display_label(
                            ref,
                            "provider_profile_id",
                            @provider_profiles_by_id,
                            :provider_profile_id
                          )}
                        </div>
                      <% end %>
                    </td>
                    <td class="font-mono text-xs">
                      <%= if template.transport_profile_refs == [] do %>
                        <span class="text-base-content/40">None</span>
                      <% else %>
                        <div :for={ref <- template.transport_profile_refs}>
                          {profile_ref_display_label(
                            ref,
                            "transport_profile_id",
                            @transport_profiles_by_id,
                            :transport_profile_id
                          )}
                        </div>
                      <% end %>
                    </td>
                    <td class="font-mono text-sm">v{template.version}</td>
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

  defp source_endpoint_label(nil, _source_endpoints_by_id), do: "Reusable template"

  defp source_endpoint_label(source_endpoint_ref, source_endpoints_by_id) do
    case Map.fetch(source_endpoints_by_id, source_endpoint_ref) do
      {:ok, endpoint} ->
        "Legacy direct identity: #{endpoint.display_name || endpoint.source_endpoint_id}"

      :error ->
        "Legacy direct identity: #{source_endpoint_ref} (missing)"
    end
  end
end
