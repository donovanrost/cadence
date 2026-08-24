defmodule CadenceWeb.OpsFleetPlanningLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningRuns
  }

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Fleet Planning")
      |> assign(:ops_nav_item, :planning)
      |> assign(:planning_page, page_dto())
      |> assign(:planning_actions, actions_dto(socket.assigns.current_mission))
      |> assign(:planning_journey, journey_dto())
      |> assign(:recurring_demand, recurring_demand_dto(socket.assigns.current_mission))
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
      <.vue
        id="ops-fleet-planning-component"
        v-component="OpsFleetPlanning"
        page={@planning_page}
        actions={@planning_actions}
        control_metrics={@control_metrics}
        stopped_policy={@stopped_policy}
        ledger={@planning_ledger}
        journey={@planning_journey}
        recurring_demand={@recurring_demand}
        fleet_runs={@streams.fleet_runs}
        v-on:refresh-planning={JS.push("refresh-planning")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto do
    %{
      id: "ops-fleet-planning-page",
      header: %{
        eyebrow: "Mission operations / fleet horizon",
        title: "Fleet Planning",
        copy:
          "Turn exact mission needs into one explainable provider commitment manifest. Healthy capacity stays quiet; gaps, contested resources, and stale evidence rise here."
      }
    }
  end

  defp actions_dto(mission) do
    %{
      refresh: %{
        id: "refresh-fleet-planning",
        icon: "hero-arrow-path",
        label: "Refresh"
      },
      policy: %{
        id: "fleet-planning-policy-link",
        href: ~p"/missions/#{mission.mission_id}/ops/planning/policy",
        icon: "hero-adjustments-horizontal",
        label: "Policy"
      },
      new_run: %{
        id: "new-fleet-planning-run-link",
        href: ~p"/missions/#{mission.mission_id}/ops/planning/new",
        icon: "hero-play",
        label: "Plan horizon"
      }
    }
  end

  defp control_metrics_dto(active_policy, template_count, active_grant_count, exception_count) do
    [
      control_metric_dto(
        "fleet-planning-active-policy",
        "Active policy",
        policy_value(active_policy),
        policy_detail(active_policy),
        if(active_policy, do: "quiet", else: "warning")
      ),
      control_metric_dto(
        "fleet-planning-recurring-demand",
        "Recurring demand",
        Integer.to_string(template_count),
        "active templates",
        "quiet"
      ),
      control_metric_dto(
        "fleet-planning-automation",
        "Automation",
        Integer.to_string(active_grant_count),
        "active exact grants",
        if(active_grant_count > 0, do: "quiet", else: "muted")
      ),
      control_metric_dto(
        "fleet-planning-exceptions",
        "Exceptions",
        Integer.to_string(exception_count),
        "partial or failed runs",
        if(exception_count > 0, do: "warning", else: "quiet")
      )
    ]
  end

  defp control_metric_dto(id, label, value, detail, tone) do
    %{id: id, label: label, value: value, detail: detail, tone: tone}
  end

  defp stopped_policy_dto(nil, mission) do
    %{
      id: "fleet-planning-policy-required",
      eyebrow: "Planning is intentionally stopped",
      title: "Approve a fleet policy before searching providers.",
      copy:
        "The policy fixes horizon, concurrency, resource, budget, repair, and automation boundaries.",
      action: %{
        id: "configure-fleet-planning-policy",
        href: ~p"/missions/#{mission.mission_id}/ops/planning/policy",
        label: "Configure policy"
      }
    }
  end

  defp stopped_policy_dto(_active_policy, _mission), do: nil

  defp ledger_dto(run_count, run_empty?) do
    %{
      eyebrow: "Run ledger",
      copy: "Immutable inputs, durable checkpoints, and ordinary candidate Plans.",
      count: run_count,
      count_label: "#{run_count} runs",
      runs_id: "fleet-planning-runs",
      stream_empty_id: "fleet-planning-runs-stream-empty",
      empty:
        if(run_empty?,
          do: %{
            id: "fleet-planning-runs-empty",
            icon: "hero-chart-bar-square",
            title: "No fleet horizon has been planned",
            copy:
              "Start with a bounded UTC horizon. Cadence will materialize recurring needs, search ready provider routes, and retain every decision."
          },
          else: nil
        )
    }
  end

  defp journey_dto do
    %{
      id: "fleet-planning-journey",
      eyebrow: "Operating loop",
      steps: [
        journey_step_dto("01", "Demand", "Requirements and recurring templates"),
        journey_step_dto("02", "Search", "Provider-owned opportunities"),
        journey_step_dto("03", "Allocate", "Hard constraints before score"),
        journey_step_dto("04", "Commit", "Exact Plan approval and execution"),
        journey_step_dto("05", "Repair", "Preserve uncertain and successful work")
      ]
    }
  end

  defp journey_step_dto(number, label, detail) do
    %{id: "fleet-planning-journey-#{number}", number: number, label: label, detail: detail}
  end

  defp recurring_demand_dto(mission) do
    %{
      id: "fleet-planning-recurring-demand-panel",
      eyebrow: "Recurring demand",
      copy:
        "Templates generate ordinary Requirements. They do not bypass the planning or approval journey.",
      action: %{
        id: "requirement-templates-link",
        href: ~p"/missions/#{mission.mission_id}/ops/requirement-templates",
        label: "Manage templates",
        icon: "hero-arrow-right"
      }
    }
  end

  defp load_workspace(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    runs = FleetPlanningRuns.list(scope.organization_id, mission.mission_id, limit: 100)

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
      AutomationGrants.list(
        scope.organization_id,
        mission.mission_id,
        lifecycle_state: :active
      )

    template_count = length(templates)
    active_grant_count = length(active_grants)
    exception_run_count = Enum.count(runs, &(&1.lifecycle_state in [:partial, :failed]))

    socket
    |> assign(
      :control_metrics,
      control_metrics_dto(
        active_policy,
        template_count,
        active_grant_count,
        exception_run_count
      )
    )
    |> assign(:stopped_policy, stopped_policy_dto(active_policy, mission))
    |> assign(:planning_ledger, ledger_dto(length(runs), runs == []))
    |> stream(
      :fleet_runs,
      Enum.map(runs, &fleet_run_dto(&1, mission.mission_id)),
      reset: true
    )
  end

  defp fleet_run_dto(run, mission_id) do
    shortfall? = coverage_shortfall?(run)

    %{
      id: run.fleet_planning_run_id,
      fleet_planning_run_id: run.fleet_planning_run_id,
      href:
        ~p"/missions/#{mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}",
      lifecycle: %{
        state: Atom.to_string(run.lifecycle_state),
        label: humanize(run.lifecycle_state),
        tone: run_state_tone(run.lifecycle_state),
        class: run_state_class(run.lifecycle_state)
      },
      trigger: %{
        kind: Atom.to_string(run.trigger_kind),
        label: humanize(run.trigger_kind)
      },
      horizon: %{
        label: "UTC horizon",
        start: format_time(run.horizon_start),
        end: format_time(run.horizon_end),
        value: "#{format_time(run.horizon_start)} → #{format_time(run.horizon_end)}"
      },
      phase: %{
        state: Atom.to_string(run.phase),
        width_class: phase_width_class(run.phase)
      },
      coverage: %{
        label: "Coverage",
        value: coverage_label(run),
        shortfall: shortfall?,
        tone: if(shortfall?, do: "warning", else: "quiet")
      },
      open_icon: "hero-chevron-right"
    }
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

  defp run_state_tone(:failed), do: "error"
  defp run_state_tone(:partial), do: "warning"
  defp run_state_tone(state) when state in [:queued, :running], do: "primary"
  defp run_state_tone(_state), do: "muted"

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
