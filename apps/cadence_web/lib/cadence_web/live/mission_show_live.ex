defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [readiness_card: 1, status_badge: 1]

  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    summary = load_summary(socket.assigns)

    {:ok,
     socket
     |> assign(:page_title, socket.assigns.current_mission.display_name)
     |> assign(:nav_item, :mission_overview)
     |> assign(Map.drop(summary, [:spacecraft_readiness]))
     |> stream(:spacecraft_readiness, summary.spacecraft_readiness)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="mission-overview-page" class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@current_mission.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@current_mission.slug}</p>
      </div>

      <div class="grid gap-4 md:grid-cols-3">
        <.readiness_card
          title="Ready Spacecraft"
          value={@ready_spacecraft_count}
          status={if @ready_spacecraft_count == 0, do: :attention, else: :ready}
          description="Spacecraft with SCID, a runtime identity, and at least one downlink link template."
        />
        <.readiness_card
          title="Need SCID"
          value={@missing_scid_count}
          status={if @missing_scid_count == 0, do: :ready, else: :blocked}
          description="Spacecraft that cannot be resolved from TM transfer-frame primary headers yet."
        />
        <.readiness_card
          title="Need Link"
          value={@missing_path_count}
          status={if @missing_path_count == 0, do: :ready, else: :attention}
          description="Spacecraft with identity configured but no provider-backed downlink link assignment."
        />
      </div>

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
              <.status_badge status={if @setup_issue_count == 0, do: :ready, else: :attention} />
            </div>
          </div>

          <div id="spacecraft-readiness-section" class="mt-6 overflow-x-auto">
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

            <table :if={not @spacecraft_readiness_empty?} class="table">
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
    </div>
    """
  end

  defp load_summary(%{current_scope: scope, current_mission: mission}) do
    spacecraft = Cadence.list_spacecraft(scope.organization_id, mission.mission_id)
    source_endpoints = Cadence.list_source_endpoints(scope.organization_id, mission.mission_id)
    path_templates = Cadence.list_path_templates(scope.organization_id, mission.mission_id)
    link_assignments = Cadence.list_link_assignments(scope.organization_id, mission.mission_id)

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
      setup_issue_count: Enum.count(spacecraft_readiness, &(&1.status != :ready))
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
