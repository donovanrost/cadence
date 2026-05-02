defmodule CadenceWeb.CommsOverviewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents
  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    summary = load_summary(socket.assigns)

    {:ok,
     socket
     |> assign(:page_title, "Comms")
     |> assign(:nav_item, :comms_overview)
     |> assign(Map.drop(summary, [:spacecraft_readiness]))
     |> stream(:spacecraft_readiness, summary.spacecraft_readiness)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="comms-overview-page" class="space-y-6">
      <.comms_header current_mission={@current_mission} active={:overview} />

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <.readiness_card
          title="Ready Spacecraft"
          value={@ready_spacecraft_count}
          status={if @ready_spacecraft_count == 0, do: :warning, else: :ready}
          description="Spacecraft with SCID, a runtime identity, and at least one downlink link template."
        />
        <.readiness_card
          title="Need SCID"
          value={@missing_scid_count}
          status={if @missing_scid_count == 0, do: :ready, else: :missing}
          description="Spacecraft that cannot be resolved from TM transfer-frame primary headers yet."
        />
        <.readiness_card
          title="Need Link"
          value={@missing_path_count}
          status={if @missing_path_count == 0, do: :ready, else: :warning}
          description="Spacecraft with identity configured but no provider-backed downlink link assignment."
        />
        <.readiness_card
          title="Advanced Objects"
          value={@advanced_object_count}
          status={if @advanced_object_count == 0, do: :warning, else: :info}
          description="Runtime identities, providers, protocol behaviors, and reusable link templates."
          navigate={~p"/missions/#{@current_mission.mission_id}/comms/advanced/runtime-identities"}
        />
      </div>

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

          <div class="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-6">
            <.network_resource_card
              id="mission-network-links"
              title="Links"
              value={@path_template_count}
              description="Create shared mission paths without editing raw objects."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/links/new"}
            />
            <.network_resource_card
              id="mission-network-providers"
              title="Providers"
              value={@provider_profile_count}
              description="External ground-side systems and adapters."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/providers"}
            />
            <.network_resource_card
              id="mission-network-protocol-behaviors"
              title="Protocol Behaviors"
              value={@transport_profile_count}
              description="Reusable path-local protocol behavior."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/protocol-behaviors"}
            />
            <.network_resource_card
              id="mission-network-link-templates"
              title="Link Templates"
              value={@path_template_count}
              description="Reusable uplink and downlink options."
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/link-templates"}
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

      <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <section class="card bg-base-200">
          <div class="card-body p-6">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="hud-label mb-2">Spacecraft Readiness</p>
                <h2 class="text-lg font-semibold">
                  Configure spacecraft identity, then assign mission-owned links
                </h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Each row shows whether a spacecraft can be identified from TM transfer frames
                  and use a configured downlink link template.
                </p>
              </div>
              <div class="flex flex-wrap items-center justify-end gap-2">
                <.link
                  id="configure-missing-links"
                  navigate={~p"/missions/#{@current_mission.mission_id}/comms/apply-link-template"}
                  class="btn btn-primary btn-sm"
                >
                  Apply Link Template
                </.link>
                <.status_badge status={if @setup_issue_count == 0, do: :ready, else: :warning} />
              </div>
            </div>

            <div
              id="spacecraft-readiness-section"
              class="mt-6 overflow-x-auto"
            >
              <div
                :if={@spacecraft_readiness_empty?}
                id="spacecraft-readiness-empty"
                class="rounded border border-base-300 bg-base-100/40 p-5 text-sm text-base-content/60"
              >
                No spacecraft have been registered for this mission yet.
                <.link
                  navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
                  class="text-primary hover:underline"
                >
                  Add the first spacecraft.
                </.link>
              </div>

              <table class="table">
                <thead>
                  <tr>
                    <th class="hud-label">Spacecraft</th>
                    <th class="hud-label">SCID</th>
                    <th class="hud-label">Runtime Identity</th>
                    <th class="hud-label">Downlink Link</th>
                    <th class="hud-label">Status</th>
                    <th class="hud-label text-right">Actions</th>
                  </tr>
                </thead>
                <tbody id="spacecraft-readiness-table" phx-update="stream">
                  <tr :for={{id, row} <- @streams.spacecraft_readiness} id={id}>
                    <td>
                      <div class="font-medium">{row.spacecraft.display_name}</div>
                      <div class="font-mono text-xs text-base-content/50">
                        {row.spacecraft.spacecraft_id}
                      </div>
                    </td>
                    <td class="font-mono text-sm text-base-content/70">
                      {format_scid(row.scid)}
                    </td>
                    <td>
                      <div class="text-sm">{row.endpoint_label}</div>
                      <div class="font-mono text-xs text-base-content/50">
                        {row.endpoint_ref || "Not created"}
                      </div>
                    </td>
                    <td>
                      <div class="text-sm">{row.path_label}</div>
                      <div class="text-xs text-base-content/50">{row.path_detail}</div>
                    </td>
                    <td>
                      <.status_badge status={row.status} label={row.status_label} />
                      <p class="mt-1 max-w-xs text-xs text-base-content/60">{row.issue}</p>
                    </td>
                    <td class="text-right">
                      <.action_menu>
                        <:action>
                          <.link navigate={
                            spacecraft_readiness_path(@current_mission.mission_id, row.spacecraft)
                          }>
                            {row.primary_action}
                          </.link>
                        </:action>
                        <:action>
                          <.link navigate={
                            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{row.spacecraft.spacecraft_id}"
                          }>
                            View spacecraft
                          </.link>
                        </:action>
                        <:action :if={row.endpoint_ref}>
                          <.link navigate={
                            spacecraft_links_path(@current_mission.mission_id, row.spacecraft)
                          }>
                            Link assignments
                          </.link>
                        </:action>
                      </.action_menu>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <aside class="card bg-base-200 border border-base-300">
          <div class="card-body p-5">
            <p class="hud-label mb-2">Setup Summary</p>
            <p class="text-3xl font-bold font-mono">{@setup_issue_count}</p>
            <p class="mt-2 text-sm text-base-content/60">
              spacecraft setup issue{if @setup_issue_count == 1, do: "", else: "s"}
              detected across identity and downlink link readiness.
            </p>
            <div class="mt-4 space-y-3 text-sm">
              <.summary_line label="Runtime identities" value={@source_endpoint_count} />
              <.summary_line label="Providers" value={@provider_profile_count} />
              <.summary_line label="Protocol behaviors" value={@transport_profile_count} />
              <.summary_line label="Link templates" value={@path_template_count} />
            </div>
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/comms/validation"}
              class="mt-4 btn btn-sm btn-primary"
            >
              Review validation
            </.link>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp summary_line(assigns) do
    ~H"""
    <div class="flex items-center justify-between border-b border-base-300 pb-2 last:border-b-0">
      <span class="text-base-content/60">{@label}</span>
      <span class="font-mono">{@value}</span>
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
    link_assignments = Cadence.list_link_assignments(scope.organization_id, mission.mission_id)

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

    spacecraft_readiness =
      SpacecraftCommsReadiness.readiness_rows(
        spacecraft,
        source_endpoints,
        path_templates,
        link_assignments
      )

    %{
      spacecraft_readiness: spacecraft_readiness,
      spacecraft_readiness_empty?: spacecraft_readiness == [],
      ready_spacecraft_count: Enum.count(spacecraft_readiness, &(&1.status == :ready)),
      missing_scid_count: Enum.count(spacecraft_readiness, &is_nil(&1.scid)),
      missing_path_count:
        Enum.count(spacecraft_readiness, &SpacecraftCommsReadiness.missing_path?/1),
      setup_issue_count: Enum.count(spacecraft_readiness, &(&1.status != :ready)),
      source_endpoint_count: length(source_endpoints),
      provider_profile_count: length(provider_profiles),
      transport_profile_count: length(transport_profiles),
      path_template_count: length(path_templates),
      advanced_object_count:
        length(source_endpoints) + length(provider_profiles) + length(transport_profiles) +
          length(path_templates) + length(link_assignments),
      finding_count: length(findings),
      blocking_findings: Enum.count(findings, &(&1.severity == :missing))
    }
  end

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)

  defp spacecraft_readiness_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
  end

  defp spacecraft_links_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
  end
end
