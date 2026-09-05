defmodule CadenceWeb.OpsContactRequirementListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirements = ContactRequirements.list(scope.organization_id, mission.mission_id)
    plans = ContactPlans.list(scope.organization_id, mission.mission_id)

    rows =
      Enum.map(requirements, fn {requirement, version} ->
        runs =
          Planner.list_runs(
            scope.organization_id,
            mission.mission_id,
            requirement.contact_requirement_id
          )

        plan = plan_for_requirement(plans, requirement.contact_requirement_id)

        requirement_row_dto(
          %{
            requirement: requirement,
            version: version,
            latest_run: List.first(runs),
            plan: plan
          },
          mission.mission_id
        )
      end)

    {:ok,
     socket
     |> assign(:page_title, "Contact Requirements")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:contact_requirements_page, page_dto(mission.mission_id))
     |> stream_configure(:requirements, dom_id: &"contact-requirement-#{&1.id}")
     |> stream(:requirements, rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirements-component"
        v-component="FederatedFullPageSurface"
        page={@contact_requirements_page}
        requirements={@streams.requirements}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission_id) do
    %{
      id: "ops-contact-requirements-page",
      header: %{
        eyebrow: "Mission operations / planning horizon",
        title: "Contact Requirements",
        description:
          "Declare the mission outcome first. Cadence searches every ready provider route, preserves their evidence, and lets operators commit an exact plan.",
        create_action: %{
          id: "new-contact-requirement-link",
          label: "Declare need",
          href: ~p"/missions/#{mission_id}/ops/requirements/new"
        }
      },
      journey_steps: [
        %{number: "01", label: "Need", detail: "Mission outcome", active: true},
        %{number: "02", label: "Options", detail: "Provider evidence", active: false},
        %{number: "03", label: "Plan", detail: "Exact commitment", active: false},
        %{number: "04", label: "Reserved", detail: "Provider capacity", active: false}
      ],
      empty_state: %{
        id: "contact-requirements-empty",
        title: "No contact needs in this horizon",
        description:
          "Start with the outcome the spacecraft needs—data volume, duration, or contact count. Provider details come later."
      },
      list_id: "contact-requirements"
    }
  end

  defp requirement_row_dto(row, mission_id) do
    version = row.version
    requirement_id = row.requirement.contact_requirement_id

    %{
      id: requirement_id,
      priority: priority_dto(version.priority),
      version_direction: "v#{version.version} · #{version.service_direction}",
      intent_label: intent_label(version.contact_intent),
      outcome_detail: outcome_sentence(version),
      window: %{
        label: "Acceptable UTC window",
        detail: "#{short_time(version.earliest_start)} → #{short_time(version.latest_end)}"
      },
      journey: %{
        label: journey_state(row),
        detail: journey_detail(row)
      },
      detail_href: ~p"/missions/#{mission_id}/ops/requirements/#{requirement_id}"
    }
  end

  defp plan_for_requirement(plans, requirement_id) do
    Enum.find_value(plans, fn {plan, version} ->
      if Enum.any?(
           version.requirement_refs_document["requirements"] || [],
           &(&1["id"] == requirement_id)
         ),
         do: plan,
         else: nil
    end)
  end

  defp journey_state(%{plan: %{lifecycle_state: state}})
       when state in [:reserved, :partially_reserved],
       do: "Reserved"

  defp journey_state(%{plan: %{lifecycle_state: state}})
       when state in [:draft, :pending_approval, :approved, :executing, :failed],
       do: "Plan #{humanize(state)}"

  defp journey_state(%{latest_run: nil}), do: "Need declared"
  defp journey_state(_row), do: "Options captured"

  defp journey_detail(%{plan: %{lifecycle_state: state}}), do: humanize(state)
  defp journey_detail(%{latest_run: nil}), do: "Search not run"
  defp journey_detail(%{latest_run: run}), do: humanize(run.lifecycle_state)

  defp priority_dto(:critical) do
    %{
      label: "critical",
      tone: "error",
      class:
        "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"
    }
  end

  defp priority_dto(:high) do
    %{
      label: "high",
      tone: "warning",
      class:
        "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"
    }
  end

  defp priority_dto(priority) do
    %{
      label: to_string(priority),
      tone: "neutral",
      class:
        "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/55"
    }
  end

  defp outcome_sentence(%{success_measure: :minimum_data_volume} = version),
    do:
      "Deliver at least #{format_bytes(version.minimum_data_volume_bytes)} across #{version.contact_count} contact(s)."

  defp outcome_sentence(%{success_measure: :minimum_duration} = version),
    do: "Secure at least #{version.minimum_duration_seconds} seconds of contact time."

  defp outcome_sentence(%{success_measure: :contact_count} = version),
    do: "Secure #{version.contact_count} separated contact window(s)."

  defp outcome_sentence(_version), do: "Any eligible contact satisfies this need."

  defp format_bytes(bytes) when bytes >= 1_000_000_000,
    do: "#{Float.round(bytes / 1_000_000_000, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_bytes(bytes), do: "#{bytes} bytes"
  defp short_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")
  defp intent_label(intent), do: intent |> String.replace("_", " ") |> String.capitalize()
  defp humanize(item), do: item |> to_string() |> String.replace("_", " ")
end
