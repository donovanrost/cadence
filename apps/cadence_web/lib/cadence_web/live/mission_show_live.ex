defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.SpacecraftCommsReadiness

  @impl true
  def mount(_params, _session, socket) do
    summary = load_summary(socket.assigns)
    overview = mission_overview_dto(socket.assigns.current_mission, summary)

    {:ok,
     socket
     |> assign(:page_title, socket.assigns.current_mission.display_name)
     |> assign(:nav_item, :mission_overview)
     |> assign(:mission_overview, Map.drop(overview, [:spacecraft_readiness]))
     |> stream(:spacecraft_readiness, overview.spacecraft_readiness)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="mission-overview-page" class="space-y-6">
        <.vue
          id="mission-overview-component"
          v-component="FederatedFullPageSurface"
          overview={@mission_overview}
          spacecraft_readiness={@streams.spacecraft_readiness}
          v-ssr={false}
          class="space-y-6"
        />
      </div>
    </Layouts.app>
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

  defp mission_overview_dto(mission, summary) do
    %{
      mission: %{
        eyebrow: "Mission",
        display_name: mission.display_name,
        slug: mission.slug
      },
      readiness_cards: [
        readiness_card_dto(
          "Ready Spacecraft",
          summary.ready_spacecraft_count,
          if(summary.ready_spacecraft_count == 0, do: :attention, else: :ready),
          "Spacecraft with SCID and identity configured."
        ),
        readiness_card_dto(
          "Need SCID",
          summary.missing_scid_count,
          if(summary.missing_scid_count == 0, do: :ready, else: :blocked),
          "Spacecraft that cannot be resolved from incoming frames yet."
        ),
        readiness_card_dto(
          "Need Link",
          summary.missing_path_count,
          if(summary.missing_path_count == 0, do: :ready, else: :attention),
          "Spacecraft with identity configured but no provider link."
        )
      ],
      setup: %{
        eyebrow: "Spacecraft Readiness",
        title: "Configure spacecraft identity and select a spacecraft profile",
        description:
          "Each row shows whether a spacecraft can be identified from incoming frames and has a profile that defines its byte-interpretation contract.",
        issue_count: summary.setup_issue_count,
        status: status_dto(if(summary.setup_issue_count == 0, do: :ready, else: :attention)),
        empty: summary.spacecraft_readiness_empty?,
        empty_state: %{
          title: "No spacecraft have been registered for this mission yet.",
          action_label: "Add the first spacecraft",
          action_href: ~p"/missions/#{mission.mission_id}/spacecraft/new"
        }
      },
      spacecraft_readiness:
        Enum.map(summary.spacecraft_readiness, &readiness_row_dto(mission.mission_id, &1))
    }
  end

  defp readiness_card_dto(title, value, status, description) do
    %{
      title: title,
      value: value,
      status: status_dto(status),
      description: description
    }
  end

  defp readiness_row_dto(mission_id, row) do
    spacecraft = row.spacecraft

    %{
      id: spacecraft.spacecraft_id,
      actions_id: "#{spacecraft.spacecraft_id}-readiness-actions",
      spacecraft_display_name: spacecraft.display_name,
      spacecraft_id: spacecraft.spacecraft_id,
      scid_label: format_scid(row.scid),
      endpoint_label: row.endpoint_label,
      endpoint_ref_label: row.endpoint_ref || "Not created",
      path_label: row.path_label,
      path_detail: row.path_detail,
      status: Atom.to_string(row.status),
      status_label: row.status_label,
      issue: row.issue,
      primary_action: row.primary_action,
      primary_action_href: spacecraft_readiness_path(mission_id, spacecraft),
      view_spacecraft_href: ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
    }
  end

  defp status_dto(status) do
    %{tone: Atom.to_string(status), label: status_label(status)}
  end

  defp status_label(:ready), do: "Ready"
  defp status_label(:attention), do: "Needs Work"
  defp status_label(:blocked), do: "Missing"

  defp format_scid(nil), do: "Not set"
  defp format_scid(scid), do: Integer.to_string(scid)

  defp spacecraft_readiness_path(mission_id, spacecraft) do
    ~p"/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
  end
end
