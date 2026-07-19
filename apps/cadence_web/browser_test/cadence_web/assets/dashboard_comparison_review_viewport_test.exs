# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardComparisonReviewViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live comparison review bulk decision passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-bulk-decision-viewport",
        display_name: "Comparison Review Bulk Decision Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Bulk Decision")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Bulk Decision Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 1,
                 "open_placement_ids" => [counter_item.placement_id],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecision\""
    assert bulk_decision_output =~ "\"actionOutcome\""
    assert bulk_decision_output =~ "\"decision\": \"mark_conflict\""

    assert bulk_decision_output =~
             "\"decision_reason\": \"dashboard_comparison_review_mark_conflict\""

    assert bulk_decision_output =~ "\"source_request_event_id\""
  end

  @tag :browser
  test "live comparison review partial bulk decision passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-partial-bulk-decision-viewport",
        display_name: "Comparison Review Partial Bulk Decision Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Bulk")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Partial Bulk Decision Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Missing Review Target",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.voltage"
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Untracked Review Target",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.current"
            },
            layout: %{x: 8, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 2, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")
    missing_item = render_item_by_title(document, "Missing Review Target")
    untracked_item = render_item_by_title(document, "Untracked Review Target")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    missing_observation_identity_id = "missing-comparison-review-browser-identity"

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 3,
                 "open_placement_ids" => [
                   counter_item.placement_id,
                   missing_item.placement_id,
                   untracked_item.placement_id
                 ],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     },
                     %{
                       "placement_id" => missing_item.placement_id,
                       "title" => "Missing identity",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "observation_identity_id" => missing_observation_identity_id,
                       "primary_observation_identity_id" => missing_observation_identity_id,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     },
                     %{
                       "placement_id" => untracked_item.placement_id,
                       "title" => "Untracked finding",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision",
                 "--expected-bulk-decision-status",
                 "degraded",
                 "--expected-bulk-decision-status-label",
                 "Partial",
                 "--expected-bulk-decision-reason",
                 "comparison_review_bulk_decision_partially_applied",
                 "--expected-bulk-decision-form-count",
                 "2",
                 "--expected-bulk-decision-form-placements",
                 "#{counter_item.placement_id},#{missing_item.placement_id}",
                 "--expected-bulk-decision-skipped-count",
                 "1",
                 "--expected-bulk-decision-skipped-placements",
                 untracked_item.placement_id,
                 "--expected-bulk-decision-skipped-reasons",
                 "missing_observation_identity",
                 "--expected-bulk-decision-applied",
                 "1",
                 "--expected-bulk-decision-failed",
                 "1",
                 "--expected-bulk-decision-message",
                 "Comparison review decisions applied to 1 findings; 1 failed.",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecision\""
    assert bulk_decision_output =~ "\"status\": \"degraded\""
    assert bulk_decision_output =~ "\"skippedCount\": \"1\""
    assert bulk_decision_output =~ "\"skippedReasons\": \"missing_observation_identity\""
    assert bulk_decision_output =~ "\"applied\": \"1\""
    assert bulk_decision_output =~ "\"failed\": \"1\""
  end

  @tag :browser
  test "live resolved mixed comparison review preserves audit context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-resolved-audit-viewport",
        display_name: "Comparison Review Resolved Audit Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Resolved Audit")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Resolved Audit Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Untracked Review Target",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.current"
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 2, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")
    untracked_item = render_item_by_title(document, "Untracked Review Target")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    assert {:ok, review_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 2,
                 "open_placement_ids" => [
                   counter_item.placement_id,
                   untracked_item.placement_id
                 ],
                 "workflow_intent" => %{
                   "schema" => "dashboard_comparison_workflow_intent.v1",
                   "kind" => "bulk_correction_authority_review",
                   "source" => "dashboard_comparison_rollup",
                   "action" => "request_comparison_review",
                   "selection_kind" => "open_comparison_findings",
                   "selection_count" => 2,
                   "placement_ids" => [
                     counter_item.placement_id,
                     untracked_item.placement_id
                   ]
                 },
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "runtime_query" => source_context,
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     },
                     %{
                       "placement_id" => untracked_item.placement_id,
                       "title" => "Untracked finding",
                       "state" => "missing",
                       "decision_status" => "unhandled",
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    assert {:ok, resolution} =
             Cadence.Dashboards.record_dashboard_comparison_review_resolution(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_resolution.v1",
                 "source_request_event_id" => review_request.dashboard_lifecycle_event_id,
                 "disposition" => "review_completed",
                 "resolution_reason" => "Resolved browser audit",
                 "selected_placement_id" => counter_item.placement_id,
                 "affected_placement_ids" => [
                   counter_item.placement_id,
                   untracked_item.placement_id
                 ]
               },
               actor_id: user.user_id
             )

    assert resolution.payload["source_bulk_decision_actionable_count"] == 1
    assert resolution.payload["source_bulk_decision_skipped_count"] == 1

    assert resolution.payload["source_bulk_decision_skipped_reasons"] == [
             "missing_observation_identity"
           ]

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    resolved_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "comparison_reviews", activity_event: resolution.dashboard_lifecycle_event_id}}"

    expected_source_open_placements =
      "#{counter_item.placement_id},#{untracked_item.placement_id}"

    assert {resolved_audit_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-resolved-audit",
                 "--expected-review-resolution-source-open-count",
                 "2",
                 "--expected-review-resolution-source-open-placements",
                 expected_source_open_placements,
                 "--expected-review-resolution-source-actionable-count",
                 "1",
                 "--expected-review-resolution-source-actionable-placements",
                 counter_item.placement_id,
                 "--expected-review-resolution-source-skipped-count",
                 "1",
                 "--expected-review-resolution-source-skipped-placements",
                 untracked_item.placement_id,
                 "--expected-review-resolution-source-skipped-reasons",
                 "missing_observation_identity",
                 "--url",
                 resolved_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert resolved_audit_output =~ "dashboard_viewport_smoke passed"
    assert resolved_audit_output =~ "\"comparisonReviewResolvedAudit\""
    assert resolved_audit_output =~ "\"sourceActionableCount\": \"1\""
    assert resolved_audit_output =~ "\"sourceSkippedCount\": \"1\""
    assert resolved_audit_output =~ "\"sourceSkippedReasons\": \"missing_observation_identity\""
    assert resolved_audit_output =~ "\"recovery\": \"hidden\""
    assert resolved_audit_output =~ "\"urlActivityFilter\": \"\""
  end

  @tag :browser
  test "live comparison review missing source context passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-missing-source-viewport",
        display_name: "Comparison Review Missing Source Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Missing Source")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review Missing Source Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")

    assert [observation_identity_state] =
             Storage.list_observation_identity_states(mission.mission_id,
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               point_id: "HK.counter"
             )

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 1,
                 "open_placement_ids" => [counter_item.placement_id],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_identity_id" =>
                         observation_identity_state.observation_identity_id,
                       "primary_observation_id" =>
                         observation_identity_state.canonical_observation_id,
                       "primary_sample_id" => observation_identity_state.canonical_sample_id,
                       "primary_revision" => observation_identity_state.canonical_revision,
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical"
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision-unavailable",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecisionUnavailable\""
    assert bulk_decision_output =~ "\"unavailableReason\": \"missing_source_context\""
    assert bulk_decision_output =~ "\"formPresent\": false"
    assert bulk_decision_output =~ "\"actionOutcomePresent\": false"
  end

  @tag :browser
  test "live comparison review no actionable findings passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "comparison-review-no-actionable-viewport",
        display_name: "Comparison Review No Actionable Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC No Actionable")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, 1_700_000_100)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Comparison Review No Actionable Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")

    source_context = %{
      "realm" => "flight",
      "data_source_id" => DataSources.default_managed_data_source().data_source_id,
      "source_binding_id" => "default_flight_telemetry"
    }

    assert {:ok, bulk_request} =
             Cadence.Dashboards.record_dashboard_comparison_review_request(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %{
                 "schema" => "dashboard_comparison_review_request.v1",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => 1,
                 "open_placement_ids" => [counter_item.placement_id],
                 "open_findings" => %{
                   "schema" => "dashboard_comparison_open_findings.v1",
                   "findings" => [
                     %{
                       "placement_id" => counter_item.placement_id,
                       "title" => "Counter",
                       "state" => "increased",
                       "decision_status" => "unhandled",
                       "primary_data_view" => "all_revisions",
                       "compare_data_view" => "canonical",
                       "primary_data_link" => %{"context" => %{"data" => source_context}}
                     }
                   ]
                 }
               },
               actor_id: user.user_id
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    bulk_request_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "versions", activity_filter: "open_comparison_reviews", activity_event: bulk_request.dashboard_lifecycle_event_id}}"

    assert {bulk_decision_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "comparison-review-bulk-decision-unavailable",
                 "--expected-bulk-decision-unavailable-reason",
                 "no_actionable_findings",
                 "--expected-bulk-decision-unavailable-count",
                 "0",
                 "--expected-bulk-decision-unavailable-text",
                 "no actionable findings",
                 "--expected-bulk-decision-unavailable-placements",
                 "",
                 "--url",
                 bulk_request_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert bulk_decision_output =~ "dashboard_viewport_smoke passed"
    assert bulk_decision_output =~ "\"comparisonReviewBulkDecisionUnavailable\""
    assert bulk_decision_output =~ "\"unavailableReason\": \"no_actionable_findings\""
    assert bulk_decision_output =~ "\"unavailableCount\": \"0\""
    assert bulk_decision_output =~ "\"formPresent\": false"
    assert bulk_decision_output =~ "\"actionOutcomePresent\": false"
  end

  @tag :browser
  test "live revision decision inspector preserves dashboard limit mode in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "revision-limit-mode-viewport",
        display_name: "Revision Limit Mode Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Browser")
    binding_set = persist_binding_set!(org, mission)
    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 37, base_unix,
      dashboard_runtime_invalidation?: false
    )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [initial_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert {:ok, _state} =
             Cadence.apply_telemetry_observation_identity_decision(
               initial_state.observation_identity_id,
               "mark_canonical",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 canonical_observation_id: initial_state.canonical_observation_id,
                 canonical_sample_id: initial_state.canonical_sample_id,
                 canonical_revision: initial_state.canonical_revision,
                 decision_reason: "browser_smoke_revision_source_marker",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-source-marker-1",
                   "source_target" => "comparison_finding",
                   "source_target_id" => "browser-placement-1",
                   "source_link_label" => "Comparison finding"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    [source_event] =
      Storage.list_observation_identity_decision_events(
        initial_state.observation_identity_id,
        query_opts
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Limit Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter",
            layout: %{x: 0, y: 0, w: 4, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Counter",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          },
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 4, y: 0, w: 6, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: [:events]
              },
              options: %{}
            }
          }
        ]
      )

    selected_query = %{
      limit_mode: "compare"
    }

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()
    start_browser_endpoint!(port, sandbox_owner)
    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "revision-decision-limit-mode",
                 "--expected-limit-mode",
                 "compare",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
    assert output =~ "\"revisionDecisionLimitMode\""
    assert output =~ ~s("sourceEventId": "#{source_event.decision_event_id}")
    assert output =~ ~s("decision": "mark_conflict")
    assert output =~ ~s("dashboardLimitMode": "compare")
    assert output =~ ~s("targetObservationIdentityId": "#{initial_state.observation_identity_id}")
    assert output =~ ~s("revisionActionLimitMode": "compare")
  end
end
