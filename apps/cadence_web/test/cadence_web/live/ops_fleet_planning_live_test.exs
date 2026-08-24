defmodule CadenceWeb.OpsFleetPlanningLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 2, track_async_view: 1]

  import Phoenix.LiveViewTest, except: [render_async: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningRuns
  }

  alias CadenceWeb.TestFixtures

  test "authenticated mission operators can navigate the planning journey and see stopped state" do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope(:member)

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning")

    assert has_element?(view, "#ops-fleet-planning-component.contents")

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/planning"][class*="text-primary"])
           )

    planning_vue = fleet_planning_vue(view)

    assert planning_vue.component == "OpsFleetPlanning"
    assert planning_vue.class == "contents"
    assert planning_vue.ssr == false
    assert planning_vue.slots == %{}

    assert planning_vue.handlers == %{
             "refresh-planning" => Phoenix.LiveView.JS.push("refresh-planning")
           }

    assert planning_vue.props ==
             workspace_props(
               mission,
               stopped_control_metrics(),
               stopped_policy_props(mission),
               ledger_props(0, ledger_empty_props())
             )

    assert fleet_run_stream_mutations(planning_vue) == [
             ["replace", "/fleet_runs", []]
           ]

    assert_json_safe_fleet_planning_vue(planning_vue)

    {:ok, new_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(new_view, "#ops-fleet-planning-new-component")
    refute has_element?(new_view, "#ops-fleet-planning-new-page")
    refute has_element?(new_view, "#fleet-planning-new-policy-required")
    refute has_element?(new_view, "#fleet-planning-run-form")

    new_vue = LiveVue.Test.get_vue(new_view, id: "ops-fleet-planning-new-component")

    assert new_vue.component == "OpsFleetPlanningNew"
    assert new_vue.class == "contents"
    assert new_vue.ssr == false
    assert new_vue.props == Jason.decode!(Jason.encode!(new_vue.props))

    assert new_vue.handlers == %{
             "create-fleet-run" => Phoenix.LiveView.JS.push("create-fleet-run"),
             "validate-fleet-run" => Phoenix.LiveView.JS.push("validate-fleet-run")
           }

    assert new_vue.props == %{
             "form" => nil,
             "header" => %{
               "id" => "ops-fleet-planning-new-page",
               "back" => %{
                 "id" => "fleet-planning-back-link",
                 "icon" => "hero-arrow-left",
                 "label" => "Fleet planning"
               },
               "title" => "Plan a mission horizon",
               "copy" =>
                 "Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules."
             },
             "paths" => %{
               "planning" => "/missions/#{mission.mission_id}/ops/planning",
               "policy" => "/missions/#{mission.mission_id}/ops/planning/policy"
             },
             "policy_state" => %{
               "active" => false,
               "required" => %{
                 "id" => "fleet-planning-new-policy-required",
                 "icon" => "hero-lock-closed",
                 "title" => "An approved policy is required",
                 "copy" =>
                   "Provider searches remain stopped until an organization administrator approves the fleet boundary.",
                 "action_id" => "fleet-planning-open-policy-link",
                 "action_label" => "Open policy"
               }
             },
             "preview" => nil
           }

    {:ok, policy_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(policy_view, "#ops-fleet-planning-policy-page")
    assert has_element?(policy_view, "#fleet-policy-admin-required")
    refute has_element?(policy_view, "#fleet-policy-form")

    {:ok, template_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert has_element?(template_view, "#ops-requirement-templates-page")
    assert has_element?(template_view, "#requirement-template-admin-required")
  end

  test "planning workspace refresh replaces the ledger with exact run contracts" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    horizon_end = DateTime.add(now, 6, :hour)

    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning")

    initial_vue = fleet_planning_vue(view)

    assert initial_vue.props ==
             workspace_props(
               mission,
               active_control_metrics("0"),
               nil,
               ledger_props(0, ledger_empty_props())
             )

    assert fleet_run_stream_mutations(initial_vue) == [
             ["replace", "/fleet_runs", []]
           ]

    assert {:ok, queued_run, [_queued_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    assert {:ok, partial_source, [_partial_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :scheduled
             })

    assert {:ok, failed_source, [_failed_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    partial_run = finish_partial_run!(scope, mission, partial_source, requirement)

    assert {:ok, failed_run} =
             FleetPlanningRuns.fail(
               scope,
               mission.mission_id,
               failed_source.fleet_planning_run_id,
               :queued,
               %{"code" => "provider_search_unavailable"}
             )

    render_hook(view, "refresh-planning", %{})

    refreshed_vue = fleet_planning_vue(view)

    assert refreshed_vue.props ==
             workspace_props(
               mission,
               active_control_metrics("2"),
               nil,
               ledger_props(3, nil)
             )

    expected_rows = %{
      queued_run.fleet_planning_run_id => queued_run_props(queued_run, mission),
      partial_run.fleet_planning_run_id => partial_run_props(partial_run, mission),
      failed_run.fleet_planning_run_id => failed_run_props(failed_run, mission)
    }

    assert Map.new(fleet_run_upserts(refreshed_vue), &{&1["fleet_planning_run_id"], &1}) ==
             expected_rows

    assert [
             ["replace", "/fleet_runs", []],
             ["upsert", "/fleet_runs/-", _first_run],
             ["upsert", "/fleet_runs/-", _second_run],
             ["upsert", "/fleet_runs/-", _third_run]
           ] = fleet_run_stream_mutations(refreshed_vue)

    assert_json_safe_fleet_planning_vue(refreshed_vue)
  end

  test "an organization administrator creates and activates the exact fleet policy in UI" do
    {conn, _scope, org, mission, _spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(view, "#fleet-policy-empty")
    assert has_element?(view, "#fleet-policy-form")

    view
    |> form("#fleet-policy-form",
      policy: %{
        "max_horizon_hours" => "24",
        "requirement_concurrency" => "8",
        "provider_search_concurrency" => "4",
        "reuse_freshness_seconds" => "300",
        "max_contacts" => "300",
        "max_estimated_cost_micros" => "",
        "currency" => "",
        "critical_contact_reserve" => "5",
        "automation_mode" => "advisory",
        "execution_concurrency" => "4",
        "max_repair_attempts" => "3",
        "repair_horizon_hours" => "12"
      }
    )
    |> render_submit()

    assert has_element?(view, "#fleet-policy-approval-form")
    assert has_element?(view, "#fleet-policy-state", "draft")

    view
    |> form("#fleet-policy-approval-form",
      decision: %{reason: "Bound mission-scale provider demand"}
    )
    |> render_submit()

    assert has_element?(view, "#fleet-policy-state", "active")
    refute has_element?(view, "#fleet-policy-approval-form")

    assert {:ok, policy, version} =
             FleetPlanningPolicies.fetch_active(
               org.organization_id,
               mission.mission_id
             )

    assert policy.active_version == version.version
    assert version.budget_quota_document["max_contacts"] == 300
    assert version.budget_quota_document["critical_contact_reserve"] == 5
  end

  test "administrator creates and pauses a progressively rendered recurring Requirement Template" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert has_element?(view, "#requirement-template-form")
    assert has_element?(view, "#template-interval-minutes")
    refute has_element?(view, "#template-time-utc")

    params = template_params(spacecraft)

    view
    |> form("#requirement-template-form",
      template:
        params
        |> Map.drop(["interval_minutes", "minimum_data_volume_bytes", "time_utc"])
        |> Map.put("schedule_type", "daily")
    )
    |> render_change()

    assert has_element?(view, "#template-time-utc")
    refute has_element?(view, "#template-interval-minutes")

    view
    |> form("#requirement-template-form",
      template: Map.drop(params, ["interval_minutes", "minimum_data_volume_bytes"])
    )
    |> render_change()

    view
    |> form("#requirement-template-form",
      template: Map.drop(params, ["minimum_data_volume_bytes", "time_utc"])
    )
    |> render_submit()

    [{template, version}] =
      ContactRequirementTemplates.list(
        org.organization_id,
        mission.mission_id
      )

    assert version.spacecraft_id == spacecraft.spacecraft_id
    assert version.schedule_document["type"] == "fixed_interval"
    assert version.schedule_document["interval_seconds"] == 21_600
    assert has_element?(view, "#requirement-template-#{template.contact_requirement_template_id}")

    view
    |> element("#pause-template-#{template.contact_requirement_template_id}")
    |> render_click()

    [{paused, _version}] =
      ContactRequirementTemplates.list(
        org.organization_id,
        mission.mission_id
      )

    assert paused.lifecycle_state == :paused
    assert has_element?(view, "#activate-template-#{template.contact_requirement_template_id}")
  end

  test "starting a horizon persists first and the run workspace resumes durable phases" do
    {conn, scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(view, "#ops-fleet-planning-new-component")
    refute has_element?(view, "#fleet-planning-run-form")
    refute has_element?(view, "#fleet-run-policy-preview")
    refute has_element?(view, "#fleet-run-policy-progressive-details")

    initial_vue = LiveVue.Test.get_vue(view, id: "ops-fleet-planning-new-component")

    assert initial_vue.component == "OpsFleetPlanningNew"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "create-fleet-run" => Phoenix.LiveView.JS.push("create-fleet-run"),
             "validate-fleet-run" => Phoenix.LiveView.JS.push("validate-fleet-run")
           }

    assert initial_vue.props["form"]["id"] == "fleet-planning-run-form"
    assert initial_vue.props["preview"]["id"] == "fleet-run-policy-preview"

    assert initial_vue.props["preview"]["details"]["id"] ==
             "fleet-run-policy-progressive-details"

    horizon_end = DateTime.add(now, 6, :hour)

    fleet_run_params = %{
      "horizon_start" => datetime_local(now),
      "horizon_end" => datetime_local(horizon_end),
      "include_recurring" => "true"
    }

    render_hook(view, "validate-fleet-run", %{"fleet_run" => fleet_run_params})

    validated_vue = LiveVue.Test.get_vue(view, id: "ops-fleet-planning-new-component")

    assert validated_vue.props == %{
             "form" => %{
               "id" => "fleet-planning-run-form",
               "fields" => %{
                 "horizon_start" => %{
                   "id" => "fleet-run-horizon-start",
                   "name" => "fleet_run[horizon_start]",
                   "type" => "datetime-local",
                   "label" => "Horizon starts (UTC)",
                   "required" => true,
                   "value" => datetime_local(now),
                   "errors" => []
                 },
                 "horizon_end" => %{
                   "id" => "fleet-run-horizon-end",
                   "name" => "fleet_run[horizon_end]",
                   "type" => "datetime-local",
                   "label" => "Horizon ends (UTC)",
                   "required" => true,
                   "value" => datetime_local(horizon_end),
                   "errors" => []
                 },
                 "include_recurring" => %{
                   "id" => "fleet-run-include-recurring",
                   "name" => "fleet_run[include_recurring]",
                   "type" => "checkbox",
                   "label" => "Materialize recurring Requirement Templates in this horizon",
                   "value" => true,
                   "errors" => []
                 }
               },
               "snapshot" => %{
                 "label" => "Snapshot boundary",
                 "copy" =>
                   "Starting the run freezes exact Requirement and policy versions. Later edits stop the run closed rather than silently changing its inputs."
               },
               "submit" => %{
                 "id" => "start-fleet-planning-run",
                 "label" => "Start durable planning run"
               }
             },
             "header" => %{
               "id" => "ops-fleet-planning-new-page",
               "back" => %{
                 "id" => "fleet-planning-back-link",
                 "icon" => "hero-arrow-left",
                 "label" => "Fleet planning"
               },
               "title" => "Plan a mission horizon",
               "copy" =>
                 "Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules."
             },
             "paths" => %{
               "planning" => "/missions/#{mission.mission_id}/ops/planning",
               "policy" => "/missions/#{mission.mission_id}/ops/planning/policy"
             },
             "policy_state" => %{"active" => true, "required" => nil},
             "preview" => %{
               "id" => "fleet-run-policy-preview",
               "eyebrow" => "Active policy",
               "version" => "v1",
               "facts" => [
                 %{"term" => "Maximum horizon", "value" => "24 hours"},
                 %{"term" => "Requirement workers", "value" => "4"},
                 %{"term" => "Provider searches", "value" => "2"},
                 %{"term" => "Contact ceiling", "value" => "100"},
                 %{"term" => "Automation", "value" => "advisory"}
               ],
               "details" => %{
                 "id" => "fleet-run-policy-progressive-details",
                 "summary" => "Why these settings?",
                 "copy" =>
                   "Operators choose demand and horizon. Administrators own organizational risk: provider concurrency, cost, quotas, and unattended authority."
               }
             }
           }

    assert validated_vue.props == Jason.decode!(Jason.encode!(validated_vue.props))

    render_hook(view, "create-fleet-run", %{"fleet_run" => fleet_run_params})

    [run] = FleetPlanningRuns.list(org.organization_id, mission.mission_id)

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
    )

    {:ok, run_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
      )

    track_async_view(run_view)

    assert has_element?(run_view, "#ops-fleet-planning-run-page")
    assert has_element?(run_view, "#fleet-run-phase-strip")
    assert has_element?(run_view, "#fleet-coverage-matrix")
    assert has_element?(run_view, "#fleet-decision-inspector")
    assert has_element?(run_view, "#fleet-requirement-rows [id^=fleet-requirement-]")

    render_async(run_view, 5_000)

    assert {:ok, finished} =
             FleetPlanningRuns.fetch(
               org.organization_id,
               mission.mission_id,
               run.fleet_planning_run_id
             )

    assert finished.phase == :finished
  end

  defp fleet_planning_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-fleet-planning-component")
  end

  defp fleet_run_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/fleet_runs/" <> _index, _run] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, run] -> run end)
  end

  defp fleet_run_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_fleet_planning_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp workspace_props(mission, control_metrics, stopped_policy, ledger) do
    %{
      "page" => %{
        "id" => "ops-fleet-planning-page",
        "header" => %{
          "eyebrow" => "Mission operations / fleet horizon",
          "title" => "Fleet Planning",
          "copy" =>
            "Turn exact mission needs into one explainable provider commitment manifest. Healthy capacity stays quiet; gaps, contested resources, and stale evidence rise here."
        }
      },
      "actions" => %{
        "refresh" => %{
          "id" => "refresh-fleet-planning",
          "icon" => "hero-arrow-path",
          "label" => "Refresh"
        },
        "policy" => %{
          "id" => "fleet-planning-policy-link",
          "href" => "/missions/#{mission.mission_id}/ops/planning/policy",
          "icon" => "hero-adjustments-horizontal",
          "label" => "Policy"
        },
        "new_run" => %{
          "id" => "new-fleet-planning-run-link",
          "href" => "/missions/#{mission.mission_id}/ops/planning/new",
          "icon" => "hero-play",
          "label" => "Plan horizon"
        }
      },
      "control_metrics" => control_metrics,
      "stopped_policy" => stopped_policy,
      "ledger" => ledger,
      "journey" => %{
        "id" => "fleet-planning-journey",
        "eyebrow" => "Operating loop",
        "steps" => [
          %{
            "id" => "fleet-planning-journey-01",
            "number" => "01",
            "label" => "Demand",
            "detail" => "Requirements and recurring templates"
          },
          %{
            "id" => "fleet-planning-journey-02",
            "number" => "02",
            "label" => "Search",
            "detail" => "Provider-owned opportunities"
          },
          %{
            "id" => "fleet-planning-journey-03",
            "number" => "03",
            "label" => "Allocate",
            "detail" => "Hard constraints before score"
          },
          %{
            "id" => "fleet-planning-journey-04",
            "number" => "04",
            "label" => "Commit",
            "detail" => "Exact Plan approval and execution"
          },
          %{
            "id" => "fleet-planning-journey-05",
            "number" => "05",
            "label" => "Repair",
            "detail" => "Preserve uncertain and successful work"
          }
        ]
      },
      "recurring_demand" => %{
        "id" => "fleet-planning-recurring-demand-panel",
        "eyebrow" => "Recurring demand",
        "copy" =>
          "Templates generate ordinary Requirements. They do not bypass the planning or approval journey.",
        "action" => %{
          "id" => "requirement-templates-link",
          "href" => "/missions/#{mission.mission_id}/ops/requirement-templates",
          "label" => "Manage templates",
          "icon" => "hero-arrow-right"
        }
      }
    }
  end

  defp stopped_control_metrics do
    [
      control_metric_props(
        "fleet-planning-active-policy",
        "Active policy",
        "STOPPED",
        "no approved boundary",
        "warning"
      ),
      control_metric_props(
        "fleet-planning-recurring-demand",
        "Recurring demand",
        "0",
        "active templates",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-automation",
        "Automation",
        "0",
        "active exact grants",
        "muted"
      ),
      control_metric_props(
        "fleet-planning-exceptions",
        "Exceptions",
        "0",
        "partial or failed runs",
        "quiet"
      )
    ]
  end

  defp active_control_metrics(exception_count) do
    [
      control_metric_props(
        "fleet-planning-active-policy",
        "Active policy",
        "v1",
        "24h maximum horizon",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-recurring-demand",
        "Recurring demand",
        "0",
        "active templates",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-automation",
        "Automation",
        "0",
        "active exact grants",
        "muted"
      ),
      control_metric_props(
        "fleet-planning-exceptions",
        "Exceptions",
        exception_count,
        "partial or failed runs",
        if(exception_count == "0", do: "quiet", else: "warning")
      )
    ]
  end

  defp control_metric_props(id, label, value, detail, tone) do
    %{"id" => id, "label" => label, "value" => value, "detail" => detail, "tone" => tone}
  end

  defp stopped_policy_props(mission) do
    %{
      "id" => "fleet-planning-policy-required",
      "eyebrow" => "Planning is intentionally stopped",
      "title" => "Approve a fleet policy before searching providers.",
      "copy" =>
        "The policy fixes horizon, concurrency, resource, budget, repair, and automation boundaries.",
      "action" => %{
        "id" => "configure-fleet-planning-policy",
        "href" => "/missions/#{mission.mission_id}/ops/planning/policy",
        "label" => "Configure policy"
      }
    }
  end

  defp ledger_props(count, empty) do
    %{
      "eyebrow" => "Run ledger",
      "copy" => "Immutable inputs, durable checkpoints, and ordinary candidate Plans.",
      "count" => count,
      "count_label" => "#{count} runs",
      "runs_id" => "fleet-planning-runs",
      "stream_empty_id" => "fleet-planning-runs-stream-empty",
      "empty" => empty
    }
  end

  defp ledger_empty_props do
    %{
      "id" => "fleet-planning-runs-empty",
      "icon" => "hero-chart-bar-square",
      "title" => "No fleet horizon has been planned",
      "copy" =>
        "Start with a bounded UTC horizon. Cadence will materialize recurring needs, search ready provider routes, and retain every decision."
    }
  end

  defp queued_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "queued",
        "label" => "queued",
        "tone" => "primary",
        "class" =>
          "border border-primary/40 bg-primary/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary"
      },
      %{"kind" => "manual", "label" => "manual"},
      %{"state" => "queued", "width_class" => "h-full w-[8%] bg-primary/55"},
      %{"label" => "Coverage", "value" => "0/1", "shortfall" => false, "tone" => "quiet"}
    )
  end

  defp partial_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "partial",
        "label" => "partial",
        "tone" => "warning",
        "class" =>
          "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"
      },
      %{"kind" => "scheduled", "label" => "scheduled"},
      %{"state" => "finished", "width_class" => "h-full w-full bg-primary/80"},
      %{"label" => "Coverage", "value" => "1/1", "shortfall" => true, "tone" => "warning"}
    )
  end

  defp failed_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "failed",
        "label" => "failed",
        "tone" => "error",
        "class" =>
          "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"
      },
      %{"kind" => "manual", "label" => "manual"},
      %{"state" => "finished", "width_class" => "h-full w-full bg-primary/80"},
      %{
        "label" => "Coverage",
        "value" => "Stopped",
        "shortfall" => true,
        "tone" => "warning"
      }
    )
  end

  defp fleet_run_props(run, mission, lifecycle, trigger, phase, coverage) do
    horizon_start = fleet_time(run.horizon_start)
    horizon_end = fleet_time(run.horizon_end)

    %{
      "id" => run.fleet_planning_run_id,
      "__dom_id" => "fleet-planning-run-#{run.fleet_planning_run_id}",
      "fleet_planning_run_id" => run.fleet_planning_run_id,
      "href" =>
        "/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}",
      "lifecycle" => lifecycle,
      "trigger" => trigger,
      "horizon" => %{
        "label" => "UTC horizon",
        "start" => horizon_start,
        "end" => horizon_end,
        "value" => "#{horizon_start} → #{horizon_end}"
      },
      "phase" => phase,
      "coverage" => coverage,
      "open_icon" => "hero-chevron-right"
    }
  end

  defp finish_partial_run!(scope, mission, run, requirement) do
    [
      {:queued, :materializing, %{}},
      {:materializing, :searching, %{}},
      {:searching, :optimizing, %{}},
      {:optimizing, :materializing_plan, %{}},
      {:materializing_plan, :finished,
       %{
         outcome: :partial,
         result_summary_document: %{
           "coverage" => %{
             requirement.contact_requirement_id => %{"state" => "satisfied"}
           }
         }
       }}
    ]
    |> Enum.reduce(run, fn {expected, next, attrs}, current ->
      assert {:ok, advanced} =
               FleetPlanningRuns.advance_phase(
                 scope,
                 mission.mission_id,
                 current.fleet_planning_run_id,
                 expected,
                 next,
                 attrs
               )

      advanced
    end)
  end

  defp fleet_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")

  defp activate_policy!(scope, mission) do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(scope, mission.mission_id, policy_attrs())

    assert {:ok, _active, ^version, _approval} =
             FleetPlanningPolicies.approve(
               scope,
               mission.mission_id,
               policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Enable LiveView fleet planning"
             )
  end

  defp signed_in_scope(role) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: role)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "fleet-planning",
        display_name: "Fleet Planning Mission"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Asteria")

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    {TestFixtures.member_conn(user), scope, org, mission, spacecraft}
  end

  defp template_params(spacecraft) do
    now = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    %{
      "spacecraft_id" => spacecraft.spacecraft_id,
      "schedule_type" => "fixed_interval",
      "anchor_at" => datetime_local(now),
      "time_utc" => "12:00:00",
      "interval_minutes" => "360",
      "window_offset_minutes" => "10",
      "window_duration_minutes" => "45",
      "contact_intent" => "recurring_payload_downlink",
      "success_measure" => "minimum_duration",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "approval_mode" => "manual",
      "maximum_occurrences_per_run" => "50",
      "maximum_lookback_hours" => "72",
      "rationale" => "Routine recorder relief"
    }
  end

  defp requirement_attrs(spacecraft_id, now) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(now, 600, :second),
      latest_end: DateTime.add(now, 18_000, :second),
      success_measure: :minimum_duration,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "LiveView fleet planning proof",
      metadata: %{}
    }
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 4,
        "provider_search_concurrency" => 2,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{},
      resource_policy_document: %{},
      budget_quota_document: %{
        "max_contacts" => 100,
        "max_estimated_cost_micros" => nil,
        "currency" => nil,
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{},
      automation_repair_document: %{
        "mode" => "advisory",
        "execution_concurrency" => 2,
        "max_repair_attempts" => 2,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => false
      }
    }
  end

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
end
