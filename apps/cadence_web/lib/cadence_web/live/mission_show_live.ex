defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.CommsComponents, only: [readiness_card: 1]

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
      <.page_header
        eyebrow="Mission"
        title={@current_mission.display_name}
        subtitle={@current_mission.slug}
      />

      <div class="grid gap-4 md:grid-cols-3">
        <.readiness_card
          title="Ready Spacecraft"
          value={@ready_spacecraft_count}
          status={if @ready_spacecraft_count == 0, do: :attention, else: :ready}
          description="Spacecraft with SCID and identity configured."
        />
        <.readiness_card
          title="Need SCID"
          value={@missing_scid_count}
          status={if @missing_scid_count == 0, do: :ready, else: :blocked}
          description="Spacecraft that cannot be resolved from incoming frames yet."
        />
        <.readiness_card
          title="Need Link"
          value={@missing_path_count}
          status={if @missing_path_count == 0, do: :ready, else: :attention}
          description="Spacecraft with identity configured but no provider link."
        />
      </div>

      <.readiness_panel
        setup_issue_count={@setup_issue_count}
        empty?={@spacecraft_readiness_empty?}
        mission_id={@current_mission.mission_id}
        rows={@streams.spacecraft_readiness}
      />
    </div>
    """
  end

  attr :setup_issue_count, :integer, required: true
  attr :empty?, :boolean, required: true
  attr :mission_id, :string, required: true
  attr :rows, :any, required: true

  defp readiness_panel(assigns) do
    ~H"""
    <.card>
      <.section_header
        eyebrow="Spacecraft Readiness"
        title="Configure spacecraft identity and select a spacecraft profile"
        description="Each row shows whether a spacecraft can be identified from incoming frames and has a profile that defines its byte-interpretation contract."
      >
        <:actions>
          <.status_badge status={if @setup_issue_count == 0, do: :ready, else: :attention} />
        </:actions>
      </.section_header>

      <div id="spacecraft-readiness-section" class="mt-6 overflow-x-auto">
        <div :if={@empty?} id="spacecraft-readiness-empty">
          <.empty_state
            title="No spacecraft have been registered for this mission yet."
            action_label="Add the first spacecraft"
            action_navigate={~p"/missions/#{@mission_id}/spacecraft/new"}
          />
        </div>

        <.readiness_table :if={not @empty?} mission_id={@mission_id} rows={@rows} />
      </div>
    </.card>
    """
  end

  attr :mission_id, :string, required: true
  attr :rows, :any, required: true

  defp readiness_table(assigns) do
    ~H"""
    <.table id="mission-spacecraft-readiness" body_id="spacecraft-readiness-table" rows={@rows}>
      <:col :let={row} label="Spacecraft">
        <div class="font-medium">{row.spacecraft.display_name}</div>
        <div class="font-mono text-xs text-base-content/60">
          {row.spacecraft.spacecraft_id}
        </div>
      </:col>
      <:col :let={row} label="SCID" mono class="text-primary/80">
        {format_scid(row.scid)}
      </:col>
      <:col :let={row} label="Runtime Identity">
        <div class="text-sm">{row.endpoint_label}</div>
        <div class="font-mono text-xs text-base-content/60">
          {row.endpoint_ref || "Not created"}
        </div>
      </:col>
      <:col :let={row} label="Downlink Link">
        <div class="text-sm">{row.path_label}</div>
        <div class="text-xs text-base-content/60">{row.path_detail}</div>
      </:col>
      <:col :let={row} label="Status">
        <.status_badge status={row.status} label={row.status_label} />
        <p class="mt-1 max-w-xs text-xs text-base-content/70">{row.issue}</p>
      </:col>
      <:col :let={row} label="Actions" align={:right}>
        <.action_menu id={"#{row.spacecraft.spacecraft_id}-readiness-actions"}>
          <:action>
            <.link navigate={spacecraft_readiness_path(@mission_id, row.spacecraft)}>
              {row.primary_action}
            </.link>
          </:action>
          <:action>
            <.link navigate={
              ~p"/missions/#{@mission_id}/spacecraft/#{row.spacecraft.spacecraft_id}"
            }>
              View spacecraft
            </.link>
          </:action>
        </.action_menu>
      </:col>
    </.table>
    """
  end

  defp load_summary(%{current_scope: scope, current_mission: mission}) do
    spacecraft =
      Cadence.SpacecraftStore.list_spacecraft(scope.organization_id, mission.mission_id)

    source_endpoints =
      Cadence.SourceEndpoints.list_source_endpoints(scope.organization_id, mission.mission_id)

    path_templates =
      Cadence.Contacts.list_path_templates(scope.organization_id, mission.mission_id)

    link_assignments =
      Cadence.Contacts.list_link_assignments(scope.organization_id, mission.mission_id)

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
end
