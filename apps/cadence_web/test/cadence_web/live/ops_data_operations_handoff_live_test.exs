defmodule CadenceWeb.OpsDataOperationsHandoffLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: role)
    mission = TestFixtures.persist_mission!(organization)

    {TestFixtures.member_conn(user), user, organization, mission}
  end

  test "dashboard context prefills a request that can be followed independently" do
    {conn, _user, organization, mission} = signed_in(:member)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        dashboard_id: "historical-gap-dashboard",
        name: "Historical Gap"
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{dashboard_id: dashboard.dashboard_id, dashboard_version: "3", dashboard_time_mode: "absolute", dashboard_data_view: "all_revisions", dashboard_limit_mode: "observed", realm: "flight", data_source_id: "flight-telemetry", source_binding_id: "flight-telemetry-binding", point_id: "HK.counter", point_ids: "HK.counter, HK.voltage", source_from: "2026-08-01T10:00:00Z", source_to: "2026-08-01T11:00:00Z", comparison_review_request_event_id: "review-request-1", comparison_review_request_kind: "operator_review", comparison_review_open_count: "2", comparison_review_open_placement_ids: "power-tile,thermal-chart"}}"
      )

    assert has_element?(view, "#ops-data-operations-page")
    assert has_element?(view, "#ops-context-rail")

    assert has_element?(
             view,
             ~s(input[name="historical_workflow_request[dashboard_id]"][value="#{dashboard.dashboard_id}"])
           )

    assert has_element?(
             view,
             ~s(input[name="historical_workflow_request[point_ids]"][value="HK.counter, HK.voltage"])
           )

    view
    |> form("#data-operation-request-form",
      historical_workflow_request: %{
        workflow: "backfill",
        run_id: "data-operation-handoff-1",
        realm: "flight",
        data_source_id: "flight-telemetry",
        source_binding_id: "flight-telemetry-binding",
        point_ids: "HK.counter, HK.voltage",
        source_from: "2026-08-01T10:00:00Z",
        source_to: "2026-08-01T11:00:00Z",
        dashboard_id: dashboard.dashboard_id,
        dashboard_version: "3",
        dashboard_time_mode: "absolute",
        dashboard_data_view: "all_revisions",
        dashboard_limit_mode: "observed",
        comparison_review_request_event_id: "review-request-1",
        comparison_review_request_kind: "operator_review",
        comparison_review_open_count: "2",
        comparison_review_open_placement_ids: "power-tile,thermal-chart",
        reason: "dashboard_historical_data_gap",
        confirmed: "true"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#data-operation-data-operation-handoff-1[data-operation-state="requested"])
           )

    assert has_element?(view, "#data-operation-group-id")

    assert has_element?(
             view,
             ~s(#data-operation-dashboard-#{dashboard.dashboard_id}[href*="/ops/dashboards/#{dashboard.dashboard_id}"][href*="selected_data_view=all_revisions"])
           )

    assert has_element?(
             view,
             ~s(#data-operation-comparison-review-request-1),
             "operator_review"
           )

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id
      )

    assert length(events) == 2
    assert Enum.all?(events, &(&1.payload["request_group_id"] == "data-operation-handoff-1"))

    assert Enum.all?(
             events,
             &(&1.payload["dashboard_context"]["dashboard_id"] == dashboard.dashboard_id)
           )

    refute has_element?(view, "#data-operation-recovery-panel")

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "data-operation-handoff-1"}}"
             )
  end

  test "organization administrators complete a group through the dedicated management route" do
    {conn, user, organization, mission} = signed_in(:organization_admin)

    assert {:ok, [_event]} =
             Cadence.record_telemetry_historical_data_workflow_request(
               :backfill,
               %{
                 backfill_run_id: "managed-operation-1",
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "flight-telemetry",
                 binding_id: "flight-telemetry-binding",
                 actor_id: user.user_id,
                 actor_kind: "operator",
                 reason: "operator_requested_backfill"
               },
               ["HK.counter"]
             )

    {:ok, reader, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "managed-operation-1"}}"
      )

    assert has_element?(reader, "#data-operations-manage-link")
    refute has_element?(reader, "#data-operation-transition-approved")

    {:ok, manager, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "managed-operation-1"}}"
      )

    assert has_element?(manager, "#data-operation-recovery-panel")
    assert has_element?(manager, "#data-operation-transition-approved")

    manager
    |> element("#data-operation-transition-approved")
    |> render_click()

    assert has_element?(
             manager,
             ~s(#data-operation-managed-operation-1[data-operation-state="approved"])
           )

    manager |> element("#data-operation-transition-started") |> render_click()
    manager |> element("#data-operation-transition-completed") |> render_click()

    assert has_element?(
             manager,
             ~s(#data-operation-managed-operation-1[data-operation-state="completed"])
           )

    assert has_element?(manager, "#data-operation-audit")

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id,
        backfill_run_id: "managed-operation-1"
      )

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_completed
           ]
  end

  test "grouped imports retain their workflow identity and independent progress" do
    {conn, _user, organization, mission} = signed_in(:member)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-operations")

    view
    |> form("#data-operation-request-form",
      historical_workflow_request: %{
        workflow: "import",
        run_id: "managed-import-1",
        realm: "backfill",
        data_source_id: "customer-archive",
        source_binding_id: "archive-import",
        point_ids: "HK.counter, HK.voltage",
        source_from: "2026-08-01T10:00:00Z",
        source_to: "2026-08-01T11:00:00Z",
        reason: "operator_requested_import",
        confirmed: "true"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#data-operation-managed-import-1[data-operation-state="requested"][data-operation-workflow="import"])
           )

    events =
      Cadence.list_telemetry_backfill_lifecycle_events(mission.mission_id,
        organization_id: organization.organization_id
      )

    assert Enum.map(events, & &1.event_type) == [:import_requested, :import_requested]
  end

  test "failed groups expose retry and correction posture only on the management route" do
    {conn, user, organization, mission} = signed_in(:organization_admin)

    seed_failed_item!(
      organization,
      mission,
      user,
      "failed-group-1",
      "retryable",
      true,
      "retry_job"
    )

    correction_event =
      seed_failed_item!(
        organization,
        mission,
        user,
        "failed-group-1",
        "correction",
        false,
        "correct_workflow_request"
      )

    {:ok, reader, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations?#{%{group: "failed-group-1"}}"
      )

    refute has_element?(reader, "#data-operation-recovery-panel")

    {:ok, manager, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-operations/manage?#{%{group: "failed-group-1"}}"
      )

    assert has_element?(manager, "#data-operation-retry-group")

    assert has_element?(
             manager,
             "#data-operation-correct-#{correction_event.backfill_lifecycle_event_id}"
           )

    assert has_element?(manager, "#data-operation-audit")
  end

  defp seed_failed_item!(organization, mission, user, group_id, suffix, retryable?, action) do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: "#{group_id}-#{suffix}",
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed-archive",
                 binding_id: "archive-binding",
                 observable_id: "HK.#{suffix}",
                 point_id: "HK.#{suffix}",
                 source_from: ~U[2026-08-01 10:00:00Z],
                 source_to: ~U[2026-08-01 11:00:00Z],
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: user.user_id,
                 actor_kind: "operator",
                 payload: %{
                   "request_group_id" => group_id,
                   "source" => %{
                     "failure" => %{
                       "code" => "source_window_unavailable",
                       "retryable" => retryable?,
                       "recovery_action" => action
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    event
  end
end
