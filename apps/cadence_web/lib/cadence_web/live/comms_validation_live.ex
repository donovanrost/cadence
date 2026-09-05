defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Applications.JSONBoundary
  alias CadenceWeb.CommsValidation

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    findings =
      case CommsValidation.findings_for_mission(scope, mission.mission_id) do
        {:ok, findings} -> findings
        {:error, _reason} -> [CommsValidation.unavailable_finding()]
      end

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
      v-component="FederatedFullPageSurface"
      application_key="comms"
      surface_id="validation"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
      />
    </Layouts.app>
    """
  end

  defp validation_page_dto(mission, findings) do
    finding_count = length(findings)

    dto = %{
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
      status: validation_status_dto(findings),
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

    case JSONBoundary.validate(dto) do
      :ok -> dto
      {:error, _reason} -> blocked_validation_page_dto()
    end
  end

  defp blocked_validation_page_dto do
    %{
      id: "comms-validation-page",
      title: "Validation unavailable",
      subtitle: "Cadence could not safely render the saved communications configuration.",
      breadcrumbs: [],
      finding_count_suffix: "0 findings",
      status: %{tone: "blocked", label: "Validation unavailable"},
      empty: true,
      empty_state: %{
        id: "comms-validation-empty",
        title: "Validation unavailable",
        description: "The saved configuration could not be safely evaluated."
      },
      findings_id: "comms-validation-findings",
      finding_groups: []
    }
  end

  defp validation_status_dto([]), do: status_dto(:ready, "No findings")

  defp validation_status_dto([%{id: "comms-validation-unavailable"}]),
    do: status_dto(:blocked, "Validation unavailable")

  defp validation_status_dto(findings),
    do: status_dto(:attention, "#{length(findings)} findings")

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

    base = %{
      id: Map.get(finding, :id),
      title: finding.title,
      body: finding.body,
      status: status_dto(finding.severity, CommsValidation.finding_label(finding.severity))
    }

    if is_binary(action_href),
      do:
        Map.merge(base, %{
          action_label: Map.get(finding, :action_label, "Review"),
          action_href: action_href
        }),
      else: base
  end

  defp status_dto(tone, label), do: %{tone: Atom.to_string(tone), label: label}
end
