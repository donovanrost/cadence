defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowComparisonReviewGroupRequestLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp record_comparison_review_request!(user, org, mission, dashboard) do
    assert {:ok, request_event} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 2,
                 "open_placement_ids" => ["placement-counter", "placement-voltage"],
                 "workflow_intent" => %{
                   "schema" => "dashboard_comparison_workflow_intent.v1",
                   "kind" => "bulk_correction_authority_review",
                   "source" => "dashboard_comparison_rollup",
                   "action" => "request_comparison_review",
                   "selection_kind" => "open_comparison_findings",
                   "selection_count" => 2,
                   "placement_ids" => ["placement-counter", "placement-voltage"],
                   "primary_data_view" => "all_revisions",
                   "compare_data_view" => "canonical"
                 },
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "comparison" => %{
                     "primary_data_view" => "all_revisions",
                     "compare_data_view" => "canonical"
                   },
                   "findings" => [
                     %{
                       "placement_id" => "placement-counter",
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "primary_observable_ids" => ["HK.counter"],
                       "compare_observable_ids" => ["HK.counter"]
                     },
                     %{
                       "placement_id" => "placement-voltage",
                       "title" => "Voltage",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "primary_observable_ids" => ["HK.voltage"],
                       "compare_observable_ids" => ["HK.voltage"]
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    request_event
  end

  defp submit_group_stage(view, stage, reason) do
    view
    |> element("#dashboard-historical-workflow-group-form")
    |> render_submit(%{
      "historical_workflow_group" => %{
        "workflow" => "backfill",
        "request_group_id" => "dashboard-comparison-workflow-run",
        "realm" => "backfill",
        "data_source_id" => "managed_questdb_backfill",
        "source_binding_id" => "backfill_telemetry",
        "stage" => stage,
        "reason" => reason,
        "confirmed" => "confirmed"
      }
    })
  end

  describe "historical workflow comparison-review surfaces" do
    test "starts a grouped historical workflow request from an open comparison review" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      request_event = record_comparison_review_request!(user, org, mission, dashboard)

      path =
        show_path(mission, dashboard) <>
          "?panel=versions&activity_filter=open_comparison_reviews&activity_event=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-comparison-review-workflow-request-#{request_event.dashboard_lifecycle_event_id}[data-dashboard-comparison-review-workflow-point-count="2"][data-dashboard-comparison-review-workflow-point-ids="HK.counter,HK.voltage"])
             )

      view
      |> element(
        "#dashboard-comparison-review-workflow-request-#{request_event.dashboard_lifecycle_event_id}"
      )
      |> render_click()

      assert has_element?(view, "#dashboard-historical-workflow-request-form")

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[observable_id]"][value="HK.counter"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[point_id]"][value="HK.counter"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[point_ids]"][value="HK.counter, HK.voltage"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[reason]"][value="operator_requested_bulk_correction_authority_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_request_event_id]"][value="#{request_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_request_kind]"][value="comparison_open_findings_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_open_count]"][value="2"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_open_placement_ids]"][value="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_kind]"][value="bulk_correction_authority_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_action]"][value="request_comparison_review"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_selection_kind]"][value="open_comparison_findings"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_workflow_selection_count]"][value="2"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_primary_data_view]"][value="all_revisions"])
             )

      assert has_element?(
               view,
               ~s(input[name="historical_workflow_request[comparison_review_compare_data_view]"][value="canonical"])
             )

      view
      |> form("#dashboard-historical-workflow-request-form", %{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-comparison-workflow-run",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "point_ids" => "HK.counter, HK.voltage",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_requested_bulk_correction_authority_review",
          "confirmed" => "confirmed"
        }
      })
      |> render_submit()

      assert_patch(view)

      events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(organization_id: org.organization_id)
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-comparison-workflow-run"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.voltage"]

      source_event = List.first(events)

      nav_trail =
        Jason.encode!([
          %{
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => source_event.backfill_lifecycle_event_id,
            "label" => "Backfill lifecycle event",
            "relationship_kind" => "comparison_review_origin",
            "relationship_label" => "Comparison review request",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry"
          }
        ])

      lifecycle_route =
        show_path(mission, dashboard) <>
          "?" <>
          URI.encode_query(%{
            "panel" => "data_link",
            "selected_target" => "dashboard_lifecycle_event",
            "selected_id" => request_event.dashboard_lifecycle_event_id,
            "nav_from_target" => "telemetry_backfill_lifecycle_event",
            "nav_from_target_id" => source_event.backfill_lifecycle_event_id,
            "nav_from_label" => "Backfill lifecycle event",
            "nav_from_relationship_kind" => "comparison_review_origin",
            "nav_from_relationship_label" => "Comparison review request",
            "nav_trail" => nav_trail,
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry"
          })

      {:ok, lifecycle_view, _html} = live(conn, lifecycle_route)
      render_dashboard_async(lifecycle_view)

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{request_event.dashboard_lifecycle_event_id}"][data-data-link-status="resolved"])
             )

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{source_event.backfill_lifecycle_event_id}"][phx-value-target="telemetry_backfill_lifecycle_event"][phx-value-nav-from-target-id="#{request_event.dashboard_lifecycle_event_id}"])
             )

      assert has_element?(
               lifecycle_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(request_event.dashboard_lifecycle_event_id)}"][data-clipboard-text*="nav_from_target=telemetry_backfill_lifecycle_event"][data-clipboard-text*="nav_from_target_id=#{URI.encode_www_form(source_event.backfill_lifecycle_event_id)}"][data-clipboard-text*="nav_trail="])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-group-comparison-review-open-count="2"][data-historical-workflow-group-comparison-review-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-comparison-review-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-group-comparison-review-workflow-action="request_comparison_review"][data-historical-workflow-group-comparison-review-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-group-comparison-review-workflow-selection-count="2"][data-historical-workflow-group-comparison-review-primary-data-view="all_revisions"][data-historical-workflow-group-comparison-review-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-review-origin[data-historical-workflow-review-origin-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-review-origin-open-count="2"][data-historical-workflow-review-origin-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-review-origin[data-historical-workflow-review-origin-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-review-origin-workflow-action="request_comparison_review"][data-historical-workflow-review-origin-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-review-origin-workflow-selection-count="2"][data-historical-workflow-review-origin-primary-data-view="all_revisions"][data-historical-workflow-review-origin-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-link="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-review-origin-href*="activity_filter=open_comparison_reviews"][data-historical-workflow-review-origin-href*="activity_event=#{request_event.dashboard_lifecycle_event_id}"]),
               "Open review"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-placement="placement-counter"][data-historical-workflow-review-origin-placement-href*="selected_placement=placement-counter"]),
               "placement-counter"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-review-origin-placement="placement-voltage"][data-historical-workflow-review-origin-placement-href*="selected_placement=placement-voltage"]),
               "placement-voltage"
             )

      submit_group_stage(
        view,
        "approved",
        "operator_approved_bulk_correction_authority_review"
      )

      assert_patch(view)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-next-action="start_eligible_items"][data-historical-workflow-group-start-eligible="2"][data-historical-workflow-group-start-expected-jobs="2"][data-historical-workflow-group-start-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-group-start-review-open-count="2"][data-historical-workflow-group-start-review-placements="placement-counter,placement-voltage"]),
               "2 review findings are attached."
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-review-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-group-start-review-workflow-action="request_comparison_review"][data-historical-workflow-group-start-review-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-group-start-review-workflow-selection-count="2"][data-historical-workflow-group-start-review-primary-data-view="all_revisions"][data-historical-workflow-group-start-review-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-start-orchestration[data-historical-workflow-group-start-reason="eligible_group_items"]),
               "Record start transition for 2 eligible items in request group dashboard-comparison-workflow-run"
             )

      submit_group_stage(
        view,
        "started",
        "operator_started_bulk_correction_authority_review"
      )

      assert_patch(view)

      [started_event | _started_events] =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_started
        )
        |> Enum.filter(&(&1.payload["request_group_id"] == "dashboard-comparison-workflow-run"))
        |> Enum.sort_by(& &1.point_id)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="ok"][data-workflow-latest-action-stage="started"][data-workflow-latest-action-request-group-id="dashboard-comparison-workflow-run"][data-workflow-latest-action-count="2"][data-workflow-latest-action-queued-jobs="2"][data-workflow-latest-action-failed-jobs="0"])
             )

      assert {:ok, job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(started_event.backfill_run_id)

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-status[data-historical-workflow-job-id="#{job.job_id}"][data-historical-workflow-job-status="queued"][data-historical-workflow-job-comparison-review-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-comparison-review-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-review-origin[data-historical-workflow-job-review-origin-request="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-review-origin-open-count="2"][data-historical-workflow-job-review-origin-placements="placement-counter,placement-voltage"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-job-review-origin[data-historical-workflow-job-review-origin-workflow-kind="bulk_correction_authority_review"][data-historical-workflow-job-review-origin-workflow-action="request_comparison_review"][data-historical-workflow-job-review-origin-workflow-selection-kind="open_comparison_findings"][data-historical-workflow-job-review-origin-workflow-selection-count="2"][data-historical-workflow-job-review-origin-primary-data-view="all_revisions"][data-historical-workflow-job-review-origin-compare-data-view="canonical"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-job-review-origin-link="#{request_event.dashboard_lifecycle_event_id}"][data-historical-workflow-job-review-origin-href*="activity_filter=open_comparison_reviews"][data-historical-workflow-job-review-origin-href*="activity_event=#{request_event.dashboard_lifecycle_event_id}"]),
               "Open review"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-job-review-origin-placement="placement-counter"][data-historical-workflow-job-review-origin-placement-href*="selected_placement=placement-counter"]),
               "placement-counter"
             )
    end
  end
end
