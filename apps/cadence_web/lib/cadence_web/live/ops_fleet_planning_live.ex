defmodule CadenceWeb.OpsFleetPlanningLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{ContactRequirementTemplates, FleetPlanningPolicies}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Fleet Planning")
      |> assign(:ops_nav_item, :planning)
      |> stream_configure(:fleet_runs, dom_id: &"fleet-planning-run-#{&1.fleet_planning_run_id}")
      |> load_workspace()

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh-planning", _params, socket) do
    {:noreply, load_workspace(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-fleet-planning-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[100rem] flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
                Mission operations / fleet horizon
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Fleet Planning</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                Turn exact mission needs into one explainable provider commitment manifest. Healthy capacity stays quiet; gaps, contested resources, and stale evidence rise here.
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <button
                id="refresh-fleet-planning"
                type="button"
                phx-click="refresh-planning"
                class="btn btn-ghost btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
              >
                <.icon name="hero-arrow-path" class="h-4 w-4" /> Refresh
              </button>
              <.link
                id="fleet-planning-policy-link"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning/policy"}
                class="btn btn-ghost btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
              >
                <.icon name="hero-adjustments-horizontal" class="h-4 w-4" /> Policy
              </.link>
              <.link
                id="new-fleet-planning-run-link"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning/new"}
                class="btn btn-primary btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
              >
                <.icon name="hero-play" class="h-4 w-4" /> Plan horizon
              </.link>
            </div>
          </div>
        </header>

        <div class="mx-auto max-w-[100rem] space-y-5 p-5 lg:p-7">
          <section id="fleet-planning-control-strip" class="grid border border-base-300 bg-base-200/20 md:grid-cols-4">
            <.control_metric
              label="Active policy"
              value={policy_value(@active_policy)}
              detail={policy_detail(@active_policy)}
              tone={if @active_policy, do: :quiet, else: :warning}
            />
            <.control_metric
              label="Recurring demand"
              value={Integer.to_string(@template_count)}
              detail="active templates"
              tone={:quiet}
            />
            <.control_metric
              label="Automation"
              value={Integer.to_string(@active_grant_count)}
              detail="active exact grants"
              tone={if @active_grant_count > 0, do: :quiet, else: :muted}
            />
            <.control_metric
              label="Exceptions"
              value={Integer.to_string(@exception_run_count)}
              detail="partial or failed runs"
              tone={if @exception_run_count > 0, do: :warning, else: :quiet}
            />
          </section>

          <section
            :if={is_nil(@active_policy)}
            id="fleet-planning-policy-required"
            class="flex flex-col gap-4 border border-warning/35 bg-warning/[0.04] p-5 md:flex-row md:items-center md:justify-between"
          >
            <div>
              <p class="hud-label text-warning">Planning is intentionally stopped</p>
              <h2 class="mt-1 text-base font-semibold">Approve a fleet policy before searching providers.</h2>
              <p class="mt-1 text-sm text-base-content/55">
                The policy fixes horizon, concurrency, resource, budget, repair, and automation boundaries.
              </p>
            </div>
            <.link
              id="configure-fleet-planning-policy"
              navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning/policy"}
              class="btn btn-warning btn-sm"
            >
              Configure policy
            </.link>
          </section>

          <div class="grid gap-5 xl:grid-cols-[minmax(0,1.55fr)_minmax(20rem,0.55fr)]">
            <section class="min-w-0 border border-base-300 bg-base-200/15">
              <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
                <div>
                  <p class="hud-label">Run ledger</p>
                  <p class="mt-1 text-sm text-base-content/55">
                    Immutable inputs, durable checkpoints, and ordinary candidate Plans.
                  </p>
                </div>
                <span class="font-mono text-xs text-base-content/45">{@run_count} runs</span>
              </div>

              <div
                :if={@run_empty?}
                id="fleet-planning-runs-empty"
                class="px-6 py-16 text-center"
              >
                <.icon name="hero-chart-bar-square" class="mx-auto h-8 w-8 text-primary/35" />
                <h2 class="mt-4 text-base font-semibold">No fleet horizon has been planned</h2>
                <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">
                  Start with a bounded UTC horizon. Cadence will materialize recurring needs, search ready provider routes, and retain every decision.
                </p>
              </div>

              <div id="fleet-planning-runs" phx-update="stream">
                <div id="fleet-planning-runs-stream-empty" class="hidden only:block"></div>
                <.link
                  :for={{dom_id, run} <- @streams.fleet_runs}
                  id={dom_id}
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"}
                  class="group grid gap-4 border-b border-base-300 px-4 py-4 last:border-b-0 hover:bg-primary/[0.035] md:grid-cols-[minmax(11rem,0.7fr)_minmax(18rem,1.2fr)_minmax(9rem,0.45fr)_auto] md:items-center"
                >
                  <div>
                    <div class="flex items-center gap-2">
                      <span class={run_state_class(run.lifecycle_state)}>
                        {humanize(run.lifecycle_state)}
                      </span>
                      <span class="font-mono text-[0.6rem] uppercase text-base-content/40">
                        {run.trigger_kind}
                      </span>
                    </div>
                    <p class="mt-2 truncate font-mono text-[0.65rem] text-base-content/45">
                      {run.fleet_planning_run_id}
                    </p>
                  </div>
                  <div>
                    <p class="hud-label">UTC horizon</p>
                    <p class="mt-1 font-mono text-xs tabular-nums">
                      {format_time(run.horizon_start)} → {format_time(run.horizon_end)}
                    </p>
                    <div class="mt-2 h-1 overflow-hidden bg-base-300">
                      <div class={phase_width_class(run.phase)}></div>
                    </div>
                  </div>
                  <div>
                    <p class="hud-label">Coverage</p>
                    <p class={[
                      "mt-1 text-sm font-semibold",
                      coverage_shortfall?(run) && "text-warning",
                      not coverage_shortfall?(run) && "text-base-content/75"
                    ]}>
                      {coverage_label(run)}
                    </p>
                  </div>
                  <.icon
                    name="hero-chevron-right"
                    class="h-4 w-4 text-base-content/30 group-hover:text-primary"
                  />
                </.link>
              </div>
            </section>

            <aside class="space-y-5">
              <section id="fleet-planning-journey" class="border border-base-300 bg-base-200/15">
                <div class="border-b border-base-300 px-4 py-3">
                  <p class="hud-label">Operating loop</p>
                </div>
                <ol class="divide-y divide-base-300">
                  <.journey_item number="01" label="Demand" detail="Requirements and recurring templates" />
                  <.journey_item number="02" label="Search" detail="Provider-owned opportunities" />
                  <.journey_item number="03" label="Allocate" detail="Hard constraints before score" />
                  <.journey_item number="04" label="Commit" detail="Exact Plan approval and execution" />
                  <.journey_item number="05" label="Repair" detail="Preserve uncertain and successful work" />
                </ol>
              </section>

              <section class="border border-base-300 bg-base-200/15 p-4">
                <p class="hud-label">Recurring demand</p>
                <p class="mt-2 text-sm text-base-content/55">
                  Templates generate ordinary Requirements. They do not bypass the planning or approval journey.
                </p>
                <.link
                  id="requirement-templates-link"
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/requirement-templates"}
                  class="mt-4 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                >
                  Manage templates <.icon name="hero-arrow-right" class="h-3.5 w-3.5" />
                </.link>
              </section>
            </aside>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, required: true
  attr :tone, :atom, required: true

  defp control_metric(assigns) do
    ~H"""
    <div class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0">
      <p class="hud-label">{@label}</p>
      <p class={[
        "mt-1 font-mono text-lg font-semibold",
        @tone == :warning && "text-warning",
        @tone == :muted && "text-base-content/45",
        @tone == :quiet && "text-base-content/85"
      ]}>
        {@value}
      </p>
      <p class="mt-0.5 text-xs text-base-content/45">{@detail}</p>
    </div>
    """
  end

  attr :number, :string, required: true
  attr :label, :string, required: true
  attr :detail, :string, required: true

  defp journey_item(assigns) do
    ~H"""
    <li class="grid grid-cols-[2.25rem_1fr] gap-3 px-4 py-3">
      <span class="font-mono text-[0.6rem] tracking-[0.18em] text-primary/60">{@number}</span>
      <div>
        <p class="text-sm font-semibold">{@label}</p>
        <p class="mt-0.5 text-xs text-base-content/45">{@detail}</p>
      </div>
    </li>
    """
  end

  defp load_workspace(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    runs = Cadence.list_fleet_planning_runs(scope.organization_id, mission.mission_id, limit: 100)

    active_policy =
      case FleetPlanningPolicies.fetch_active(
             scope.organization_id,
             mission.mission_id
           ) do
        {:ok, policy, version} -> {policy, version}
        {:error, _reason} -> nil
      end

    templates =
      ContactRequirementTemplates.list(
        scope.organization_id,
        mission.mission_id,
        lifecycle_state: :active
      )

    active_grants =
      Cadence.list_automation_grants(
        scope.organization_id,
        mission.mission_id,
        lifecycle_state: :active
      )

    socket
    |> assign(:active_policy, active_policy)
    |> assign(:template_count, length(templates))
    |> assign(:active_grant_count, length(active_grants))
    |> assign(
      :exception_run_count,
      Enum.count(runs, &(&1.lifecycle_state in [:partial, :failed]))
    )
    |> assign(:run_count, length(runs))
    |> assign(:run_empty?, runs == [])
    |> stream(:fleet_runs, runs, reset: true)
  end

  defp policy_value(nil), do: "STOPPED"

  defp policy_value({_policy, version}),
    do: "v#{version.version}"

  defp policy_detail(nil), do: "no approved boundary"

  defp policy_detail({_policy, version}) do
    "#{version.horizon_document["max_horizon_seconds"] |> div(3_600)}h maximum horizon"
  end

  defp coverage_shortfall?(run), do: run.lifecycle_state in [:partial, :failed]

  defp coverage_label(%{lifecycle_state: :failed}), do: "Stopped"

  defp coverage_label(run) do
    coverage = run.result_summary_document["coverage"] || %{}
    satisfied = Enum.count(coverage, fn {_id, item} -> item["state"] == "satisfied" end)
    "#{satisfied}/#{run.input_document["requirement_count"] || 0}"
  end

  defp phase_width_class(:queued), do: "h-full w-[8%] bg-primary/55"
  defp phase_width_class(:materializing), do: "h-full w-1/5 bg-primary/55"
  defp phase_width_class(:searching), do: "h-full w-2/5 bg-primary/65"
  defp phase_width_class(:optimizing), do: "h-full w-3/5 bg-primary/70"
  defp phase_width_class(:materializing_plan), do: "h-full w-4/5 bg-primary/75"
  defp phase_width_class(:finished), do: "h-full w-full bg-primary/80"

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

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")
end
