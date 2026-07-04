defmodule CadenceWeb.OpsDashboardShowLive.ComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataBinding, InvestigationPreset, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.Components

  test "dashboard toolbar exposes mission scope alongside spacecraft context search" do
    html =
      render_component(&Components.dashboard_toolbar/1,
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        edit_mode?: false,
        show_context?: true,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [
          %{spacecraft_id: "spacecraft-1", display_name: "Alpha", scid: 101}
        ],
        context_spacecraft_id: nil,
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        selected_data_ref: nil,
        query: "lunar"
      )

    document = LazyHTML.from_fragment(html)

    assert ["mission"] =
             document
             |> LazyHTML.query(~s(button[phx-value-scope-kind="mission"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["mission-1"] =
             document
             |> LazyHTML.query(~s(button[phx-value-scope-kind="mission"]))
             |> LazyHTML.attribute("phx-value-scope-id")

    assert html =~ "Lunar Demo"
    assert html =~ "Find mission, spacecraft, contact, source, transport, ground, or link"

    assert ["open_versions"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("phx-click")
  end

  test "dashboard toolbar exposes scheduled and realized contacts as runtime contexts" do
    html =
      render_component(&Components.dashboard_toolbar/1,
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        edit_mode?: false,
        show_context?: true,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [],
        scheduled_contacts: [
          %{
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        realized_contacts: [
          %{
            realized_contact_id: "contact-realized-1",
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        context_spacecraft_id: nil,
        context_scope_kind: "contact",
        context_scope_id: "contact-realized-1",
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        selected_data_ref: nil,
        query: "gs-alpha"
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "realized / contact-realized-1 / gs-alpha"

    assert ["contact"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["contact-scheduled-1"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["scheduled"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("data-dashboard-context-contact-kind")

    assert ["contact-realized-1"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-contact-kind="realized"]))
             |> LazyHTML.attribute("phx-value-scope-id")
  end

  test "dashboard toolbar exposes unsupported limit mode fallback" do
    html =
      render_component(&Components.dashboard_toolbar/1,
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        edit_mode?: false,
        show_context?: false,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [],
        context_spacecraft_id: nil,
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        time_mode: "archive",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        selected_data_ref: nil,
        query: ""
      )

    document = LazyHTML.from_fragment(html)

    assert ["projected"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-requested-limit-mode")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-applied-limit-mode")

    assert ["unsupported_limit_semantics_mode"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-limit-mode-fallback-reason")

    assert ["Requested projected limit semantics; using observed."] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("title")
  end

  test "dashboard warnings expose selected clock and missing limit samples" do
    html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: true,
        warnings: [
          %{
            code: :incomplete_limit_evaluation,
            code_text: "incomplete_limit_evaluation",
            severity: :warning,
            severity_text: "warning",
            label: "Incomplete limit analysis",
            message:
              "Some telemetry samples have no active complete limit definition for recomputation",
            details: %{
              selected_limit_clock: %{
                observed: :limit_event_receipt_time,
                requested_time_axis: :receipt_time,
                requested_time_mode: "archive"
              },
              missing_sample_ids: ["sample-missing"],
              requested_semantics_mode: :recomputed
            },
            detail_rows: [
              %{label: "Selected clock", value: "observed=limit_event_receipt_time"},
              %{label: "Missing samples", value: "sample-missing"}
            ],
            evidence: [],
            links: [],
            actions: []
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["incomplete_limit_evaluation"] =
             document
             |> LazyHTML.query("#dashboard-engine-warnings")
             |> LazyHTML.attribute("data-warning-codes")

    warning =
      LazyHTML.query(document, ~s([data-engine-warning-detail="incomplete_limit_evaluation"]))

    assert [
             "observed=limit_event_receipt_time requested_time_axis=receipt_time requested_time_mode=archive"
           ] = LazyHTML.attribute(warning, "data-limit-selected-clock")

    assert ["sample-missing"] = LazyHTML.attribute(warning, "data-limit-missing-samples")
    assert ["recomputed"] = LazyHTML.attribute(warning, "data-limit-mode")

    assert ["Selected clock"] =
             document
             |> LazyHTML.query(~s([data-warning-detail="Selected clock"]))
             |> LazyHTML.attribute("data-warning-detail")
  end

  test "dashboard toolbar surfaces open comparison review work on versions button" do
    lifecycle_events = [
      comparison_review_request_event(
        event_id: "review-request-1",
        placement_ids: ["placement-1", "placement-2"]
      ),
      comparison_review_request_event(
        event_id: "review-request-2",
        payload: %{
          "open_findings" => %{
            "findings" => [%{"placement_id" => "placement-3"}]
          }
        }
      ),
      comparison_review_resolution_event(
        event_id: "review-resolution-2",
        source_request_event_id: "review-request-2"
      )
    ]

    html =
      render_component(&Components.dashboard_toolbar/1,
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        edit_mode?: false,
        show_context?: false,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [],
        context_spacecraft_id: nil,
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        selected_data_ref: nil,
        query: ""
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["open_review_activity"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("phx-click")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-placements")

    assert [_class] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-toolbar-badge]")
             |> LazyHTML.attribute("class")
  end

  test "source selection strip exposes selected and skipped source candidates" do
    html =
      render_component(&Components.source_selection_strip/1,
        mission_id: "mission-1",
        selections: [
          %{
            request_id: "req-telemetry",
            logical_source_text: "Telemetry",
            strategy_text: "current_binding",
            selected_binding_id: "secondary-flight",
            selected_data_source_id: "secondary-questdb",
            selected_dataset: "flight",
            requested_realm: "flight",
            candidate_count: 2,
            eligible_candidate_count: 1,
            rejected_candidate_count: 1,
            state: :selected,
            state_text: "selected",
            candidates: [
              %{
                binding_id: "primary-flight",
                data_source_id: "primary-questdb",
                decision: :rejected,
                decision_text: "rejected",
                reasons_text: "source_unavailable",
                source_health_text: "unavailable",
                source_health_freshness_text: "fresh",
                inventory_query: %{
                  "data_source_id" => "primary-questdb",
                  "logical_source" => "telemetry",
                  "realm" => "flight",
                  "source_binding_id" => "primary-flight"
                },
                inventory_action_label: "Open source inventory"
              },
              %{
                binding_id: "secondary-flight",
                data_source_id: "secondary-questdb",
                decision: :selected,
                decision_text: "selected",
                reasons_text: "",
                source_health_text: "",
                source_health_freshness_text: "",
                inventory_query: %{
                  "data_source_id" => "secondary-questdb",
                  "logical_source" => "telemetry",
                  "realm" => "flight",
                  "source_binding_id" => "secondary-flight"
                },
                inventory_action_label: "Open source inventory"
              }
            ]
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-requests")

    assert ["req-telemetry"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-request-ids")

    assert ["secondary-flight"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-bindings")

    assert ["secondary-questdb"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-data-sources")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-source-selection")
             |> LazyHTML.attribute("data-source-selection-rejected")

    assert ["selected"] =
             document
             |> LazyHTML.query(~s(summary[data-source-selection="req-telemetry"]))
             |> LazyHTML.attribute("data-source-selection-state")

    assert ["primary-questdb"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-source")

    assert ["rejected"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-decision")

    assert ["source_unavailable"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-reasons")

    assert ["source_inventory"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-action")

    assert [
             "data_source_id=primary-questdb&logical_source=telemetry&realm=flight&source_binding_id=primary-flight"
           ] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="primary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-action-query")

    assert [primary_href] =
             document
             |> LazyHTML.query(~s(a[data-source-selection-candidate-open="primary-flight"]))
             |> LazyHTML.attribute("href")

    assert primary_href =~ "/missions/mission-1/ops/data-sources?"
    assert primary_href =~ "data_source_id=primary-questdb"
    assert primary_href =~ "source_binding_id=primary-flight"

    assert ["selected"] =
             document
             |> LazyHTML.query(~s([data-source-selection-candidate="secondary-flight"]))
             |> LazyHTML.attribute("data-source-selection-candidate-decision")
  end

  test "dashboard health strip summarizes affected widget groups" do
    snapshot_id = "dashboard_health_snapshot_abc123"

    html =
      render_component(&Components.dashboard_health_strip/1,
        health: %{
          visible?: true,
          snapshot_schema: "dashboard_health_snapshot.v1",
          snapshot_id: snapshot_id,
          snapshot: %{
            "schema" => "dashboard_health_snapshot.v1",
            "snapshot_id" => snapshot_id,
            "dashboard_id" => "dashboard-1",
            "state" => "blocked",
            "counts" => %{
              "widgets" => 3,
              "ready" => 1,
              "degraded" => 1,
              "stale" => 0,
              "blocked" => 1,
              "affected" => 2
            },
            "placement_ids" => %{
              "affected" => ["blocked-placement", "degraded-placement"],
              "blocked" => ["blocked-placement"],
              "stale" => [],
              "degraded" => ["degraded-placement"]
            }
          },
          state: :blocked,
          state_text: "blocked",
          label: "Blocked",
          severity: :error,
          severity_text: "error",
          widget_count: 3,
          ready_count: 1,
          degraded_count: 1,
          stale_count: 0,
          blocked_count: 1,
          affected_count: 2,
          states: "ready,degraded,blocked",
          affected_placements: "blocked-placement,degraded-placement",
          blocked_placements: "blocked-placement",
          stale_placements: "",
          degraded_placements: "degraded-placement",
          groups: [
            %{
              key: "blocked",
              state: :blocked,
              label: "Blocked",
              count: 1,
              placement_ids: "blocked-placement",
              items: [
                %{
                  placement_id: "blocked-placement",
                  title: "Blocked widget",
                  state_text: "blocked",
                  lifecycle_state_text: "ready",
                  source_state_text: "unavailable",
                  warning_codes_text: "",
                  reason: "source_unavailable"
                }
              ]
            },
            %{
              key: "degraded",
              state: :degraded,
              label: "Degraded",
              count: 1,
              placement_ids: "degraded-placement",
              items: [
                %{
                  placement_id: "degraded-placement",
                  title: "No data widget",
                  state_text: "degraded",
                  lifecycle_state_text: "no_data",
                  source_state_text: "no_data",
                  warning_codes_text: "",
                  reason: "lifecycle_no_data"
                }
              ]
            }
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert ["blocked"] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-state")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-health-rollup")
             |> LazyHTML.attribute("data-dashboard-health-affected")

    assert ["blocked-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-group="blocked"]))
             |> LazyHTML.attribute("data-dashboard-health-group-placements")

    assert ["#widget-blocked-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-item="blocked-placement"]))
             |> LazyHTML.attribute("href")

    assert ["source_unavailable"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-item="blocked-placement"]))
             |> LazyHTML.attribute("data-dashboard-health-item-reason")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-click")

    assert ["dashboard_health"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-schema")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-snapshot-id")

    assert ["blocked"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-state")

    assert ["blocked-placement,degraded-placement"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-evidence-open]))
             |> LazyHTML.attribute("phx-value-dashboard-health-affected-placements")

    assert ["ClipboardButton"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("phx-hook")

    assert ["dashboard_health_snapshot.v1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-schema")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert [snapshot_json] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-copy]))
             |> LazyHTML.attribute("data-clipboard-text")

    assert Jason.decode!(snapshot_json) == %{
             "schema" => "dashboard_health_snapshot.v1",
             "snapshot_id" => snapshot_id,
             "dashboard_id" => "dashboard-1",
             "state" => "blocked",
             "counts" => %{
               "widgets" => 3,
               "ready" => 1,
               "degraded" => 1,
               "stale" => 0,
               "blocked" => 1,
               "affected" => 2
             },
             "placement_ids" => %{
               "affected" => ["blocked-placement", "degraded-placement"],
               "blocked" => ["blocked-placement"],
               "stale" => [],
               "degraded" => ["degraded-placement"]
             }
           }

    assert ["capture_dashboard_health_snapshot"] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("phx-click")

    assert [^snapshot_id] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert [capture_snapshot_json] =
             document
             |> LazyHTML.query(~s([data-dashboard-health-snapshot-capture]))
             |> LazyHTML.attribute("phx-value-snapshot")

    assert Jason.decode!(capture_snapshot_json) == Jason.decode!(snapshot_json)
  end

  test "comparison rollup strip summarizes dashboard-level compare state" do
    preset = %{
      "schema" => "dashboard_comparison_investigation_preset.v1",
      "dashboard_id" => "dashboard-1",
      "current_path" =>
        "/missions/mission-1/ops/dashboards/dashboard-1?data_view=all_revisions&compare_data_view=canonical",
      "comparison" => %{
        "primary_data_view" => "all_revisions",
        "compare_data_view" => "canonical",
        "delta_count" => 1,
        "open_count" => 1
      },
      "runtime_query" => %{
        "data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      },
      "workflow_groups" => [
        %{
          "key" => "open",
          "label" => "Open findings",
          "count" => 1,
          "placement_ids" => ["placement-2"],
          "items" => [
            %{
              "placement_id" => "placement-2",
              "widget_id" => "widget-2",
              "title" => "Current",
              "state" => "missing",
              "label" => "No compare data",
              "decision_status" => "unhandled"
            }
          ]
        }
      ]
    }

    html =
      render_component(&Components.comparison_rollup_strip/1,
        rollup: %{
          visible?: true,
          widget_count: 4,
          delta_count: 1,
          unchanged_count: 1,
          coverage_count: 1,
          missing_count: 1,
          handled_count: 1,
          open_count: 1,
          unhandled_count: 1,
          states: "increased,unchanged,available,missing",
          workflow_groups: [
            %{
              key: "open",
              label: "Open findings",
              count: 1,
              placement_ids: "placement-2",
              items: [
                %{
                  placement_id: "placement-2",
                  widget_id: "widget-2",
                  title: "Current",
                  state: "missing",
                  label: "No compare data",
                  decision_status: "unhandled"
                }
              ]
            },
            %{
              key: "handled",
              label: "Handled findings",
              count: 1,
              placement_ids: "placement-1",
              items: [
                %{
                  placement_id: "placement-1",
                  widget_id: "widget-1",
                  title: "Voltage",
                  state: "increased",
                  label: "Canonical +2",
                  decision_status: "applied",
                  decision_event_id: "decision-event-1"
                }
              ]
            }
          ],
          groups: [
            %{
              key: "deltas",
              label: "Deltas",
              count: 1,
              handled_count: 1,
              unhandled_count: 0,
              placement_ids: "placement-1",
              items: [
                %{
                  placement_id: "placement-1",
                  widget_id: "widget-1",
                  title: "Voltage",
                  state: "increased",
                  label: "Canonical +2",
                  detail: "All revisions compared with Canonical",
                  primary_view: "all_revisions",
                  compare_view: "canonical",
                  primary_count: 1,
                  compare_count: 1,
                  delta: "+2",
                  handled?: true,
                  decision_status: "applied",
                  decision_event_id: "decision-event-1",
                  decision: "mark_conflict",
                  decision_reason: "operator_confirmed_comparison",
                  primary_sample_id: "primary-sample-1",
                  compare_sample_id: "compare-sample-1",
                  primary_data_link: presented_link(),
                  compare_data_link: %{
                    presented_link()
                    | link_id: "compare-link-1",
                      target_id: "compare-sample-1",
                      context: %{
                        data: %{
                          realm: :simulation,
                          view: "canonical",
                          data_source_id: "questdb-sim",
                          source_binding_id: "binding-sim"
                        },
                        time: %{mode: "replay_run", axis: "generation_time"}
                      }
                  }
                }
              ]
            },
            %{
              key: "missing",
              label: "Missing compare data",
              count: 1,
              placement_ids: "placement-2",
              items: [
                %{
                  placement_id: "placement-2",
                  widget_id: "widget-2",
                  title: "Current",
                  state: "missing",
                  label: "No compare data",
                  detail: "Canonical returned no comparable widget data."
                }
              ]
            }
          ]
        },
        preset: preset,
        saved_presets: [
          InvestigationPreset.new(%{
            dashboard_investigation_preset_id: "preset-1",
            mission_id: "mission-1",
            dashboard_id: "dashboard-1",
            name: "All revisions vs canonical",
            schema: "dashboard_comparison_investigation_preset.v1",
            preset_kind: :comparison,
            runtime_query: %{
              "data_view" => "all_revisions",
              "compare_data_view" => "canonical"
            },
            primary_data_view: "all_revisions",
            compare_data_view: "canonical",
            affected_placement_ids: ["placement-1"]
          })
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["4"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-widgets")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-deltas")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-handled")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open")

    assert ["placement-2"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-placements")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-handled-placements")

    assert ["0"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-group="deltas"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-group-unhandled")

    assert ["open", "handled"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-workflow-badge]")
             |> LazyHTML.attribute("data-dashboard-comparison-workflow-badge")

    assert ["open", "handled"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-workflow-group]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-workflow-group")

    assert ["placement-2", "placement-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-workflow-item]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-workflow-item")

    assert ["deltas", "unchanged", "coverage", "missing"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-badge]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-badge")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-badge="deltas"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-placements")

    assert ["deltas", "missing"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-group]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-group")

    assert ["placement-1", "placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-item]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-item")

    assert ["#widget-placement-1", "#widget-placement-2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-item] a")
             |> LazyHTML.attribute("href")

    assert ["primary-sample-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-primary-sample")

    assert ["compare-sample-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-compare-sample")

    assert ["applied"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-decision-status")

    assert ["decision-event-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-decision-event")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handled="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-handled")

    assert ["telemetry_revision_decision_event"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["decision-event-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-decision-link="placement-1"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["link-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-primary-link")

    assert ["compare-link-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-item="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-compare-link")

    assert ["primary", "compare"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-rollup-link]")
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-link")

    assert ["placement-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("data-dashboard-comparison-rollup-handoff")

    assert ["comparison_finding"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-target")

    assert ["primary-sample-1"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-primary-sample-id")

    assert ["canonical"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-handoff="placement-1"]))
             |> LazyHTML.attribute("phx-value-compare-data-view")

    assert ["flight"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-link="primary"]))
             |> LazyHTML.attribute("phx-value-realm")

    assert ["questdb-sim"] =
             document
             |> LazyHTML.query(~s([data-dashboard-comparison-rollup-link="compare"]))
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert [encoded_preset] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-preset")

    assert %{
             "schema" => "dashboard_comparison_investigation_preset.v1",
             "comparison" => %{"compare_data_view" => "canonical"}
           } = Jason.decode!(encoded_preset)

    assert [encoded_open_findings] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open-findings")

    assert %{
             "schema" => "dashboard_comparison_open_findings.v1",
             "source_schema" => "dashboard_comparison_investigation_preset.v1",
             "comparison" => %{"open_count" => 1, "open_placement_ids" => ["placement-2"]},
             "findings" => [
               %{
                 "placement_id" => "placement-2",
                 "decision_status" => "unhandled"
               }
             ]
           } = Jason.decode!(encoded_open_findings)

    assert [^encoded_open_findings] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-copy")
             |> LazyHTML.attribute("data-clipboard-text")

    assert ["request_comparison_review"] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review-form")
             |> LazyHTML.attribute("phx-submit")

    assert [^encoded_open_findings] =
             document
             |> LazyHTML.query("#dashboard-comparison-open-findings-review-payload")
             |> LazyHTML.attribute("value")

    assert [
             "/missions/mission-1/ops/dashboards/dashboard-1?data_view=all_revisions&compare_data_view=canonical"
           ] =
             document
             |> LazyHTML.query("#dashboard-comparison-preset-copy")
             |> LazyHTML.attribute("data-clipboard-text")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-presets")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset")

    assert ["All revisions vs canonical"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset-name")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-apply]")
             |> LazyHTML.attribute("phx-value-preset-id")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-delete]")
             |> LazyHTML.attribute("phx-value-preset-id")

    assert html =~ "Compare"
    assert html =~ "4 widgets"
  end

  test "comparison rollup strip is hidden when no comparison is active" do
    html =
      render_component(&Components.comparison_rollup_strip/1,
        rollup: %{
          visible?: false,
          widget_count: 0,
          delta_count: 0,
          unchanged_count: 0,
          coverage_count: 0,
          missing_count: 0,
          states: ""
        }
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("id")
  end

  test "widget header exposes stable lifecycle attributes and badges" do
    for {state, severity, label} <- [
          {:no_data, :info, "No Data"},
          {:stale, :warning, "Stale"},
          {:partial, :warning, "Partial"},
          {:retention_gap, :error, "Retention Gap"},
          {:error, :error, "Source Error"},
          {:unsupported, :error, "Unsupported"}
        ] do
      html =
        render_component(&Components.widget/1,
          widget: value_tile(),
          placement_id: "placement-1",
          data: lifecycle_point_data(state),
          compare_data: nil,
          point: %{unit: "V"},
          spacecraft: [],
          backfill: nil,
          limit_markers: [],
          event_markers: [],
          selected_data_ref: nil,
          context_spacecraft_id: "spacecraft-1",
          chart_epoch: 1,
          edit_mode?: false,
          warnings: []
        )

      document = LazyHTML.from_fragment(html)
      selector = ~s([data-widget-lifecycle-state="#{state}"])
      expected_severity = Atom.to_string(severity)
      expected_state = Atom.to_string(state)

      assert [^expected_severity] =
               document
               |> LazyHTML.query(selector)
               |> LazyHTML.attribute("data-widget-lifecycle-severity")

      assert [^expected_state] =
               document
               |> LazyHTML.query(selector)
               |> LazyHTML.attribute("data-widget-lifecycle-reasons")

      assert html =~ label
    end
  end

  test "widget unsupported notice explains selected context mismatch" do
    data =
      :unsupported
      |> lifecycle_point_data()
      |> put_in([:lifecycle, :warning_codes], [:unsupported_observable_scope])

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    assert html =~ "This widget does not support the selected context."

    document = LazyHTML.from_fragment(html)

    assert ["unsupported"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")
  end

  test "widget header exposes stable source status attributes" do
    data =
      :stale
      |> lifecycle_point_data()
      |> Map.put(:source_status, %{
        state: :stale,
        severity: :warning,
        data_state: :ready,
        stale?: true,
        warning_codes: [:stale_data],
        freshness_states: [:stale],
        confidences: [:best_effort],
        logical_sources: [:telemetry],
        source_request_ids: ["source-req-1"],
        data_source_ids: ["questdb-flight"],
        source_binding_ids: ["binding-flight"],
        realms: [:flight],
        time_modes: [:archive],
        time_axes: [:receipt_time],
        replay_run_ids: ["replay-1"],
        scope_kinds: [:spacecraft],
        scope_ids: ["spacecraft-1"],
        contact_ids: ["contact-1"],
        source_endpoint_ids: ["endpoint-1"],
        empty_reason: :contact_scope_no_data
      })

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        mission_id: "mission-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        data_view: "all_revisions",
        compare_data_view: "canonical",
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)
    selector = ~s([data-widget-source-state="stale"])

    assert ["warning"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-severity")

    assert ["ready"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-data-state")

    assert ["true"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-stale")

    assert ["stale_data"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-warning-codes")

    assert ["telemetry"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-logical-sources")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-data-source-ids")

    assert ["archive"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-time-modes")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-time-axes")

    assert ["spacecraft"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-scope-kinds")

    assert ["contact-1"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-contact-ids")

    assert ["endpoint-1"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-source-endpoint-ids")

    assert ["contact_scope_no_data"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("data-widget-source-empty-reason")

    assert ["Source stale"] =
             document
             |> LazyHTML.query(~s([data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-label")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-compare-data-view")

    assert ["telemetry"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-binding-source")

    assert ["fixed"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-binding-mode")

    assert ["HK.voltage"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-observables")

    assert ["stale"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-source-state")

    assert ["source-req-1"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-source-request-ids")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-data-source-ids")

    assert ["archive"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-time-modes")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query(~s([data-widget-query-diagnostics]))
             |> LazyHTML.attribute("data-widget-query-time-axes")

    assert "archive/receipt_time" =
             document
             |> LazyHTML.query(~s([data-widget-query-value="time"]))
             |> LazyHTML.text()
             |> String.trim()

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-widget-query-value="data_sources"]))
             |> LazyHTML.text()
             |> String.trim()

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-click")

    assert ["query"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["Voltage"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-widget-title")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-requested-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-compare-data-view")

    assert ["HK.voltage"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-observables")

    assert ["stale"] =
             document
             |> LazyHTML.query(~s([data-widget-query-evidence-open]))
             |> LazyHTML.attribute("phx-value-source-evidence-state")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-click")

    assert ["source_inventory"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-action")

    assert [inventory_query] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-query")

    assert inventory_query =~ "contact_id=contact-1"
    assert inventory_query =~ "data_source_id=questdb-flight"
    assert inventory_query =~ "source_binding_id=binding-flight"
    assert inventory_query =~ "source_endpoint_id=endpoint-1"

    assert [badge_inventory_href] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-inventory-href")

    assert badge_inventory_href =~ "/missions/mission-1/ops/data-sources?"
    assert badge_inventory_href =~ "contact_id=contact-1"
    assert badge_inventory_href =~ "data_source_id=questdb-flight"
    assert badge_inventory_href =~ "source_binding_id=binding-flight"
    assert badge_inventory_href =~ "source_endpoint_id=endpoint-1"

    assert [inventory_href] =
             document
             |> LazyHTML.query(~s(a[data-widget-source-badge-inventory-open="stale"]))
             |> LazyHTML.attribute("href")

    assert inventory_href == badge_inventory_href

    assert ["source"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-kind")

    assert ["health"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-source-evidence-mode")

    assert ["stale"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-source-evidence-state")

    assert ["source-req-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-source-request-id")

    assert ["contact-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-contact-id")

    assert ["endpoint-1"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-source-endpoint-id")

    assert ["contact_scope_no_data"] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("phx-value-source-empty-reason")

    assert ["telemetry"] =
             document
             |> LazyHTML.query(~s([data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-source")

    assert ["endpoint-1"] =
             document
             |> LazyHTML.query(~s([data-widget-source-badge="stale"]))
             |> LazyHTML.attribute("data-widget-source-badge-source-endpoint-id")

    assert html =~ "Source stale"
  end

  test "widget header keeps source status badge passive without source evidence context" do
    data =
      :no_data
      |> lifecycle_point_data()
      |> Map.put(:source_status, %{
        state: :no_data,
        severity: :info,
        data_state: :no_data,
        stale?: false,
        warning_codes: []
      })

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["none"] =
             document
             |> LazyHTML.query(~s(span[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("data-widget-source-badge-action")

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="no_data"]))
             |> LazyHTML.attribute("phx-click")
  end

  test "widget source status attributes do not serialize nil empty reason" do
    data =
      :error
      |> lifecycle_point_data()
      |> Map.put(:source_status, %{
        state: :unavailable,
        severity: :error,
        data_state: :no_data,
        stale?: false,
        warning_codes: [:source_unavailable],
        logical_sources: [:telemetry],
        source_request_ids: ["source-req-1"],
        data_source_ids: ["questdb-flight"],
        source_binding_ids: ["binding-flight"],
        scope_kinds: [:spacecraft],
        scope_ids: ["spacecraft-1"],
        empty_reason: nil
      })

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        mission_id: "mission-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert [""] =
             document
             |> LazyHTML.query(~s([data-widget-source-state="unavailable"]))
             |> LazyHTML.attribute("data-widget-source-empty-reason")

    refute ["nil"] ==
             document
             |> LazyHTML.query(~s(button[data-widget-source-badge="unavailable"]))
             |> LazyHTML.attribute("phx-value-source-empty-reason")
  end

  test "widget header suppresses source status badge for fresh source status" do
    data =
      42
      |> point_data()
      |> Map.put(:source_status, %{
        state: :fresh,
        severity: :ok,
        data_state: :ready,
        stale?: false,
        warning_codes: [],
        logical_sources: [:telemetry]
      })

    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: data,
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-widget-source-badge]")
             |> LazyHTML.attribute("data-widget-source-badge")
  end

  test "time series source failure renders a body notice instead of an empty chart" do
    html =
      render_component(&Components.widget/1,
        widget: time_series(),
        placement_id: "placement-1",
        data: lifecycle_point_data(:error),
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["error"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")

    assert [] =
             document
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"]))
             |> LazyHTML.attribute("phx-hook")

    assert html =~ "This widget cannot load because its source failed."
  end

  test "partial data table keeps rows visible and explains degraded coverage" do
    html =
      render_component(&Components.widget/1,
        widget: data_table(),
        placement_id: "placement-1",
        data: lifecycle_table_data(:partial),
        compare_data: nil,
        point: nil,
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["partial"] =
             document
             |> LazyHTML.query("[data-widget-body-notice]")
             |> LazyHTML.attribute("data-widget-body-notice")

    assert ["tlm.hk.battery_voltage"] =
             document
             |> LazyHTML.query("[data-data-table-row]")
             |> LazyHTML.attribute("data-data-table-row")

    assert html =~ "This widget is showing partial data"
  end

  test "empty row widgets expose no-data lifecycle body notices" do
    for {type, notice} <- [
          {:status_matrix, "No current rows."},
          {:data_table, "No rows for this table."},
          {:state_timeline, "No state transitions in this time range."},
          {:event_timeline, "No events in this time range."}
        ] do
      html =
        render_component(&Components.widget/1,
          widget: row_widget(type),
          placement_id: "placement-1",
          data: empty_lifecycle_row_data(type),
          compare_data: nil,
          point: nil,
          spacecraft: [],
          backfill: nil,
          limit_markers: [],
          event_markers: [],
          selected_data_ref: nil,
          context_spacecraft_id: "spacecraft-1",
          chart_epoch: 1,
          edit_mode?: false,
          warnings: []
        )

      document = LazyHTML.from_fragment(html)

      assert ["no_data"] =
               document
               |> LazyHTML.query("[data-widget-body-notice]")
               |> LazyHTML.attribute("data-widget-body-notice")

      assert html =~ notice
    end
  end

  test "value tile renders numeric comparison delta" do
    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: point_data(40),
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        data_view: "all_revisions",
        compare_data_view: "canonical",
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["increased"] =
             document
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-state")

    assert ["+2"] =
             document
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-delta")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-data-view")

    assert html =~ "Canonical compare +2"

    assert ["increased"] =
             document
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-state")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-primary-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-compare-view")

    assert ["+2"] =
             document
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-delta")
  end

  test "widget data-link controls carry source identity event params" do
    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data:
          point_data(42)
          |> Map.merge(%{
            links: [presented_link()],
            query_scope_kind: "source_endpoint",
            query_scope_id: "endpoint-1",
            query_scope_ids: ["endpoint-1", "endpoint-2"]
          }),
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)
    selector = "[data-widget-data-link-ref]"

    assert ["link-1"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["flight"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-realm")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["archive"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-time-mode")

    assert ["receipt_time"] =
             document
             |> LazyHTML.query(selector)
             |> LazyHTML.attribute("phx-value-time-axis")

    assert ["frame"] =
             document
             |> LazyHTML.query("[data-widget-frame-evidence]")
             |> LazyHTML.attribute("phx-value-kind")

    assert ["source_endpoint"] =
             document
             |> LazyHTML.query("[data-widget-frame-evidence]")
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["endpoint-1"] =
             document
             |> LazyHTML.query("[data-widget-frame-evidence]")
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["endpoint-1,endpoint-2"] =
             document
             |> LazyHTML.query("[data-widget-frame-evidence]")
             |> LazyHTML.attribute("phx-value-scope-ids")
  end

  test "time-series chart carries comparison backfill payload" do
    html =
      render_component(&Components.widget/1,
        widget: time_series(),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: point_data(40),
        point: %{unit: "V"},
        spacecraft: [],
        backfill: backfill("primary", 42),
        compare_backfill: backfill("compare", 40),
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        time_mode: "replay_run",
        time_axis: "occurred_at",
        replay_run_id: "replay-run-1",
        data_realm: "replay",
        data_view: "all_revisions",
        compare_data_view: "canonical",
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    [encoded] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-compare-backfill]")
      |> LazyHTML.attribute("data-compare-backfill")

    assert %{
             "series" => [
               %{
                 "id" => "compare",
                 "points" => [
                   [
                     _,
                     40,
                     %{
                       "link_id" => "sample-link:compare-sample",
                       "sample_id" => "compare-sample"
                     }
                   ]
                 ]
               }
             ]
           } =
             Jason.decode!(encoded)

    assert ["all_revisions"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-data-view]")
             |> LazyHTML.attribute("data-data-view")

    assert ["canonical"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-compare-data-view]))
             |> LazyHTML.attribute("data-compare-data-view")

    assert ["replay_run"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-time-mode]))
             |> LazyHTML.attribute("data-time-mode")

    assert ["occurred_at"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-time-axis]))
             |> LazyHTML.attribute("data-time-axis")

    assert ["replay-run-1"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-replay-run-id]))
             |> LazyHTML.attribute("data-replay-run-id")

    assert ["replay"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-data-realm]))
             |> LazyHTML.attribute("data-data-realm")

    assert ["source-primary"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-data-source-id]))
             |> LazyHTML.attribute("data-data-source-id")

    assert ["binding-primary"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-source-binding-id]))
             |> LazyHTML.attribute("data-source-binding-id")

    assert ["all_revisions"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-primary-data-view")

    assert ["canonical"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-compare-data-view")

    assert html =~ "All revisions vs Canonical"

    assert ["available"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-state")

    assert ["1"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-primary-count")

    assert ["1"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-comparison-summary]")
             |> LazyHTML.attribute("data-widget-comparison-compare-count")

    assert html =~ "1 vs 1 pts"

    assert ["all_revisions,corrected"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="TelemetryChart"][data-data-management-badges]))
             |> LazyHTML.attribute("data-data-management-badges")

    assert ["recomputed,backfill"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(
               ~s([phx-hook="TelemetryChart"][data-compare-data-management-badges])
             )
             |> LazyHTML.attribute("data-compare-data-management-badges")

    assert ["all_revisions", "corrected", "recomputed", "backfill"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-chart-data-management-strip] [data-data-management-badge]")
             |> LazyHTML.attribute("data-data-management-badge")
  end

  test "time-series chart exposes late-data execution summaries in data-management badges" do
    html =
      render_component(&Components.widget/1,
        widget: time_series(),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: late_data_backfill(),
        compare_backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        data_view: "canonical",
        compare_data_view: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert "Late data accepted" ==
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.text()
             |> String.trim()

    assert [
             "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
           ] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.attribute("data-data-management-summary")

    assert [
             "Late data accepted - 2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
           ] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="late_data_accepted"]))
             |> LazyHTML.attribute("title")
  end

  test "value tile header renders frame revision and workflow state badges" do
    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: data_management_point_data(42),
        compare_data: nil,
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        data_view: "all_revisions",
        compare_data_view: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["corrected,import_retried"] =
             document
             |> LazyHTML.query(~s([data-data-management-badges="corrected,import_retried"]))
             |> LazyHTML.attribute("data-data-management-badges")

    assert ["revision_state"] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="corrected"]))
             |> LazyHTML.attribute("data-data-management-kind")

    assert ["Corrected"] =
             document
             |> LazyHTML.query(~s([data-data-management-badge="corrected"]))
             |> LazyHTML.text()
             |> then(&[String.trim(&1)])

    assert ["historical_workflow"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("data-data-management-kind")

    assert ["telemetry_backfill_lifecycle_event"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("data-data-link-target")

    assert ["import-retry-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("data-data-link-target-id")

    assert ["direct:telemetry_backfill_lifecycle_event:import-retry-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("data-data-link-data-view")

    assert ["customer_archive_import"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("data-data-link-data-source-id")

    assert ["Import retried - Retry queued from dashboard lifecycle inspector"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="import_retried"]))
             |> LazyHTML.attribute("title")
  end

  test "value tile omits comparison delta for non-numeric comparison data" do
    html =
      render_component(&Components.widget/1,
        widget: value_tile(),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: point_data("nominal"),
        point: %{unit: "V"},
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-delta")
  end

  test "event timeline renders data-management workflow badges" do
    html =
      render_component(&Components.widget/1,
        widget: event_timeline(),
        placement_id: "placement-1",
        data: event_timeline_data(),
        compare_data: nil,
        point: nil,
        spacecraft: [],
        backfill: nil,
        limit_markers: [],
        event_markers: [],
        selected_data_ref: nil,
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 1,
        edit_mode?: false,
        warnings: []
      )

    document = LazyHTML.from_fragment(html)

    assert ["backfill_started"] =
             document
             |> LazyHTML.query("[data-event-timeline-row]")
             |> LazyHTML.attribute("data-data-management-badges")

    assert ["backfill_started"] =
             document
             |> LazyHTML.query("[data-data-management-badge]")
             |> LazyHTML.attribute("data-data-management-badge")

    assert ["open_data_link"] =
             document
             |> LazyHTML.query(
               ~s(button[data-data-management-badge="backfill_started"][data-data-link-target="telemetry_backfill_lifecycle_event"])
             )
             |> LazyHTML.attribute("phx-click")

    assert ["backfill-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-target-id")

    assert ["direct:telemetry_backfill_lifecycle_event:backfill-event-1"] =
             document
             |> LazyHTML.query(~s(button[data-data-management-badge="backfill_started"]))
             |> LazyHTML.attribute("phx-value-link-id")
  end

  defp event_timeline do
    %RenderWidget{
      widget_id: "widget-1",
      type: :event_timeline,
      title: "Events",
      binding: %{mode: :context, source: :events, point_id: "events"},
      options: %{}
    }
  end

  defp event_timeline_data do
    %{
      kind: :event_timeline,
      rows: [
        %{
          row_id: "event:backfill-event-1",
          category: :telemetry_backfill,
          kind: :backfill_started,
          severity: :info,
          title: "HK.counter backfill started",
          occurred_at: ~U[2026-06-17 12:05:00Z],
          source_record_id: "backfill-event-1",
          links: [],
          data_management: %{
            badges: [
              %{
                kind: :historical_workflow,
                value: "backfill_started",
                label: "Backfill started",
                status: :attention,
                code: "backfill_started",
                data_link_target: :telemetry_backfill_lifecycle_event,
                data_link_id: "backfill-event-1"
              }
            ]
          }
        }
      ],
      links: [],
      data_management: nil,
      stale?: false,
      unresolved?: false,
      engine_backed?: true,
      lifecycle_state: :ready
    }
  end

  defp value_tile do
    %RenderWidget{
      widget_id: "widget-1",
      type: :value_tile,
      title: "Voltage",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2}
    }
  end

  defp time_series do
    %RenderWidget{
      widget_id: "widget-1",
      type: :time_series,
      title: "Voltage",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2, window_seconds: 300}
    }
  end

  defp data_table do
    %RenderWidget{
      widget_id: "widget-1",
      type: :data_table,
      title: "Telemetry Rows",
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.voltage"
      },
      options: %{precision: 2}
    }
  end

  defp row_widget(:event_timeline), do: event_timeline()

  defp row_widget(type) when type in [:status_matrix, :data_table, :state_timeline] do
    %{data_table() | type: type}
  end

  defp empty_lifecycle_row_data(:event_timeline) do
    %{event_timeline_data() | rows: [], lifecycle_state: :no_data}
  end

  defp empty_lifecycle_row_data(type)
       when type in [:status_matrix, :data_table, :state_timeline] do
    %{
      lifecycle_table_data(:no_data)
      | kind: type,
        rows: []
    }
  end

  defp backfill(series_id, value) do
    %{
      version: 1,
      data_management: backfill_data_management(series_id),
      series: [
        %{
          id: series_id,
          label: series_id,
          unit: "V",
          data_source_id: "source-#{series_id}",
          source_binding_id: "binding-#{series_id}",
          data_management: backfill_data_management(series_id),
          points: [
            [
              1_781_568_000_000,
              value,
              %{
                sample_id: "#{series_id}-sample",
                link_id: "sample-link:#{series_id}-sample"
              }
            ]
          ]
        }
      ]
    }
  end

  defp backfill_data_management("primary") do
    %{
      data_view: "all_revisions",
      warning_codes: ["corrected_range"],
      badges: [
        %{
          kind: :data_view,
          value: "all_revisions",
          label: "All revisions",
          status: :attention,
          code: "all_revisions_view"
        },
        %{
          kind: :revision_state,
          value: "corrected",
          label: "Corrected",
          status: :warning,
          code: "corrected_range"
        }
      ]
    }
  end

  defp backfill_data_management("compare") do
    %{
      data_view: "recomputed",
      warning_codes: ["advisory_backfill"],
      badges: [
        %{
          kind: :data_view,
          value: "recomputed",
          label: "Recomputed",
          status: :attention,
          code: "recomputed_values"
        },
        %{
          kind: :revision_state,
          value: "backfill",
          label: "Backfill",
          status: :warning,
          code: "advisory_backfill"
        }
      ]
    }
  end

  defp backfill_data_management(_series_id), do: nil

  defp late_data_backfill do
    %{
      version: 1,
      data_management: %{
        badges: [
          %{
            kind: :historical_workflow,
            value: "late_data_accepted",
            label: "Late data accepted",
            status: :info,
            code: "late_data_accepted",
            data_link_target: :telemetry_backfill_lifecycle_event,
            data_link_id: "late-data-event-1",
            summary:
              "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection"
          }
        ]
      },
      series: [
        %{
          id: "primary",
          label: "primary",
          unit: "V",
          points: [[1_781_568_000_000, 42, %{sample_id: "late-data-sample"}]]
        }
      ]
    }
  end

  defp data_management_point_data(value) do
    value
    |> point_data()
    |> Map.put(:data_management, %{
      data_view: "all_revisions",
      warning_codes: ["corrected_range", "import_retried"],
      badges: [
        %{
          kind: :revision_state,
          value: "corrected",
          label: "Corrected",
          status: :warning,
          code: "corrected_range",
          summary: "Canonical value selected after revision decision"
        },
        %{
          kind: :historical_workflow,
          value: "import_retried",
          label: "Import retried",
          status: :attention,
          code: "import_retried",
          summary: "Retry queued from dashboard lifecycle inspector",
          data_link_target: :telemetry_backfill_lifecycle_event,
          data_link_id: "import-retry-event-1",
          realm: "backfill",
          data_view: "all_revisions",
          data_source_id: "customer_archive_import",
          source_binding_id: "import_telemetry",
          time_mode: "archive",
          time_axis: "generation_time"
        }
      ]
    })
  end

  defp point_data(value) do
    %{
      kind: :point,
      sample: %{
        raw_value: value,
        engineering_value: value,
        receipt_time: ~U[2026-06-17 12:00:00Z],
        generation_time: ~U[2026-06-17 12:00:00Z],
        quality_state: :good
      },
      limit_event: nil,
      links: [],
      data_management: nil,
      stale?: false,
      unresolved?: false,
      engine_backed?: true,
      lifecycle: %{state: :ready},
      lifecycle_state: :ready
    }
  end

  defp presented_link do
    %{
      link_id: "link-1",
      label: "Telemetry sample",
      target_text: "telemetry sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp lifecycle_point_data(state) do
    sample =
      if state in [:no_data, :retention_gap, :error, :unsupported] do
        nil
      else
        point_data(42).sample
      end

    %{
      point_data(42)
      | sample: sample,
        stale?: state == :stale,
        lifecycle_state: state,
        lifecycle: %{
          state: state,
          severity: lifecycle_severity(state),
          reason_codes: lifecycle_reasons(state),
          warning_codes: []
        }
    }
  end

  defp lifecycle_table_data(state) do
    %{
      kind: :data_table,
      rows: [
        %{
          observable_id: "tlm.hk.battery_voltage",
          label: "Battery voltage",
          source: :telemetry,
          value: 12.25,
          unit: "V",
          quality_state: :good,
          normalized_state: :green,
          limit_state: :green,
          receipt_time: ~U[2026-06-17 12:00:00Z],
          links: []
        }
      ],
      links: [],
      data_management: nil,
      stale?: state == :stale,
      unresolved?: false,
      engine_backed?: true,
      lifecycle_state: state,
      lifecycle: %{
        state: state,
        severity: lifecycle_severity(state),
        reason_codes: lifecycle_reasons(state),
        warning_codes: []
      }
    }
  end

  defp lifecycle_severity(:no_data), do: :info
  defp lifecycle_severity(:stale), do: :warning
  defp lifecycle_severity(:partial), do: :warning
  defp lifecycle_severity(:retention_gap), do: :error
  defp lifecycle_severity(:error), do: :error
  defp lifecycle_severity(:unsupported), do: :error

  defp lifecycle_reasons(state), do: [state]

  defp data_binding do
    %DataBinding{
      binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
