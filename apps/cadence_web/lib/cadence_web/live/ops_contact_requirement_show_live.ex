defmodule CadenceWeb.OpsContactRequirementShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}

  @impl true
  def mount(%{"contact_requirement_id" => requirement_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:requirement_versions,
        dom_id: &"requirement-version-#{&1.contact_requirement_version_id}"
      )
      |> stream_configure(:planning_searches,
        dom_id: &"planning-search-#{&1.contact_planning_search_id}"
      )
      |> stream_configure(:opportunities,
        dom_id: &"planning-opportunity-#{&1.contact_opportunity_snapshot_id}"
      )
      |> assign(:page_title, "Contact Requirement")
      |> assign(:ops_nav_item, :requirements)
      |> assign(:contact_requirement_id, requirement_id)
      |> assign(:planning?, false)
      |> assign(:planning_error, nil)
      |> assign(:selected_snapshot_ids, MapSet.new())

    case load_requirement(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, _reason} -> {:ok, push_navigate(socket, to: requirements_path(socket))}
    end
  end

  @impl true
  def handle_event("plan", _params, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirement = socket.assigns.requirement

    {:noreply,
     socket
     |> assign(:planning?, true)
     |> assign(:planning_error, nil)
     |> assign_page_dto()
     |> start_async(:plan_contact_requirement, fn ->
       Planner.run(
         scope,
         mission.mission_id,
         requirement.contact_requirement_id,
         requirement.current_version
       )
     end)}
  end

  def handle_event("toggle-opportunity", %{"snapshot_id" => snapshot_id}, socket) do
    selected = socket.assigns.selected_snapshot_ids

    selected =
      if MapSet.member?(selected, snapshot_id),
        do: MapSet.delete(selected, snapshot_id),
        else: MapSet.put(selected, snapshot_id)

    {:noreply,
     socket
     |> assign(:selected_snapshot_ids, selected)
     |> assign_page_dto()
     |> stream(
       :opportunities,
       opportunity_rows(socket.assigns.opportunities, selected),
       reset: true
     )}
  end

  def handle_event("create-plan", _params, socket) do
    selected = socket.assigns.selected_snapshot_ids

    snapshots =
      Enum.filter(socket.assigns.opportunities, fn snapshot ->
        MapSet.member?(selected, snapshot.contact_opportunity_snapshot_id)
      end)

    run_ids = snapshots |> Enum.map(& &1.contact_planning_run_id) |> Enum.uniq()
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case ContactPlans.create(scope, mission.mission_id, %{
           planning_run_ids: run_ids,
           selected_snapshot_ids: Enum.map(snapshots, & &1.contact_opportunity_snapshot_id),
           rationale:
             "Operator-selected provider windows for #{socket.assigns.version.contact_intent}"
         }) do
      {:ok, plan, _version} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, plan_error(reason))}
    end
  end

  @impl true
  def handle_async(:plan_contact_requirement, {:ok, {:ok, _result}}, socket) do
    case load_requirement(assign(socket, :planning?, false)) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:planning_error, plan_error(reason))
         |> assign_page_dto()}
    end
  end

  def handle_async(:plan_contact_requirement, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> assign(:planning_error, plan_error(reason))
     |> assign_page_dto()}
  end

  def handle_async(:plan_contact_requirement, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> assign(
       :planning_error,
       "The planning worker stopped before provider evidence was complete."
     )
     |> assign_page_dto()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirement-show-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_requirement_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"contact_requirement_id" => @contact_requirement_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp load_requirement(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    requirement_id = socket.assigns.contact_requirement_id

    with {:ok, requirement, version} <-
           ContactRequirements.fetch(
             scope.organization_id,
             mission.mission_id,
             requirement_id
           ) do
      versions =
        ContactRequirements.list_versions(
          scope.organization_id,
          mission.mission_id,
          requirement_id
        )

      runs = Planner.list_runs(scope.organization_id, mission.mission_id, requirement_id)
      latest_run = List.first(runs)

      {searches, opportunities} =
        if latest_run do
          {
            Planner.list_searches(
              scope.organization_id,
              mission.mission_id,
              latest_run.contact_planning_run_id
            ),
            Planner.list_snapshots(
              scope.organization_id,
              mission.mission_id,
              latest_run.contact_planning_run_id
            )
          }
        else
          {[], []}
        end

      opportunity_ids = MapSet.new(opportunities, & &1.contact_opportunity_snapshot_id)

      selected =
        socket.assigns.selected_snapshot_ids
        |> MapSet.intersection(opportunity_ids)

      plans =
        ContactPlans.list(scope.organization_id, mission.mission_id)
        |> Enum.filter(fn {_plan, plan_version} ->
          Enum.any?(
            plan_version.requirement_refs_document["requirements"] || [],
            &(&1["id"] == requirement_id)
          )
        end)

      {:ok,
       socket
       |> assign(:requirement, requirement)
       |> assign(:version, version)
       |> assign(:latest_run, latest_run)
       |> assign(:opportunities, opportunities)
       |> assign(:selected_snapshot_ids, selected)
       |> assign(:plans, plans)
       |> assign_page_dto()
       |> stream(:requirement_versions, Enum.map(versions, &version_row_dto/1), reset: true)
       |> stream(:planning_searches, Enum.map(searches, &search_row_dto/1), reset: true)
       |> stream(:opportunities, opportunity_rows(opportunities, selected), reset: true)}
    end
  end

  defp assign_page_dto(socket) do
    assign(socket, :contact_requirement_show_page, page_dto(socket.assigns))
  end

  defp page_dto(assigns) do
    %{
      id: "ops-contact-requirement-show-page",
      back_action: %{
        label: "Requirements",
        href: requirements_path(assigns.current_mission.mission_id)
      },
      header: %{
        priority: to_string(assigns.version.priority),
        version_label: "Requirement v#{assigns.requirement.current_version}",
        intent: intent_label(assigns.version.contact_intent),
        outcome: outcome_sentence(assigns.version),
        plan_action: %{
          id: "plan-contact-requirement",
          event: "plan",
          payload: %{},
          label: if(assigns.planning?, do: "Querying providers", else: "Find options"),
          disabled: assigns.planning? or assigns.requirement.lifecycle_state != :active
        }
      },
      horizon: %{
        id: "requirement-horizon",
        fields: [
          %{
            label: "Earliest acceptable",
            value: format_time(assigns.version.earliest_start),
            class: "mt-1 font-mono text-sm tabular-nums"
          },
          %{
            label: "Latest acceptable",
            value: format_time(assigns.version.latest_end),
            class: "mt-1 font-mono text-sm tabular-nums"
          },
          %{
            label: "Spacecraft",
            value: assigns.version.spacecraft_id,
            class: "mt-1 truncate font-mono text-sm"
          }
        ],
        rationale: assigns.version.rationale
      },
      planning: %{
        heading: "Provider search evidence",
        description: "No availability and a failed search remain separate operational facts.",
        run_state: %{
          id: "planning-run-state",
          label:
            if(assigns.latest_run,
              do: humanize(assigns.latest_run.lifecycle_state),
              else: "not run"
            )
        },
        error: %{
          id: "contact-planning-error",
          message: assigns.planning_error
        },
        searches: %{
          id: "planning-searches",
          empty: %{
            id: "planning-searches-empty",
            message: "Run planning to query every provider-ready route."
          }
        }
      },
      opportunities: %{
        heading: "Opportunity comparison",
        description: "Choose exact immutable snapshots for a draft Plan.",
        selected_count: %{
          id: "selected-opportunity-count",
          label: "#{MapSet.size(assigns.selected_snapshot_ids)} selected"
        },
        list: %{
          id: "planning-opportunities",
          empty: %{
            id: "planning-opportunities-empty",
            message: "No provider opportunities were captured in the latest run."
          }
        },
        footer: "A draft records every considered option, including rejected alternatives.",
        create_action: %{
          id: "create-contact-plan",
          event: "create-plan",
          payload: %{},
          label: "Build draft Plan",
          disabled: MapSet.size(assigns.selected_snapshot_ids) == 0
        }
      },
      journey: %{
        heading: "Need → Options → Plan → Reserved",
        steps: [
          %{label: "Need", state: "Declared", complete: true},
          %{
            label: "Options",
            state:
              if(assigns.latest_run,
                do: humanize(assigns.latest_run.lifecycle_state),
                else: "Pending"
              ),
            complete: not is_nil(assigns.latest_run)
          },
          %{label: "Plan", state: plan_state(assigns.plans), complete: assigns.plans != []},
          %{
            label: "Reserved",
            state: reservation_state(assigns.plans),
            complete: reserved?(assigns.plans)
          }
        ]
      },
      versions: %{
        heading: "Immutable versions",
        id: "requirement-versions"
      }
    }
  end

  defp version_row_dto(version) do
    %{
      contact_requirement_version_id: version.contact_requirement_version_id,
      version_label: "v#{version.version}",
      created_at: format_time(version.created_at),
      rationale: version.rationale,
      content_sha256: version.content_sha256
    }
  end

  defp search_row_dto(search) do
    %{
      contact_planning_search_id: search.contact_planning_search_id,
      provider_label: search.provider_display_name || readiness_label(search),
      route_key: search.route_key,
      evidence: %{
        id: "planning-search-evidence-#{search.contact_planning_search_id}",
        summary: search_evidence_summary(search)
      },
      outcome: %{
        label: humanize(search.outcome),
        class: search_state_class(search.outcome)
      },
      opportunity_count: "#{search.opportunity_count} options"
    }
  end

  defp opportunity_rows(opportunities, selected_snapshot_ids) do
    Enum.map(opportunities, &opportunity_row_dto(&1, selected_snapshot_ids))
  end

  defp opportunity_row_dto(snapshot, selected_snapshot_ids) do
    snapshot_id = snapshot.contact_opportunity_snapshot_id

    %{
      contact_opportunity_snapshot_id: snapshot_id,
      provider_display_name: snapshot.route_binding_document["provider_display_name"],
      ground_station_ref: snapshot.normalized_opportunity_document["ground_station_ref"],
      starts_at: format_time(snapshot.starts_at),
      duration: "#{DateTime.diff(snapshot.ends_at, snapshot.starts_at)} sec",
      eligibility: %{
        label: eligibility_label(snapshot),
        class:
          if(snapshot.eligible,
            do: "mt-1 text-xs text-success",
            else: "mt-1 text-xs text-error"
          )
      },
      eligible: snapshot.eligible,
      selected: MapSet.member?(selected_snapshot_ids, snapshot_id),
      toggle_action: %{
        id: "toggle-#{snapshot_id}",
        event: "toggle-opportunity",
        payload: %{snapshot_id: snapshot_id},
        disabled: not snapshot.eligible,
        aria_label: "Toggle opportunity selection"
      }
    }
  end

  defp requirements_path(%Phoenix.LiveView.Socket{} = socket),
    do: requirements_path(socket.assigns.current_mission.mission_id)

  defp requirements_path(mission_id), do: ~p"/missions/#{mission_id}/ops/requirements"

  defp outcome_sentence(%{success_measure: :minimum_data_volume} = version),
    do:
      "Downlink at least #{version.minimum_data_volume_bytes} bytes across #{version.contact_count} eligible contact(s)."

  defp outcome_sentence(%{success_measure: :minimum_duration} = version),
    do: "Secure at least #{version.minimum_duration_seconds} seconds of contact time."

  defp outcome_sentence(%{success_measure: :contact_count} = version),
    do: "Secure #{version.contact_count} eligible contact window(s)."

  defp outcome_sentence(_version), do: "Any eligible provider contact satisfies this need."

  defp eligibility_label(%{eligible: true}), do: "Eligible"

  defp eligibility_label(snapshot) do
    snapshot.evaluation_document["hard_failures"]
    |> List.first()
    |> case do
      nil -> "Ineligible"
      failure -> humanize(failure["code"])
    end
  end

  defp readiness_label(search), do: search.readiness_document["message"] || "Route readiness"

  defp search_evidence_summary(search) do
    case search.readiness_document["orbit_readiness"] do
      %{"status" => status} = readiness ->
        orbit_summary(status, readiness)

      [%{"status" => status} = readiness | _rest] ->
        orbit_summary(status, readiness)

      _other ->
        search_outcome_summary(search)
    end
  end

  defp orbit_summary(status, readiness) do
    reference = readiness["ephemeris_ref"]
    valid_until = readiness["valid_until"]

    [
      "Provider orbit data #{humanize(status)}",
      if(reference, do: "reference #{reference}"),
      if(valid_until, do: "valid through #{format_evidence_time(valid_until)}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp search_outcome_summary(%{outcome: :succeeded_without_results}),
    do: "Provider evaluated this horizon and returned no matching availability."

  defp search_outcome_summary(%{outcome: :failed, error_document: error}),
    do: "Provider search failed: #{humanize(error["code"] || "provider_search_failed")}."

  defp search_outcome_summary(%{outcome: :not_ready}),
    do: "Provider or route readiness prevented opportunity evaluation."

  defp search_outcome_summary(%{outcome: :excluded_by_requirement}),
    do: "Requirement constraints excluded this route before provider search."

  defp search_outcome_summary(_search), do: "Provider search completed with durable evidence."

  defp format_evidence_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> format_time(datetime)
      _error -> value
    end
  end

  defp format_evidence_time(value), do: to_string(value)

  defp search_state_class(outcome)
       when outcome in [:succeeded_with_results, :succeeded_without_results],
       do: "font-mono text-[0.65rem] uppercase text-success"

  defp search_state_class(:excluded_by_requirement),
    do: "font-mono text-[0.65rem] uppercase text-base-content/45"

  defp search_state_class(_outcome), do: "font-mono text-[0.65rem] uppercase text-warning"

  defp plan_state([]), do: "Pending"
  defp plan_state([{plan, _version} | _rest]), do: humanize(plan.lifecycle_state)

  defp reservation_state(plans) do
    if reserved?(plans), do: "Capacity held", else: "Pending"
  end

  defp reserved?(plans),
    do:
      Enum.any?(plans, fn {plan, _version} ->
        plan.lifecycle_state in [:reserved, :partially_reserved]
      end)

  defp plan_error(:contact_planning_route_resolution_malformed),
    do: "Cadence could not resolve provider routes."

  defp plan_error(:contact_requirement_direction_not_executable),
    do: "Only downlink Requirements can be planned in this stage."

  defp plan_error({:contact_planning_route_resolution_failed, _detail}),
    do: "Provider route resolution failed. Review Comms readiness."

  defp plan_error(_reason), do: "Planning could not complete. Existing evidence was preserved."
  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %Y %H:%MZ")
  defp intent_label(intent), do: intent |> String.replace("_", " ") |> String.capitalize()
  defp humanize(item), do: item |> to_string() |> String.replace("_", " ")
end
