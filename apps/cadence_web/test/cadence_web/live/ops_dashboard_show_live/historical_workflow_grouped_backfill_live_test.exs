defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupedBackfillLiveTest do
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

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views =
      Process.get(:ops_dashboard_historical_workflow_grouped_backfill_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(
        :ops_dashboard_historical_workflow_grouped_backfill_views,
        MapSet.put(tracked_views, pid)
      )

      on_exit({:ops_dashboard_historical_workflow_grouped_backfill_view, pid}, fn ->
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

  describe "historical workflow grouped backfill surfaces" do
    test "records grouped historical workflow requests for multiple points" do
      {conn, org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view
      |> element("#dashboard-historical-workflow-request-button")
      |> render_click()

      view
      |> element("#dashboard-historical-workflow-request-form")
      |> render_submit(%{
        "historical_workflow_request" => %{
          "workflow" => "backfill",
          "run_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "point_ids" => "HK.counter, HK.voltage\nHK.current",
          "source_from" => "2026-06-22T10:00:00Z",
          "source_to" => "2026-06-22T11:00:00Z",
          "reason" => "operator_requested_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(organization_id: org.organization_id)
        |> Enum.filter(&String.starts_with?(&1.backfill_run_id, "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.current", "HK.voltage"]

      assert Enum.map(events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-bulk-001",
               "dashboard-workflow-run-bulk-003",
               "dashboard-workflow-run-bulk-002"
             ]

      assert Enum.all?(events, &(&1.event_type == :backfill_requested))
      assert Enum.all?(events, &(&1.reason == "operator_requested_bulk_backfill_from_dashboard"))

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request mode"]),
               "bulk_points"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request group"]),
               "dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Request item"]),
               "1/3"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="requested"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-size="3"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="0"][data-historical-workflow-group-started="0"][data-historical-workflow-group-completed="0"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-request-eligible="0"][data-historical-workflow-group-approve-eligible="3"][data-historical-workflow-group-start-eligible="0"][data-historical-workflow-group-complete-eligible="0"])
             )

      assert has_element?(view, "#dashboard-historical-workflow-group-form")

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-eligible-items[data-historical-workflow-group-eligible-request-group="dashboard-workflow-run-bulk"][data-historical-workflow-group-eligible-size="3"])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="approved"][data-historical-workflow-group-eligible-count="3"][data-historical-workflow-group-eligible-state="true"]),
               "Record approve transition for 3 eligible items in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="started"][data-historical-workflow-group-eligible-count="0"][data-historical-workflow-group-eligible-state="false"][data-historical-workflow-group-eligible-reason="no_eligible_group_items"]),
               "No request-group items are eligible for start"
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-approved[data-historical-workflow-group-action-eligible="3"][data-workflow-action-id="group_stage_approved"][data-workflow-action-eligible="true"][data-workflow-action-reason="eligible_group_items"]:not([disabled])|
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "approved",
          "reason" => "operator_approved_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(&String.starts_with?(&1.backfill_run_id, "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.point_id)

      assert Enum.map(approved_events, & &1.point_id) == [
               "HK.counter",
               "HK.current",
               "HK.voltage"
             ]

      assert Enum.all?(
               approved_events,
               &(&1.reason == "operator_approved_bulk_backfill_from_dashboard")
             )

      duplicate_submit_html =
        view
        |> element("#dashboard-historical-workflow-group-form")
        |> render_submit(%{
          "historical_workflow_group" => %{
            "workflow" => "backfill",
            "request_group_id" => "dashboard-workflow-run-bulk",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry",
            "stage" => "approved",
            "reason" => "operator_duplicate_approved_bulk_backfill_from_dashboard",
            "confirmed" => "confirmed"
          }
        })

      assert duplicate_submit_html =~
               "No approve items are eligible in request group dashboard-workflow-run-bulk"

      refute duplicate_submit_html =~ "no_eligible_request_group_items"

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="no_op"][data-workflow-latest-action-reason="no_eligible_group_items"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      duplicate_approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(String.starts_with?(&1.backfill_run_id, "dashboard-workflow-run-bulk") and
              &1.reason == "operator_duplicate_approved_bulk_backfill_from_dashboard")
        )

      assert duplicate_approved_events == []

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Workflow stage"]),
               "approved"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="approved"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="3"][data-historical-workflow-group-started="0"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-approve-eligible="0"][data-historical-workflow-group-start-eligible="3"][data-historical-workflow-group-complete-eligible="0"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-approved[data-historical-workflow-group-action-eligible="0"][data-workflow-action-eligible="false"][data-workflow-action-reason="no_eligible_group_items"][disabled])
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-started[data-historical-workflow-group-action-eligible="3"]:not([disabled])|
             )

      view
      |> element("#dashboard-historical-workflow-group-form")
      |> render_submit(%{
        "historical_workflow_group" => %{
          "workflow" => "backfill",
          "request_group_id" => "dashboard-workflow-run-bulk",
          "realm" => "backfill",
          "data_source_id" => "managed_questdb_backfill",
          "source_binding_id" => "backfill_telemetry",
          "stage" => "started",
          "reason" => "operator_started_bulk_backfill_from_dashboard",
          "confirmed" => "confirmed"
        }
      })

      assert_patch(view)

      started_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_started
        )
        |> Enum.filter(&String.starts_with?(&1.backfill_run_id, "dashboard-workflow-run-bulk"))
        |> Enum.sort_by(& &1.backfill_run_id)

      assert Enum.map(started_events, & &1.backfill_run_id) == [
               "dashboard-workflow-run-bulk-001",
               "dashboard-workflow-run-bulk-002",
               "dashboard-workflow-run-bulk-003"
             ]

      assert Enum.all?(
               started_events,
               &(&1.reason == "operator_started_bulk_backfill_from_dashboard")
             )

      regressive_submit_html =
        view
        |> element("#dashboard-historical-workflow-group-form")
        |> render_submit(%{
          "historical_workflow_group" => %{
            "workflow" => "backfill",
            "request_group_id" => "dashboard-workflow-run-bulk",
            "realm" => "backfill",
            "data_source_id" => "managed_questdb_backfill",
            "source_binding_id" => "backfill_telemetry",
            "stage" => "approved",
            "reason" => "operator_regressed_started_bulk_backfill_from_dashboard",
            "confirmed" => "confirmed"
          }
        })

      assert regressive_submit_html =~
               "No approve items are eligible in request group dashboard-workflow-run-bulk"

      assert has_element?(
               view,
               ~s(#dashboard-data-link-action-outcome[data-data-link-action-outcome-action="group_stage_transition"][data-data-link-action-outcome-status="no_op"][data-data-link-action-outcome-kind="info"][data-data-link-action-outcome-reason="no_eligible_group_items"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-latest-action[data-workflow-latest-action="group_stage_transition"][data-workflow-latest-action-status="no_op"][data-workflow-latest-action-reason="no_eligible_group_items"][data-workflow-latest-action-stage="approved"][data-workflow-latest-action-request-group-id="dashboard-workflow-run-bulk"]),
               "No approve items are eligible in request group dashboard-workflow-run-bulk"
             )

      regressive_approved_events =
        mission.mission_id
        |> Storage.list_backfill_lifecycle_events(
          organization_id: org.organization_id,
          event_type: :backfill_approved
        )
        |> Enum.filter(
          &(String.starts_with?(&1.backfill_run_id, "dashboard-workflow-run-bulk") and
              &1.reason == "operator_regressed_started_bulk_backfill_from_dashboard")
        )

      assert regressive_approved_events == []

      assert {:ok, counter_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-001"
               )

      assert {:ok, voltage_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-002"
               )

      assert {:ok, current_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(
                 "dashboard-workflow-run-bulk-003"
               )

      assert Enum.map([counter_job, voltage_job, current_job], & &1.status) == [
               :queued,
               :queued,
               :queued
             ]

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-job-progress[data-historical-workflow-group-job-progress="queued 3"][data-historical-workflow-group-job-progress-queued="3"][data-historical-workflow-group-job-progress-running="0"][data-historical-workflow-group-job-progress-completed="0"][data-historical-workflow-group-job-progress-failed="0"][data-historical-workflow-group-job-progress-missing="0"]),
               "dashboard-workflow-run-bulk-001"
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-group-job-progress",
               "dashboard-workflow-run-bulk-002"
             )

      assert has_element?(
               view,
               "#dashboard-historical-workflow-group-job-progress",
               "dashboard-workflow-run-bulk-003"
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-summary[data-historical-workflow-group-state="running"][data-historical-workflow-group-terminal="false"][data-historical-workflow-group-requested="3"][data-historical-workflow-group-approved="3"][data-historical-workflow-group-started="3"][data-historical-workflow-group-failed="0"][data-historical-workflow-group-approve-eligible="0"][data-historical-workflow-group-start-eligible="0"][data-historical-workflow-group-complete-eligible="3"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-historical-workflow-group-started[data-historical-workflow-group-action-eligible="0"][disabled])
             )

      assert has_element?(
               view,
               ~s([data-historical-workflow-group-eligible-action="completed"][data-historical-workflow-group-eligible-count="3"][data-historical-workflow-group-eligible-state="true"]),
               "Record complete transition for 3 eligible items in request group dashboard-workflow-run-bulk"
             )

      assert has_element?(
               view,
               ~s|#dashboard-historical-workflow-group-completed[data-historical-workflow-group-action-eligible="3"]:not([disabled])|
             )
    end
  end
end
