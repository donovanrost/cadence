defmodule CadenceWeb.OpsFleetPlanningRunLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    FleetAutomationActions,
    FleetPlanner,
    FleetPlanningRuns,
    FleetRepairs,
    Planner
  }

  @phases [:queued, :materializing, :searching, :optimizing, :materializing_plan, :finished]

  @impl true
  def mount(%{"fleet_planning_run_id" => run_id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Fleet Planning Run")
      |> assign(:ops_nav_item, :planning)
      |> assign(:fleet_planning_run_id, run_id)
      |> assign(:planning?, false)
      |> stream_configure(:requirement_rows, dom_id: & &1.__dom_id)
      |> stream_configure(:exceptions, dom_id: & &1.__dom_id)
      |> stream_configure(:decisions, dom_id: & &1.__dom_id)
      |> stream_configure(:horizon_commitments, dom_id: & &1.__dom_id)
      |> stream_configure(:resource_pressure, dom_id: & &1.__dom_id)
      |> stream_configure(:automation_actions, dom_id: & &1.__dom_id)

    case load_run(socket) do
      {:ok, socket} ->
        socket = maybe_resume(socket)
        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         push_navigate(socket,
           to: ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/planning"
         )}
    end
  end

  @impl true
  def handle_event("refresh-fleet-run", %{}, socket) do
    case load_run(socket) do
      {:ok, socket} -> {:noreply, maybe_resume(socket)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("repair-fleet-run", %{"repair" => params}, socket) do
    %{current_scope: scope, current_mission: mission, run: run, plan: plan} = socket.assigns

    with %{} <- plan,
         {:ok, horizon_start} <- parse_datetime(params["horizon_start"]),
         {:ok, horizon_end} <- parse_datetime(params["horizon_end"]),
         {:ok, repair_run, _refs} <-
           FleetRepairs.start(
             scope,
             mission.mission_id,
             run.fleet_planning_run_id,
             plan.contact_plan_id,
             run.candidate_contact_plan_version,
             %{horizon_start: horizon_start, horizon_end: horizon_end}
           ) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{repair_run.fleet_planning_run_id}"
       )}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
      _missing_plan -> {:noreply, put_flash(socket, :error, "No repairable Plan is linked.")}
    end
  end

  @impl true
  def handle_async(:run_fleet_planning, {:ok, {:ok, _result}}, socket) do
    case load_run(assign(socket, :planning?, false)) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_async(:run_fleet_planning, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> put_flash(:error, action_error(reason))}
  end

  def handle_async(:run_fleet_planning, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:planning?, false)
     |> put_flash(
       :error,
       "The worker stopped. Durable run checkpoints were retained and can be resumed."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-fleet-planning-run-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="fleet_planning_run"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"fleet_planning_run_id" => @fleet_planning_run_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp load_run(socket) do
    %{current_scope: scope, current_mission: mission, fleet_planning_run_id: run_id} =
      socket.assigns

    with {:ok, run} <-
           FleetPlanningRuns.fetch(scope.organization_id, mission.mission_id, run_id) do
      refs =
        FleetPlanningRuns.list_requirement_refs(
          scope.organization_id,
          mission.mission_id,
          run_id
        )

      decisions =
        FleetPlanningRuns.list_decisions(
          scope.organization_id,
          mission.mission_id,
          run_id
        )

      snapshots =
        refs
        |> Enum.map(& &1.contact_planning_run_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.flat_map(&Planner.list_snapshots(scope.organization_id, mission.mission_id, &1))

      {plan, plan_version, snapshots} =
        candidate_plan(scope.organization_id, mission.mission_id, run, snapshots)

      snapshot_by_id = Map.new(snapshots, &{&1.contact_opportunity_snapshot_id, &1})

      requirement_items =
        Enum.map(refs, fn ref ->
          {:ok, version} =
            ContactRequirements.fetch_version(
              scope.organization_id,
              mission.mission_id,
              ref.contact_requirement_id,
              ref.contact_requirement_version
            )

          %{ref: ref, version: version}
        end)

      decision_items =
        Enum.map(decisions, fn decision ->
          %{
            decision: decision,
            snapshot: snapshot_by_id[decision.contact_opportunity_snapshot_id]
          }
        end)

      commitments =
        Enum.filter(decision_items, fn item ->
          item.decision.disposition in [:selected, :locked] and item.snapshot
        end)

      exceptions =
        Enum.filter(
          requirement_items,
          &(&1.ref.result_state in [:partial, :unsatisfied, :failed])
        )

      pressures = resource_pressure(run)

      actions =
        FleetAutomationActions.list(scope.organization_id, mission.mission_id, run_id)

      repair_form = repair_form(run)

      {:ok,
       socket
       |> assign(:run, run)
       |> assign(:phases, @phases)
       |> assign(:plan, plan)
       |> assign(:plan_version, plan_version)
       |> assign(:repairable?, repairable?(plan))
       |> assign(:repair_form, repair_form)
       |> assign(:decision_count, length(decision_items))
       |> assign(
         :commitment_count,
         Enum.count(commitments, &(&1.decision.disposition == :selected))
       )
       |> assign(:locked_count, Enum.count(commitments, &(&1.decision.disposition == :locked)))
       |> assign(:exception_count, length(exceptions))
       |> assign(:automation_action_count, length(actions))
       |> stream(
         :requirement_rows,
         Enum.map(requirement_items, &requirement_row_dto(&1, mission.mission_id)),
         reset: true
       )
       |> stream(:exceptions, Enum.map(exceptions, &exception_dto/1), reset: true)
       |> stream(:decisions, Enum.map(decision_items, &decision_dto/1), reset: true)
       |> stream(
         :horizon_commitments,
         Enum.map(commitments, &commitment_dto/1),
         reset: true
       )
       |> stream(:resource_pressure, pressures, reset: true)
       |> stream(:automation_actions, Enum.map(actions, &automation_action_dto/1), reset: true)}
    end
  end

  defp requirement_row_dto(%{ref: ref, version: version}, mission_id) do
    %{
      id: ref.contact_requirement_id,
      __dom_id: "fleet-requirement-#{ref.contact_requirement_id}",
      spacecraft_id: version.spacecraft_id,
      contact_requirement_id: ref.contact_requirement_id,
      contact_requirement_version: ref.contact_requirement_version,
      requirement_href:
        ~p"/missions/#{mission_id}/ops/requirements/#{ref.contact_requirement_id}",
      input: result_dto(ref.input_state),
      coverage: result_dto(ref.result_state),
      contact_planning_run_id: ref.contact_planning_run_id || "not searched"
    }
  end

  defp exception_dto(%{ref: ref}) do
    %{
      id: ref.contact_requirement_id,
      __dom_id: "fleet-exception-#{ref.contact_requirement_id}",
      contact_requirement_id: ref.contact_requirement_id,
      result: %{state: Atom.to_string(ref.result_state), label: humanize(ref.result_state)}
    }
  end

  defp decision_dto(%{decision: decision} = item) do
    %{
      id: decision.fleet_planning_decision_id,
      __dom_id: "fleet-decision-#{decision.fleet_planning_decision_id}",
      fleet_planning_decision_id: decision.fleet_planning_decision_id,
      disposition: %{
        state: Atom.to_string(decision.disposition),
        label: humanize(decision.disposition),
        class: decision_class(decision.disposition)
      },
      title: decision_title(item),
      contact_opportunity_snapshot_id: decision.contact_opportunity_snapshot_id,
      score: decision.score,
      operational_rationale: decision.explanation_document["message"],
      hard_constraints: hard_constraint_label(decision)
    }
  end

  defp commitment_dto(%{decision: decision, snapshot: snapshot}) do
    %{
      id: decision.fleet_planning_decision_id,
      __dom_id: "fleet-commitment-#{decision.fleet_planning_decision_id}",
      fleet_planning_decision_id: decision.fleet_planning_decision_id,
      spacecraft_id: snapshot.route_binding_document["spacecraft_id"],
      starts_at: format_time(snapshot.starts_at),
      duration_seconds: duration(snapshot),
      disposition: Atom.to_string(decision.disposition)
    }
  end

  defp automation_action_dto(action) do
    %{
      id: action.fleet_automation_action_id,
      __dom_id: "fleet-action-#{action.fleet_automation_action_id}",
      fleet_automation_action_id: action.fleet_automation_action_id,
      action: Atom.to_string(action.action),
      lifecycle: %{
        state: Atom.to_string(action.lifecycle_state),
        label: humanize(action.lifecycle_state),
        class: result_class(action.lifecycle_state)
      }
    }
  end

  defp result_dto(state) do
    %{state: Atom.to_string(state), label: humanize(state), class: result_class(state)}
  end

  defp maybe_resume(%{assigns: %{run: %{phase: :finished}}} = socket), do: socket
  defp maybe_resume(%{assigns: %{planning?: true}} = socket), do: socket

  defp maybe_resume(socket) do
    if connected?(socket) do
      %{current_scope: scope, current_mission: mission, run: run} = socket.assigns

      socket
      |> assign(:planning?, true)
      |> start_async(:run_fleet_planning, fn ->
        FleetPlanner.run(
          scope,
          mission.mission_id,
          run.fleet_planning_run_id
        )
      end)
    else
      socket
    end
  end

  defp candidate_plan(
         _organization_id,
         _mission_id,
         %{candidate_contact_plan_id: nil},
         snapshots
       ),
       do: {nil, nil, snapshots}

  defp candidate_plan(organization_id, mission_id, run, snapshots) do
    case ContactPlans.fetch(organization_id, mission_id, run.candidate_contact_plan_id) do
      {:ok, plan, version} ->
        plan_snapshots =
          ContactPlans.selected_snapshots(
            organization_id,
            mission_id,
            plan.contact_plan_id,
            version.version
          )

        {plan, version,
         Enum.uniq_by(snapshots ++ plan_snapshots, & &1.contact_opportunity_snapshot_id)}

      {:error, _reason} ->
        {nil, nil, snapshots}
    end
  end

  defp resource_pressure(run) do
    run.result_summary_document
    |> get_in(["resources", "resources"])
    |> Kernel.||(%{})
    |> Enum.map(fn {id, resource} ->
      row = %{
        id: id,
        __dom_id: "fleet-resource-#{id}",
        peak_parallel: resource["peak_parallel"] || 0,
        capacity: resource["capacity"] || 1,
        over_capacity: resource["over_capacity"] == true
      }

      Map.put(row, :pressure_percent, pressure_percent(row))
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp repairable?(%{lifecycle_state: state})
       when state in [:executing, :partially_reserved, :failed],
       do: true

  defp repairable?(_plan), do: false

  defp repair_form(run) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    starts_at = later(now, run.horizon_start)
    ends_at = earlier(run.horizon_end, DateTime.add(starts_at, 12, :hour))

    ends_at =
      if DateTime.after?(ends_at, starts_at), do: ends_at, else: DateTime.add(starts_at, 1, :hour)

    to_form(
      %{
        "horizon_start" => datetime_local(starts_at),
        "horizon_end" => datetime_local(ends_at)
      },
      as: :repair
    )
  end

  defp decision_title(%{snapshot: nil, decision: decision}),
    do: decision.explanation_document["code"]

  defp decision_title(%{snapshot: snapshot}) do
    "#{snapshot.route_binding_document["provider_display_name"] || snapshot.route_binding_document["provider_id"]} · #{snapshot.normalized_opportunity_document["ground_station_ref"]}"
  end

  defp hard_constraint_label(decision) do
    failures = decision.hard_constraint_document["failures"] || []

    if failures == [],
      do: "All hard constraints satisfied.",
      else: Enum.map_join(failures, ", ", &humanize(&1["code"]))
  end

  defp pressure_percent(%{peak_parallel: peak, capacity: capacity}) do
    min(100, max(4, round(100 * peak / max(capacity, 1))))
  end

  defp duration(snapshot), do: DateTime.diff(snapshot.ends_at, snapshot.starts_at, :second)
  defp later(left, right), do: if(DateTime.after?(left, right), do: left, else: right)
  defp earlier(left, right), do: if(DateTime.before?(left, right), do: left, else: right)
  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      {:error, _reason} -> {:error, :fleet_repair_horizon_invalid}
    end
  end

  defp parse_datetime(_value), do: {:error, :fleet_repair_horizon_invalid}

  defp decision_class(:locked),
    do:
      "border border-info/40 bg-info/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-info"

  defp decision_class(:selected),
    do:
      "border border-primary/40 bg-primary/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-primary"

  defp decision_class(:ineligible),
    do:
      "border border-error/35 bg-error/[0.07] px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-error"

  defp decision_class(_disposition),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-base-content/55"

  defp result_class(state) when state in [:failed, :ineligible],
    do: "font-mono text-[0.62rem] uppercase text-error"

  defp result_class(state) when state in [:partial, :unsatisfied],
    do: "font-mono text-[0.62rem] uppercase text-warning"

  defp result_class(state) when state in [:satisfied, :succeeded, :reserved],
    do: "font-mono text-[0.62rem] uppercase text-success"

  defp result_class(_state),
    do: "font-mono text-[0.62rem] uppercase text-base-content/55"

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")
  defp humanize(nil), do: "unknown"
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp action_error(:fleet_repair_source_plan_not_repairable),
    do: "This Plan has no partial, failed, or uncertain execution to repair."

  defp action_error(:fleet_repair_attempt_limit_exceeded),
    do: "The active policy repair-attempt limit has been reached."

  defp action_error(:fleet_repair_horizon_exceeded),
    do: "The repair horizon exceeds the active policy boundary."

  defp action_error(_reason), do: "The fleet planning operation could not continue."
end
