defmodule CadenceWeb.OpsFleetPlanningRunLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
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
      |> stream_configure(:requirement_rows, dom_id: &"fleet-requirement-#{&1.id}")
      |> stream_configure(:exceptions, dom_id: &"fleet-exception-#{&1.id}")
      |> stream_configure(:decisions, dom_id: &"fleet-decision-#{&1.id}")
      |> stream_configure(:horizon_commitments, dom_id: &"fleet-commitment-#{&1.id}")
      |> stream_configure(:resource_pressure, dom_id: &"fleet-resource-#{&1.id}")
      |> stream_configure(:automation_actions, dom_id: &"fleet-action-#{&1.id}")

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
  def handle_event("refresh-fleet-run", _params, socket) do
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
      <section id="ops-fleet-planning-run-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto max-w-[110rem]">
            <.link
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning"}
              class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
            >
              <.icon name="hero-arrow-left" class="h-3.5 w-3.5" /> Fleet planning
            </.link>
            <div class="mt-4 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <span class={run_state_class(@run.lifecycle_state)}>
                    {humanize(@run.lifecycle_state)}
                  </span>
                  <span class="font-mono text-[0.65rem] uppercase text-base-content/45">
                    {@run.trigger_kind} · {@run.algorithm_key} v{@run.algorithm_version}
                  </span>
                </div>
                <h1 class="mt-2 text-2xl font-bold tracking-tight">Fleet horizon evidence</h1>
                <p class="mt-2 font-mono text-[0.65rem] text-base-content/45">
                  {@run.fleet_planning_run_id}
                </p>
              </div>
              <div class="flex flex-wrap gap-2">
                <button
                  id="refresh-fleet-planning-run"
                  type="button"
                  phx-click="refresh-fleet-run"
                  class="btn btn-ghost btn-sm gap-2"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" /> Refresh
                </button>
                <.link
                  :if={@plan}
                  id="fleet-run-candidate-plan-link"
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/plans/#{@plan.contact_plan_id}"}
                  class="btn btn-primary btn-sm gap-2"
                >
                  Open candidate Plan <.icon name="hero-arrow-right" class="h-4 w-4" />
                </.link>
              </div>
            </div>
          </div>
        </header>

        <div class="mx-auto max-w-[110rem] space-y-5 p-5 lg:p-7">
          <section id="fleet-run-phase-strip" class="grid border border-base-300 bg-base-200/20 sm:grid-cols-3 xl:grid-cols-6">
            <.phase_step
              :for={{phase, index} <- Enum.with_index(@phases)}
              phase={phase}
              index={index + 1}
              current={@run.phase}
            />
          </section>

          <section id="fleet-run-horizon-rail" class="border border-base-300 bg-base-200/15">
            <div class="grid gap-3 border-b border-base-300 px-4 py-3 md:grid-cols-[1fr_auto] md:items-end">
              <div>
                <p class="hud-label">Mission horizon rail</p>
                <p class="mt-1 font-mono text-xs tabular-nums">
                  {format_time(@run.horizon_start)} → {format_time(@run.horizon_end)}
                </p>
              </div>
              <p class="font-mono text-[0.65rem] text-base-content/45">
                {@commitment_count} selected · {@locked_count} locked
              </p>
            </div>
            <div class="relative min-h-28 overflow-x-auto px-4 py-5">
              <div class="absolute left-4 right-4 top-1/2 h-px bg-base-300"></div>
              <div
                id="fleet-horizon-commitments"
                phx-update="stream"
                class="relative flex min-w-max items-center gap-2"
              >
                <div id="fleet-horizon-commitments-empty" class="hidden only:block px-4 py-8 text-sm text-base-content/50">
                  No selected provider windows.
                </div>
                <div
                  :for={{dom_id, item} <- @streams.horizon_commitments}
                  id={dom_id}
                  class={[
                    "relative min-w-52 border px-3 py-3",
                    item.decision.disposition == :locked &&
                      "border-info/40 bg-info/[0.07]",
                    item.decision.disposition == :selected &&
                      "border-primary/40 bg-primary/[0.06]"
                  ]}
                >
                  <p class="truncate text-xs font-semibold">
                    {item.snapshot.route_binding_document["spacecraft_id"]}
                  </p>
                  <p class="mt-1 font-mono text-[0.62rem] text-base-content/50">
                    {format_time(item.snapshot.starts_at)} · {duration(item.snapshot)} sec
                  </p>
                  <span class="mt-2 inline-block font-mono text-[0.58rem] uppercase text-primary/75">
                    {item.decision.disposition}
                  </span>
                </div>
              </div>
            </div>
          </section>

          <div class="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(23rem,0.65fr)]">
            <div class="min-w-0 space-y-5">
              <section id="fleet-coverage-matrix" class="border border-base-300 bg-base-200/15">
                <div class="grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] border-b border-base-300 px-4 py-2 font-mono text-[0.58rem] uppercase tracking-wider text-base-content/45">
                  <span>Spacecraft / Requirement</span>
                  <span>Input</span>
                  <span>Coverage</span>
                  <span>Stage 4</span>
                </div>
                <div id="fleet-requirement-rows" phx-update="stream">
                  <div id="fleet-requirement-rows-empty" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
                    No Requirement inputs.
                  </div>
                  <div
                    :for={{dom_id, item} <- @streams.requirement_rows}
                    id={dom_id}
                    class="grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] items-center border-b border-base-300 px-4 py-3 text-xs last:border-b-0"
                  >
                    <div class="min-w-0">
                      <p class="truncate font-semibold">{item.version.spacecraft_id}</p>
                      <.link
                        navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirements/#{item.ref.contact_requirement_id}"}
                        class="mt-1 block truncate font-mono text-[0.6rem] text-primary/70 hover:underline"
                      >
                        {item.ref.contact_requirement_id} v{item.ref.contact_requirement_version}
                      </.link>
                    </div>
                    <span class={result_class(item.ref.input_state)}>{humanize(item.ref.input_state)}</span>
                    <span class={result_class(item.ref.result_state)}>{humanize(item.ref.result_state)}</span>
                    <span class="truncate font-mono text-[0.58rem] text-base-content/40">
                      {item.ref.contact_planning_run_id || "not searched"}
                    </span>
                  </div>
                </div>
              </section>

              <section id="fleet-decision-inspector" class="border border-base-300 bg-base-200/15">
                <div class="flex items-end justify-between border-b border-base-300 px-4 py-3">
                  <div>
                    <p class="hud-label">Decision inspector</p>
                    <p class="mt-1 text-sm text-base-content/55">
                      One durable rationale for every considered opportunity.
                    </p>
                  </div>
                  <span class="font-mono text-xs text-base-content/45">{@decision_count}</span>
                </div>
                <div id="fleet-decisions" phx-update="stream">
                  <div id="fleet-decisions-empty" class="hidden only:block px-4 py-12 text-center text-sm text-base-content/50">
                    Decisions appear after optimization.
                  </div>
                  <details
                    :for={{dom_id, item} <- @streams.decisions}
                    id={dom_id}
                    class="border-b border-base-300 last:border-b-0"
                  >
                    <summary class="grid cursor-pointer gap-3 px-4 py-3 md:grid-cols-[7rem_minmax(0,1fr)_6rem] md:items-center">
                      <span class={decision_class(item.decision.disposition)}>
                        {item.decision.disposition}
                      </span>
                      <span class="min-w-0">
                        <span class="block truncate text-xs font-semibold">
                          {decision_title(item)}
                        </span>
                        <span class="mt-0.5 block truncate font-mono text-[0.58rem] text-base-content/40">
                          {item.decision.contact_opportunity_snapshot_id}
                        </span>
                      </span>
                      <span class="text-right font-mono text-xs tabular-nums">
                        {item.decision.score}
                      </span>
                    </summary>
                    <div class="grid gap-4 border-t border-base-300 bg-base-200/25 px-4 py-4 md:grid-cols-2">
                      <div>
                        <p class="hud-label">Operational rationale</p>
                        <p class="mt-2 text-sm text-base-content/65">
                          {item.decision.explanation_document["message"]}
                        </p>
                      </div>
                      <div>
                        <p class="hud-label">Hard constraints</p>
                        <p class="mt-2 text-sm text-base-content/65">
                          {hard_constraint_label(item.decision)}
                        </p>
                      </div>
                    </div>
                  </details>
                </div>
              </section>
            </div>

            <aside class="min-w-0 space-y-5">
              <section
                :if={@exception_count > 0}
                id="fleet-exception-queue"
                class="border border-warning/35 bg-warning/[0.035]"
              >
                <div class="border-b border-warning/25 px-4 py-3">
                  <p class="hud-label text-warning">Exception queue · {@exception_count}</p>
                </div>
                <div id="fleet-exceptions" phx-update="stream">
                  <div id="fleet-exceptions-empty" class="hidden only:block"></div>
                  <div
                    :for={{dom_id, item} <- @streams.exceptions}
                    id={dom_id}
                    class="border-b border-warning/20 px-4 py-3 last:border-b-0"
                  >
                    <p class="truncate font-mono text-[0.62rem] text-warning">
                      {item.ref.contact_requirement_id}
                    </p>
                    <p class="mt-1 text-xs text-base-content/60">
                      {humanize(item.ref.result_state)}
                    </p>
                  </div>
                </div>
              </section>

              <section id="fleet-resource-pressure" class="border border-base-300 bg-base-200/15">
                <div class="border-b border-base-300 px-4 py-3">
                  <p class="hud-label">Provider resource pressure</p>
                </div>
                <div id="fleet-resource-pressure-rows" phx-update="stream">
                  <div id="fleet-resource-pressure-empty" class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50">
                    Resource pressure appears after optimization.
                  </div>
                  <div
                    :for={{dom_id, resource} <- @streams.resource_pressure}
                    id={dom_id}
                    class="border-b border-base-300 px-4 py-3 last:border-b-0"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <p class="truncate font-mono text-[0.6rem]">{resource.id}</p>
                      <span class={[
                        "font-mono text-xs",
                        resource.over_capacity && "text-error",
                        not resource.over_capacity && "text-base-content/55"
                      ]}>
                        {resource.peak_parallel}/{resource.capacity}
                      </span>
                    </div>
                    <div class="mt-2 h-1 overflow-hidden bg-base-300">
                      <div
                        class={[
                          "h-full",
                          resource.over_capacity && "bg-error",
                          not resource.over_capacity && "bg-primary/60"
                        ]}
                        style={"width: #{pressure_percent(resource)}%"}
                      >
                      </div>
                    </div>
                  </div>
                </div>
              </section>

              <section :if={@automation_action_count > 0} class="border border-base-300 bg-base-200/15">
                <div class="border-b border-base-300 px-4 py-3">
                  <p class="hud-label">Automation evidence</p>
                </div>
                <div id="fleet-automation-actions" phx-update="stream">
                  <div id="fleet-automation-actions-empty" class="hidden only:block"></div>
                  <div
                    :for={{dom_id, action} <- @streams.automation_actions}
                    id={dom_id}
                    class="flex items-center justify-between border-b border-base-300 px-4 py-3 last:border-b-0"
                  >
                    <span class="font-mono text-xs uppercase">{action.action}</span>
                    <span class={result_class(action.lifecycle_state)}>
                      {humanize(action.lifecycle_state)}
                    </span>
                  </div>
                </div>
              </section>

              <section
                :if={@repairable?}
                id="fleet-repair-panel"
                class="border border-info/35 bg-info/[0.035] p-4"
              >
                <p class="hud-label text-info">Repair without compensation</p>
                <p class="mt-2 text-sm text-base-content/60">
                  Successful and uncertain commitments remain locked. Only unmet capacity is searched and selected again.
                </p>
                <.form
                  for={@repair_form}
                  id="fleet-repair-form"
                  phx-submit="repair-fleet-run"
                  class="mt-4 space-y-3"
                >
                  <.input
                    id="fleet-repair-horizon-start"
                    field={@repair_form[:horizon_start]}
                    type="datetime-local"
                    label="Repair starts (UTC)"
                    required
                  />
                  <.input
                    id="fleet-repair-horizon-end"
                    field={@repair_form[:horizon_end]}
                    type="datetime-local"
                    label="Repair ends (UTC)"
                    required
                  />
                  <button id="start-fleet-repair" type="submit" class="btn btn-info btn-sm w-full">
                    Start repair run
                  </button>
                </.form>
              </section>

              <section :if={@run.failure_document != %{}} id="fleet-run-failure" class="border border-error/35 bg-error/[0.035] p-4">
                <p class="hud-label text-error">Stopped safely</p>
                <p class="mt-2 text-sm text-base-content/65">
                  {humanize(@run.failure_document["reason_code"] || @run.failure_document["code"])}
                </p>
                <p class="mt-2 font-mono text-[0.6rem] text-base-content/40">
                  phase {@run.failure_document["phase"]}
                </p>
              </section>
            </aside>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :phase, :atom, required: true
  attr :index, :integer, required: true
  attr :current, :atom, required: true

  defp phase_step(assigns) do
    assigns =
      assigns
      |> assign(:complete?, phase_index(assigns.phase) < phase_index(assigns.current))
      |> assign(:current?, assigns.phase == assigns.current)

    ~H"""
    <div class={[
      "border-b border-base-300 px-3 py-3 last:border-b-0 sm:border-r xl:border-b-0 xl:last:border-r-0",
      @current? && "bg-primary/[0.07]",
      @complete? && "text-base-content/65",
      not @current? and not @complete? && "text-base-content/35"
    ]}>
      <p class="font-mono text-[0.56rem] tracking-[0.16em] text-primary/60">
        {String.pad_leading(Integer.to_string(@index), 2, "0")}
      </p>
      <p class="mt-1 text-xs font-semibold">{humanize(@phase)}</p>
    </div>
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

      requirement_rows =
        Enum.map(refs, fn ref ->
          {:ok, version} =
            ContactRequirements.fetch_version(
              scope.organization_id,
              mission.mission_id,
              ref.contact_requirement_id,
              ref.contact_requirement_version
            )

          %{id: ref.contact_requirement_id, ref: ref, version: version}
        end)

      decision_rows =
        Enum.map(decisions, fn decision ->
          %{
            id: decision.fleet_planning_decision_id,
            decision: decision,
            snapshot: snapshot_by_id[decision.contact_opportunity_snapshot_id]
          }
        end)

      commitments =
        Enum.filter(decision_rows, fn item ->
          item.decision.disposition in [:selected, :locked] and item.snapshot
        end)

      exceptions =
        Enum.filter(requirement_rows, &(&1.ref.result_state in [:partial, :unsatisfied, :failed]))

      pressures = resource_pressure(run)

      actions =
        Cadence.list_fleet_automation_actions(scope.organization_id, mission.mission_id, run_id)

      repair_form = repair_form(run)

      {:ok,
       socket
       |> assign(:run, run)
       |> assign(:phases, @phases)
       |> assign(:plan, plan)
       |> assign(:plan_version, plan_version)
       |> assign(:repairable?, repairable?(plan))
       |> assign(:repair_form, repair_form)
       |> assign(:decision_count, length(decision_rows))
       |> assign(
         :commitment_count,
         Enum.count(commitments, &(&1.decision.disposition == :selected))
       )
       |> assign(:locked_count, Enum.count(commitments, &(&1.decision.disposition == :locked)))
       |> assign(:exception_count, length(exceptions))
       |> assign(:automation_action_count, length(actions))
       |> stream(:requirement_rows, requirement_rows, reset: true)
       |> stream(:exceptions, exceptions, reset: true)
       |> stream(:decisions, decision_rows, reset: true)
       |> stream(:horizon_commitments, commitments, reset: true)
       |> stream(:resource_pressure, pressures, reset: true)
       |> stream(:automation_actions, actions, reset: true)}
    end
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
    case Cadence.fetch_contact_plan(organization_id, mission_id, run.candidate_contact_plan_id) do
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
      %{
        id: id,
        peak_parallel: resource["peak_parallel"] || 0,
        capacity: resource["capacity"] || 1,
        over_capacity: resource["over_capacity"] == true
      }
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

  defp phase_index(phase), do: Enum.find_index(@phases, &(&1 == phase)) || 0
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

  defp run_state_class(:failed),
    do:
      "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"

  defp run_state_class(:partial),
    do:
      "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"

  defp run_state_class(state) when state in [:queued, :running],
    do:
      "border border-primary/40 bg-primary/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary"

  defp run_state_class(_state),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/60"

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
