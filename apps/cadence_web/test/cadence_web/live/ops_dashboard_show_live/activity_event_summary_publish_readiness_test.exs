defmodule CadenceWeb.OpsDashboardShowLive.ActivityEventSummaryPublishReadinessTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{DataBindingEvent, DataSourceEvent, SourceHealthEvent}
  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary

  test "rows summarize publish readiness check payloads" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        actor_id: "operator-1",
        dashboard_version: 4,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "still_blocked",
          "error_count" => 1,
          "warning_count" => 0,
          "issue_count" => 1,
          "issue_codes" => ["unready_publish_source_request"],
          "source_warning_codes" => ["unsupported_source_capability"],
          "source_evidence_contexts" => [
            %{
              "warning_code" => "unsupported_source_capability",
              "source_request_id" => "request-telemetry-latest",
              "logical_source" => "telemetry",
              "source_binding_id" => "rehearsal-binding",
              "data_source_id" => "rehearsal-source",
              "replay_run_id" => "replay-run-7"
            }
          ],
          "freshness_state" => "stale",
          "freshness_reason_label" => "source stale",
          "freshness_message" =>
            "Source watermark evidence is stale; re-check readiness after source data advances.",
          "remediation_targets" => [
            %{
              "label" => "Use a compatible source",
              "target" => "data_sources",
              "params" => %{"source_binding_id" => "rehearsal-binding"}
            }
          ]
        }
      )

    [row] = ActivityEventSummary.rows([event], nil)

    assert row.title == "Publish readiness checked"
    assert row.event_type == :publish_readiness_checked
    assert row.version_text == "v4"
    assert row.remediation_count == 2
    assert row.remediation_count_text == "2"

    assert row.remediation_actions == [
             %{
               label: "Use a compatible source",
               target: "data_sources",
               message: nil,
               params: %{"source_binding_id" => "rehearsal-binding"}
             },
             %{
               label:
                 "Inspect telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)",
               target: "data_sources",
               message: "Open the source evidence associated with this readiness check.",
               params: %{
                 "data_source_id" => "rehearsal-source",
                 "logical_source" => "telemetry",
                 "replay_run_id" => "replay-run-7",
                 "selected_evidence_kind" => "source",
                 "selected_source_evidence_mode" => "health",
                 "source_binding_id" => "rehearsal-binding",
                 "source_empty_reason" => "unsupported_source_capability"
               }
             }
           ]

    assert [
             %{label: "Occurred", value: "2026-06-27 12:00:00 UTC"},
             %{label: "Actor", value: "operator-1"},
             %{label: "Result", value: "still_blocked"},
             %{label: "Errors", value: "1"},
             %{label: "Warnings", value: "0"},
             %{label: "Issues", value: "1"},
             %{label: "Issue codes", value: "unready_publish_source_request"},
             %{label: "Source blockers", value: "unsupported_source_capability"},
             %{
               label: "Source evidence",
               value:
                 "telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)"
             },
             %{label: "Freshness", value: "stale"},
             %{label: "Freshness reason", value: "source stale"},
             %{
               label: "Freshness detail",
               value:
                 "Source watermark evidence is stale; re-check readiness after source data advances."
             },
             %{label: "Remediation", value: "Use a compatible source -> data_sources"},
             %{
               label: "Readiness trend",
               value: "No previous publish readiness check is available for comparison."
             },
             %{label: "Published", value: "- -> -"}
           ] = Enum.map(row.fields, &Map.take(&1, [:label, :value]))
  end

  test "rows prefer typed publish readiness remediation actions when present" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        dashboard_version: 4,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "still_blocked",
          "error_count" => 1,
          "issue_count" => 1,
          "issue_codes" => ["unready_publish_source_request"],
          "source_warning_codes" => ["source_connection_failed"],
          "remediation_targets" => [
            %{
              "label" => "Legacy flattened action",
              "target" => "data_sources",
              "params" => %{"data_source_id" => "legacy-source"}
            }
          ],
          "typed_remediation_actions" => [
            %{
              "action_id" => "dashboard-publish-source-readiness-action",
              "issue_id" =>
                "error:unready_publish_source_request:tile-1:source_connection_failed",
              "label" => "Fix source connection",
              "message" =>
                "Open Data Sources, inspect the failed connection test, and repair the adapter, credentials, or endpoint before refreshing publish readiness.",
              "target" => "source_health",
              "kind" => "invoke",
              "query" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "connection_test_failed"
              }
            }
          ]
        }
      )

    [row] = ActivityEventSummary.rows([event], nil)

    assert row.remediation_count == 1

    assert row.remediation_actions == [
             %{
               issue_id: "error:unready_publish_source_request:tile-1:source_connection_failed",
               label: "Fix source connection",
               target: "data_sources",
               message:
                 "Open Data Sources, inspect the failed connection test, and repair the adapter, credentials, or endpoint before refreshing publish readiness.",
               params: %{
                 "data_source_id" => "rehearsal-source",
                 "source_binding_id" => "rehearsal-binding",
                 "source_empty_reason" => "connection_test_failed"
               }
             }
           ]
  end

  test "build compares selected publish readiness checks to the previous check" do
    previous =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-1",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 3
        }
      )

    current =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-2",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 1
        }
      )

    summary =
      ActivityEventSummary.build(
        [previous, current],
        "dashboard-lifecycle-event-readiness-2",
        [previous, current],
        %{filter_value: "publish_readiness"}
      )

    assert summary.readiness_comparison == %{
             state: "improved",
             label: "improved",
             message: "Readiness improved: 3 issues -> 1 issue.",
             previous_event_id: "dashboard-lifecycle-event-readiness-1",
             previous_result: "still_blocked",
             previous_issue_count: 3,
             current_result: "still_blocked",
             current_issue_count: 1
           }

    assert %{label: "Readiness trend", value: "Readiness improved: 3 issues -> 1 issue."} in Enum.map(
             summary.fields,
             &Map.take(&1, [:label, :value])
           )
  end

  test "build marks publish readiness regressions" do
    previous =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-1",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "resolved",
          "issue_count" => 0
        }
      )

    current =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-2",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 2
        }
      )

    summary =
      ActivityEventSummary.build(
        [current, previous],
        "dashboard-lifecycle-event-readiness-2",
        [current, previous],
        %{filter_value: "publish_readiness"}
      )

    assert summary.readiness_comparison.state == "regressed"
    assert summary.readiness_comparison.message == "Readiness regressed: 0 issues -> 2 issues."
  end

  test "build exposes publish readiness remediation actions for selected events" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        payload: %{
          "remediation_targets" => [
            %{
              "issue_id" => "error:unready_publish_source_request:placement-ground-state",
              "label" => "Use a compatible source",
              "target" => "data_sources",
              "message" => "Open Data Sources and choose a compatible source.",
              "params" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "unsupported_source_capability"
              }
            }
          ]
        }
      )

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-readiness",
        [event],
        %{filter_value: "publish_readiness"}
      )

    assert summary.remediation_actions == [
             %{
               issue_id: "error:unready_publish_source_request:placement-ground-state",
               label: "Use a compatible source",
               target: "data_sources",
               message: "Open Data Sources and choose a compatible source.",
               params: %{
                 "data_source_id" => "rehearsal-source",
                 "source_binding_id" => "rehearsal-binding",
                 "source_empty_reason" => "unsupported_source_capability"
               }
             }
           ]
  end

  test "build correlates selected publish readiness checks to returned source actions" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-24 12:00:00Z],
        payload: %{"result" => "still_blocked", "issue_count" => 1}
      )

    source_health_event =
      SourceHealthEvent.new(%{
        source_health_event_id: "source-health-event-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: "telemetry",
        data_source_id: "rehearsal-source",
        source_binding_id: "rehearsal-binding",
        source_health: :healthy,
        observed_at: ~U[2026-06-24 12:05:00Z],
        payload: %{
          "source_dashboard_id" => "dashboard-1",
          "source_return_activity_event" => "dashboard-lifecycle-event-readiness"
        }
      })

    binding_event =
      DataBindingEvent.new(%{
        data_binding_event_id: "data-binding-event-1",
        binding_id: "rehearsal-binding",
        organization_id: "org-1",
        mission_id: "mission-1",
        event_type: :changed,
        current_status: :active,
        current_binding_version: 2,
        current_logical_source: "telemetry",
        current_realm: "flight",
        current_data_source_id: "rehearsal-source-2",
        current_priority: 0,
        occurred_at: ~U[2026-06-24 12:07:00Z],
        payload: %{
          "source_dashboard_id" => "dashboard-1",
          "source_return_activity_event" => "dashboard-lifecycle-event-readiness"
        }
      })

    stale_source_event =
      DataSourceEvent.new(%{
        data_source_event_id: "data-source-event-stale",
        data_source_id: "rehearsal-source",
        organization_id: "org-1",
        mission_id: "mission-1",
        event_type: :changed,
        current_status: :active,
        current_owner: "ops",
        current_kind: "questdb",
        current_isolation_level: "mission",
        occurred_at: ~U[2026-06-24 11:55:00Z],
        payload: %{
          "source_dashboard_id" => "dashboard-1",
          "source_return_activity_event" => "dashboard-lifecycle-event-readiness"
        }
      })

    unrelated_source_event =
      DataSourceEvent.new(%{
        data_source_event_id: "data-source-event-unrelated",
        data_source_id: "other-source",
        organization_id: "org-1",
        mission_id: "mission-1",
        event_type: :changed,
        current_status: :active,
        current_owner: "ops",
        current_kind: "questdb",
        current_isolation_level: "mission",
        occurred_at: ~U[2026-06-24 12:10:00Z],
        payload: %{
          "source_dashboard_id" => "dashboard-1",
          "source_return_activity_event" => "other-readiness-event"
        }
      })

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-readiness",
        [event],
        %{filter_value: "publish_readiness"},
        [],
        [source_health_event, binding_event, stale_source_event, unrelated_source_event]
      )

    assert summary.source_actions.count == 2
    assert summary.source_actions.count_text == "2"
    assert summary.source_actions.latest.kind == "source_binding"
    assert summary.source_actions.latest.message == "Source binding updated after this check"
    assert summary.source_actions.latest.occurred_at == "2026-06-24 12:07:00 UTC"

    assert Enum.map(summary.source_actions.rows, & &1.kind) == [
             "source_binding",
             "source_health"
           ]

    assert %{
             label: "Source follow-up",
             value: "Source binding updated at 2026-06-24 12:07:00 UTC"
           } in Enum.map(
             summary.fields,
             &Map.take(&1, [:label, :value])
           )
  end
end
