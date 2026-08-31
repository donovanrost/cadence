defmodule CadenceWeb.CommsOverviewPresenter do
  @moduledoc """
  Builds the JSON-safe presentation DTO shared by the Comms LiveView and the
  federated application-host query.
  """

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.Scope
  alias Cadence.Ids
  alias Cadence.Missions.Mission
  alias Cadence.Reads.ApplicationSurfaces.Comms, as: CommsRead

  @spec build(Scope.t(), Mission.t()) :: map()
  def build(%Scope{} = current_scope, %Mission{} = mission) do
    case CommsRead.overview(current_scope, mission.mission_id) do
      {:ok, summary} -> presentation(mission, summary)
      {:error, _reason} -> presentation(mission, unavailable_summary())
    end
  end

  @spec presentation(Mission.t(), map()) :: map()
  def presentation(%Mission{} = mission, summary) when is_map(summary) do
    dto = presentation_dto(mission, summary)

    case JSONBoundary.validate(dto) do
      :ok -> dto
      {:error, _reason} -> fallback_presentation(mission)
    end
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp unavailable_summary do
    finding = %{
      id: "comms-validation-unavailable",
      owner: :advanced_runtime_identity,
      severity: :blocked,
      title: "Validation unavailable",
      body: "Cadence could not safely evaluate the saved communications configuration."
    }

    %{
      transports: [],
      transport_count: 0,
      findings: [finding],
      finding_groups: CommsRead.finding_groups([finding])
    }
  end

  defp fallback_presentation(%Mission{} = mission) do
    fallback_mission = %{
      mission
      | mission_id: bounded_mission_id(mission.mission_id),
        display_name: bounded_display_name(mission.display_name)
    }

    dto = presentation_dto(fallback_mission, unavailable_summary())

    case JSONBoundary.validate(dto) do
      :ok ->
        dto

      {:error, _reason} ->
        presentation_dto(
          %{mission | mission_id: "unavailable", display_name: "Mission unavailable"},
          unavailable_summary()
        )
    end
  end

  defp presentation_dto(%Mission{} = mission, summary) do
    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "space-y-6",
            "id" => "comms-overview-page"
          })
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        "body" => %{"attrs" => presentation_attrs(%{"class" => false})},
        "content" => %{"attrs" => presentation_attrs(%{})},
        "eyebrow" => %{
          "attrs" => presentation_attrs(%{"class" => "hud-label"}),
          "text" => "Communications"
        },
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => mission.display_name
        },
        "title_suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "· Mission Comms"
        }
      },
      "overview" => overview_dto(mission.mission_id, summary)
    }
  end

  defp bounded_display_name(value)
       when is_binary(value) and byte_size(value) <= 240 and value != "" do
    if String.valid?(value), do: value, else: "Mission unavailable"
  end

  defp bounded_display_name(_value), do: "Mission unavailable"

  defp bounded_mission_id(value) when is_binary(value) and byte_size(value) <= 240 do
    case Ids.path_segment(value) do
      {:ok, mission_id} -> mission_id
      {:error, :invalid_identifier} -> "unavailable"
    end
  end

  defp bounded_mission_id(_value), do: "unavailable"

  defp overview_dto(mission_id, summary) do
    %{
      transport: transport_summary_dto(mission_id, summary),
      validation: validation_summary_dto(summary)
    }
  end

  defp transport_summary_dto(mission_id, summary) do
    count = summary.transport_count

    %{
      id: "comms-transports",
      eyebrow: "Transport",
      count: count,
      count_label: if(count == 1, do: "transport configured", else: "transports configured"),
      description:
        "Transports describe durable capabilities for moving bytes. Routing rules will decide how spacecraft use those capabilities.",
      status: transport_status_dto(count),
      empty: summary.transports == [],
      empty_state: %{
        title: "No transports configured",
        description: "Add a transport to describe a byte-moving capability for this mission.",
        action_label: "Add a transport",
        action_href: ~p"/missions/#{mission_id}/comms/transports/new"
      },
      rows: Enum.map(summary.transports, &transport_dto(&1, mission_id)),
      manage_label: "Manage transports →",
      manage_href: ~p"/missions/#{mission_id}/comms/transports",
      add_label: "+ Add a transport",
      add_href: ~p"/missions/#{mission_id}/comms/transports/new"
    }
  end

  defp transport_status_dto(0), do: status_dto(:attention, "Needs Work")
  defp transport_status_dto(_count), do: status_dto(:ready, "Ready")

  defp transport_dto(transport, mission_id) do
    %{
      id: "comms-transport-#{transport.transport_id}",
      display_name: transport.display_name,
      metadata:
        "#{transport.transport_kind} · #{transport.direction_capability} · v#{transport.version}",
      href: ~p"/missions/#{mission_id}/comms/transports/#{transport.transport_id}"
    }
  end

  defp validation_summary_dto(summary) do
    unavailable? =
      Enum.any?(summary.findings, &(Map.get(&1, :id) == "comms-validation-unavailable"))

    %{
      id: "comms-validation-page",
      eyebrow: "Setup Checks",
      title: "What's missing or broken",
      description: "Checks on saved configuration for spacecraft on this mission.",
      status: validation_status_dto(summary.findings),
      empty: summary.findings == [],
      empty_state: %{
        title: if(unavailable?, do: "Validation unavailable", else: "All clear"),
        description:
          if(unavailable?,
            do: "Cadence could not safely evaluate the saved configuration.",
            else: "The saved configuration looks consistent."
          )
      },
      findings_id: "comms-validation-findings",
      finding_groups: Enum.map(summary.finding_groups, &finding_group_dto/1)
    }
  end

  defp validation_status_dto([]), do: status_dto(:ready, "No Findings")

  defp validation_status_dto([%{id: "comms-validation-unavailable"}]),
    do: status_dto(:blocked, "Validation unavailable")

  defp validation_status_dto(findings),
    do: status_dto(:attention, "#{length(findings)} Findings")

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
      status: status_dto(finding.severity, CommsRead.finding_label(finding.severity))
    }

    if is_binary(action_href),
      do:
        Map.merge(base, %{
          action_label: Map.get(finding, :action_label, "Review"),
          action_href: action_href
        }),
      else: base
  end

  defp status_dto(tone, label) do
    %{tone: Atom.to_string(tone), label: label}
  end
end
