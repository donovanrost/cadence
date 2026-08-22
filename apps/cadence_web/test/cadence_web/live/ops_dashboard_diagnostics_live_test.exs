defmodule CadenceWeb.OpsDashboardDiagnosticsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.RuntimeInvalidation
  alias CadenceWeb.TestFixtures

  test "diagnostic collections and master detail selection have stable URLs" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Diagnostics")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=cache"
      )

    assert has_element?(view, "#dashboard-diagnostic-collection-cache.text-primary")
    assert has_element?(view, "#dashboard-diagnostic-row-cache-contract")
    assert has_element?(view, "#dashboard-diagnostic-copy-identity")
    assert has_element?(view, "#diagnostics-open-explore")
    assert has_element?(view, "#diagnostics-open-sources")
    assert has_element?(view, "#diagnostics-open-catalog")

    view
    |> element("#dashboard-diagnostic-collection-invalidations")
    |> render_click()

    assert_patch(
      view,
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=invalidations"
    )

    assert has_element?(view, "#dashboard-diagnostic-count", "0")
  end

  test "durable invalidation decisions expose context, impact, and refresh evidence" do
    {conn, _user, organization, mission} = signed_in_user_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Invalidation Diagnostics",
        widgets: [%{type: :value_tile, title: "Counter", binding: %{point_id: "HK.counter"}}]
      )

    occurred_at = ~U[2026-08-01 12:00:00Z]

    invalidation =
      RuntimeInvalidation.Event.new(
        :historical_data_changed,
        [:source_result, :frame],
        %{
          organization_id: organization.organization_id,
          mission_id: mission.mission_id,
          logical_source: :telemetry,
          observable: "HK.counter",
          replay_run_id: "replay-run-1"
        },
        %{},
        %{plans: 0, source_results: 1, frames: 1, total: 2},
        occurred_at: occurred_at
      )

    assert {:ok, decision} =
             Cadence.record_dashboard_runtime_invalidation_decision(
               invalidation,
               %{
                 dashboard_id: dashboard.dashboard_id,
                 organization_id: organization.organization_id,
                 mission_id: mission.mission_id,
                 affected_placement_count: 1,
                 affected_placement_ids: [List.first(dashboard.placements).placement_id],
                 affected_widget_type_ids: ["cadence.value_tile"],
                 affected_impact_reasons: [:primary_source],
                 matches?: false,
                 dashboard_matches?: true,
                 context_matches?: false,
                 context_reason: :replay_run_mismatch,
                 refresh_allowed?: false,
                 refresh_reason: :stale_for_context,
                 decision_status: :filtered
               },
               decision_observed_at: ~U[2026-08-01 12:00:05Z]
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/diagnostics?collection=invalidations"
      )

    assert has_element?(view, "#dashboard-diagnostic-count", "1")

    assert has_element?(
             view,
             ~s([data-diagnostic-id*="#{decision.invalidation_event_id}"])
           )

    assert has_element?(
             view,
             ~s([data-diagnostic-id*="#{decision.invalidation_event_id}"]),
             "filtered"
           )

    assert has_element?(
             view,
             ~s([data-diagnostic-id*="#{decision.invalidation_event_id}"]),
             "historical_data_changed"
           )

    assert has_element?(view, "#dashboard-diagnostic-detail", "replay_run_mismatch")
    assert has_element?(view, "#dashboard-diagnostic-detail", "stale_for_context")
    assert has_element?(view, "#dashboard-diagnostic-copy-identity")
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-diagnostics")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
