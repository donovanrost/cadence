defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias CadenceWeb.CommsValidation

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    findings = CommsValidation.findings_for_mission(scope, mission.mission_id)
    validation = validation_page_dto(mission, findings)

    {:ok,
     socket
     |> assign(:page_title, "Comms Validation")
     |> assign(:nav_item, :comms_validation)
     |> assign(:validation, validation)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-validation-component"
        v-component="CommsValidation"
        validation={@validation}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp validation_page_dto(mission, findings) do
    finding_count = length(findings)

    %{
      id: "comms-validation-page",
      title: "Validation",
      subtitle:
        "Actionable checks for saved Spacecraft, Transport, Routing, and advanced runtime compatibility setup.",
      breadcrumbs: [
        %{label: mission.display_name, href: ~p"/missions/#{mission.mission_id}"},
        %{label: "Comms", href: ~p"/missions/#{mission.mission_id}/comms"},
        %{label: "Validation", href: nil}
      ],
      finding_count_suffix: "#{finding_count} findings",
      status: validation_status_dto(finding_count),
      empty: findings == [],
      empty_state: %{
        id: "comms-validation-empty",
        title: "No setup findings",
        description: "The saved mission-management configuration looks consistent."
      },
      findings_id: "comms-validation-findings",
      finding_groups:
        findings
        |> CommsValidation.finding_groups()
        |> Enum.map(&finding_group_dto/1)
    }
  end

  defp validation_status_dto(0), do: status_dto(:ready, "No findings")

  defp validation_status_dto(finding_count),
    do: status_dto(:attention, "#{finding_count} findings")

  defp finding_group_dto(group) do
    %{
      id: group.id,
      title: group.title,
      description: group.description,
      findings: Enum.map(group.findings, &finding_dto/1)
    }
  end

  defp finding_dto(finding) do
    action_href = Map.get(finding, :action_navigate)

    %{
      id: Map.get(finding, :id),
      title: finding.title,
      body: finding.body,
      action_label: action_href && Map.get(finding, :action_label, "Review"),
      action_href: action_href,
      status: status_dto(finding.severity, CommsValidation.finding_label(finding.severity))
    }
  end

  defp status_dto(tone, label), do: %{tone: Atom.to_string(tone), label: label}
end
