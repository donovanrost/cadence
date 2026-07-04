defmodule CadenceWeb.OpsDashboardShowLive.ActivityEventSummaryTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{DataBindingEvent, DataSourceEvent, SourceHealthEvent}
  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary

  test "build returns no rendered summary without a selected event id" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :published)

    assert %{
             render?: false,
             runtime_impact: %{state: "not_applicable"}
           } = ActivityEventSummary.build([event], nil, [event], %{filter_value: ""})

    assert %{
             render?: false,
             runtime_impact: %{state: "not_applicable"}
           } = ActivityEventSummary.build([event], "", [event], %{filter_value: ""})
  end

  test "build summarizes a visible selected lifecycle event" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-1",
        :reverted,
        actor_id: "operator-1",
        dashboard_version: 7,
        occurred_at: ~U[2026-06-24 12:03:00Z],
        payload: %{
          "source_version" => 5,
          "reverted_version" => 8
        }
      )
      |> Map.put(:previous_published_version, 5)
      |> Map.put(:current_published_version, 6)

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-1",
        [event],
        %{filter_value: "version_changes"}
      )

    assert %{
             render?: true,
             event: ^event,
             event_id: "dashboard-lifecycle-event-1",
             found?: true,
             found_text: "true",
             visible?: true,
             visible_text: "true",
             filter_value: "version_changes",
             event_type_text: "reverted",
             title: "Restored as draft",
             version_text: "v7",
             filter_state: nil,
             filter_state_text: nil,
             visibility_class: nil
           } = summary

    assert [
             %{label: "Event", value: "dashboard-lifecycle-event-1"},
             %{label: "Occurred", value: "2026-06-24 12:03:00 UTC"},
             %{label: "Actor", value: "operator-1"},
             %{label: "Published", value: "v5 -> v6"},
             %{label: "Source", value: "v5"},
             %{label: "New draft", value: "v8"},
             %{label: "Runtime", value: "No runtime invalidation observed"}
           ] = Enum.map(summary.fields, &Map.take(&1, [:label, :value]))
  end

  test "build marks selected events hidden when filtered out" do
    selected_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    visible_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    summary =
      ActivityEventSummary.build(
        [selected_event, visible_event],
        "dashboard-lifecycle-event-published",
        [visible_event],
        %{filter_value: "health_snapshots"}
      )

    assert summary.found? == true
    assert summary.found_text == "true"
    assert summary.visible? == false
    assert summary.visible_text == "false"
    assert summary.event_type_text == "published"
    assert summary.title == "Published"
    assert summary.filter_state == :hidden
    assert summary.filter_state_text == "hidden"
    assert summary.visibility_class == "border-warning/40 bg-warning/10"
  end

  test "build correlates selected lifecycle events to runtime invalidations" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        dashboard_version: 3
      )

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-published",
        [event],
        %{filter_value: "version_changes"},
        [
          %{
            id: "invalidation-1",
            lifecycle_action: "published",
            document_version: "3",
            source_version: "-",
            context_match: "true",
            refresh_allowed: "true",
            refresh_action: "refresh_plan",
            context_reason_label: "matched",
            refresh_allowed_reason_label: "refresh allowed"
          }
        ]
      )

    assert summary.runtime_impact == %{
             state: "refresh_allowed",
             label: "Runtime refresh allowed: refresh_plan",
             invalidation_id: "invalidation-1",
             context_match: "true",
             refresh_allowed: "true",
             refresh_action: "refresh_plan",
             context_reason: "matched",
             refresh_reason: "refresh allowed"
           }

    assert %{label: "Runtime", value: "Runtime refresh allowed: refresh_plan"} in Enum.map(
             summary.fields,
             &Map.take(&1, [:label, :value])
           )
  end

  test "build marks missing selected events unavailable" do
    event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    summary =
      ActivityEventSummary.build(
        [event],
        "dashboard-lifecycle-event-missing",
        [event],
        %{filter_value: ""}
      )

    assert summary.event == nil
    assert summary.found? == false
    assert summary.found_text == "false"
    assert summary.visible? == false
    assert summary.visible_text == "false"
    assert summary.event_type_text == nil
    assert summary.title == "Activity event unavailable"
    assert summary.version_text == nil
    assert summary.filter_state == :missing
    assert summary.filter_state_text == "missing"
    assert summary.visibility_class == "border-error/40 bg-error/10"
    assert summary.fields == []
  end

  test "rows summarize visible activity events for list rendering" do
    selected_event =
      lifecycle_event(
        "dashboard-lifecycle-event-selected",
        :reverted,
        dashboard_version: 9,
        actor_id: "operator-1",
        occurred_at: ~U[2026-06-24 12:04:00Z],
        payload: %{
          "source_version" => 7,
          "reverted_version" => 10
        }
      )
      |> Map.put(:previous_published_version, 6)
      |> Map.put(:current_published_version, 7)

    other_event =
      lifecycle_event(
        "dashboard-lifecycle-event-other",
        :health_snapshot_captured,
        dashboard_version: 8
      )

    [selected_row, other_row] =
      ActivityEventSummary.rows(
        [selected_event, other_event],
        "dashboard-lifecycle-event-selected"
      )

    assert %{
             event: ^selected_event,
             event_id: "dashboard-lifecycle-event-selected",
             event_type: :reverted,
             event_type_text: "reverted",
             title: "Restored as draft",
             version_text: "v9",
             selected?: true,
             selected_text: "true",
             source_version_text: "7",
             reverted_version_text: "10",
             class: ["border-l-2 bg-base-100/40 px-2 py-2", "border-info bg-info/10"]
           } = selected_row

    assert [
             %{label: "Occurred", value: "2026-06-24 12:04:00 UTC"},
             %{label: "Actor", value: "operator-1"},
             %{label: "Published", value: "v6 -> v7"},
             %{label: "Source", value: "v7"},
             %{label: "New draft", value: "v10"},
             %{label: "Runtime", value: "No runtime invalidation observed"}
           ] = Enum.map(selected_row.fields, &Map.take(&1, [:label, :value]))

    assert other_row.selected? == false
    assert other_row.selected_text == "false"
    assert other_row.class == ["border-l-2 bg-base-100/40 px-2 py-2", "border-primary/60"]
  end

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

  test "rows report filtered or missing runtime invalidation impact for lifecycle events" do
    reverted =
      lifecycle_event(
        "dashboard-lifecycle-event-reverted",
        :reverted,
        dashboard_version: 9,
        payload: %{"source_version" => 7}
      )

    [row] =
      ActivityEventSummary.rows(
        [reverted],
        nil,
        [
          %{
            id: "invalidation-revert",
            lifecycle_action: "reverted",
            document_version: "9",
            source_version: "7",
            context_match: "false",
            refresh_allowed: "false",
            refresh_action: "refresh_plan",
            context_reason_label: "filtered by realm",
            refresh_allowed_reason_label: "stale before current context"
          }
        ]
      )

    assert row.runtime_impact == %{
             state: "context_filtered",
             label: "Runtime invalidation filtered: filtered by realm",
             invalidation_id: "invalidation-revert",
             context_match: "false",
             refresh_allowed: "false",
             refresh_action: "refresh_plan",
             context_reason: "filtered by realm",
             refresh_reason: "stale before current context"
           }

    [missing_row] = ActivityEventSummary.rows([reverted], nil, [])

    assert missing_row.runtime_impact.state == "not_observed"
    assert missing_row.runtime_impact.label == "No runtime invalidation observed"
  end

  test "label exposes lifecycle event display names" do
    assert ActivityEventSummary.label(:comparison_review_requested) ==
             "Comparison review requested"

    assert ActivityEventSummary.label(:health_snapshot_captured) == "Health snapshot captured"
    assert ActivityEventSummary.label(:publish_readiness_checked) == "Publish readiness checked"
  end
end
