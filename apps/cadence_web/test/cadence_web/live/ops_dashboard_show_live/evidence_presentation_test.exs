defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    PlacementFrames,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

  test "summarizes source watermark event data links" do
    assert %{
             target: :source_watermark_event,
             target_text: "source watermark event",
             target_id: "watermark-event-1",
             source_text: "frame"
           } =
             EvidencePresentation.link_summary(%DataLink{
               link_id: "source_watermark_event:watermark-event-1",
               label: "Source watermark",
               target: :source_watermark_event,
               target_id: "watermark-event-1",
               source: :frame
             })
  end

  test "dashboard health evidence presents shareable rollup context" do
    assert %{
             kind: :dashboard_health,
             kind_text: "dashboard health",
             title: "Dashboard Health Evidence",
             subject: "dashboard health blocked",
             status_text: "blocked",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: []
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "dashboard_health",
               "dashboard-health-schema" => "dashboard_health_snapshot.v1",
               "dashboard-health-snapshot-id" => "dashboard_health_snapshot_abc123",
               "dashboard-health-state" => "blocked",
               "dashboard-health-severity" => "error",
               "dashboard-health-widgets" => "4",
               "dashboard-health-ready" => "1",
               "dashboard-health-degraded" => "1",
               "dashboard-health-stale" => "1",
               "dashboard-health-blocked" => "1",
               "dashboard-health-affected" => "3",
               "dashboard-health-states" => "ready,degraded,stale,blocked",
               "dashboard-health-affected-placements" =>
                 "degraded-placement,stale-placement,blocked-placement",
               "dashboard-health-blocked-placements" => "blocked-placement",
               "dashboard-health-stale-placements" => "stale-placement",
               "dashboard-health-degraded-placements" => "degraded-placement"
             })

    assert %{label: "Health snapshot schema", value: "dashboard_health_snapshot.v1"} in subject_rows
    assert %{label: "Health snapshot", value: "dashboard_health_snapshot_abc123"} in subject_rows
    assert %{label: "Widgets", value: "4"} in detail_rows
    assert %{label: "Affected widgets", value: "3"} in detail_rows
    assert %{label: "Blocked placements", value: "blocked-placement"} in detail_rows
    assert %{label: "Stale placements", value: "stale-placement"} in detail_rows
  end

  test "source context evidence includes contact scope filter diagnostics" do
    assert %{
             kind: :source,
             status_text: "no_data",
             message:
               "Widget source returned no data for contact contact-1 after filtering telemetry to source endpoint endpoint-1.",
             detail_rows: detail_rows,
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "no_data",
               "logical-source" => "telemetry",
               "scope-kind" => "spacecraft",
               "scope-id" => "spacecraft-1",
               "contact-id" => "contact-1",
               "source-endpoint-id" => "endpoint-1",
               "source-empty-reason" => "contact_scope_no_data",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight",
               "source-health-event-id" => "source-health-event-1",
               "source-health-reason" => "source_adapter_probe_unsupported",
               "source-health-probe-kind" => "adapter_unsupported",
               "source-health-probe-message" => "adapter does not support active probes",
               "source-health-probe-metadata" => "storage=questdb"
             })

    assert %{label: "Scope kind", value: "spacecraft"} in detail_rows
    assert %{label: "Scope", value: "spacecraft-1"} in detail_rows
    assert %{label: "Contact", value: "contact-1"} in detail_rows
    assert %{label: "Source endpoint", value: "endpoint-1"} in detail_rows
    assert %{label: "Source empty reason", value: "contact_scope_no_data"} in detail_rows
    assert %{label: "Source health event", value: "source-health-event-1"} in detail_rows

    assert %{label: "Source health reason", value: "source_adapter_probe_unsupported"} in detail_rows

    assert %{label: "Probe kind", value: "adapter_unsupported"} in detail_rows

    assert %{label: "Probe message", value: "adapter does not support active probes"} in detail_rows

    assert %{label: "Probe metadata", value: "storage=questdb"} in detail_rows

    assert [
             %DashboardAction{
               target: :source_health,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               }
             },
             %DashboardAction{
               target: :source_inventory,
               query: %{
                 "data_source_id" => "flight-questdb",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry",
                 "realm" => "flight",
                 "scope_kind" => "spacecraft",
                 "scope_id" => "spacecraft-1",
                 "contact_id" => "contact-1",
                 "source_endpoint_id" => "endpoint-1",
                 "source_empty_reason" => "contact_scope_no_data"
               }
             }
           ] = actions
  end

  test "source context evidence explains partial source coverage" do
    assert %{
             kind: :source,
             status_text: "partial",
             message:
               "Widget source returned partial data for the selected context; inspect missing series, source scope, and source-health evidence before trusting this value.",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "partial",
               "logical-source" => "telemetry",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight"
             })

    assert %{label: "Widget source status", value: "partial"} in detail_rows
  end

  test "source context evidence explains degraded source health" do
    assert %{
             kind: :source,
             status_text: "degraded",
             message:
               "Widget source status is degraded; inspect source-health evidence before trusting this value.",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(nil, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "degraded",
               "logical-source" => "telemetry",
               "data-source-id" => "flight-questdb",
               "source-binding-id" => "binding-flight",
               "realm" => "flight"
             })

    assert %{label: "Widget source status", value: "degraded"} in detail_rows
  end

  test "source evidence inspector surfaces context-only cache evidence details" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             status_text: "context_only",
             subject: "missing-cache-source",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-state" => "context_only",
               "cache-evidence-layer" => "source",
               "cache-evidence-status" => "hit",
               "cache-evidence-reasons" => "operator_requested",
               "source-request-id" => "missing-cache-source",
               "logical-source" => "telemetry",
               "requested-source-binding-id" => "binding-flight"
             })

    assert %{value: "missing-cache-source"} =
             Enum.find(subject_rows, &(&1.label == "Source request"))

    assert %{value: "hit"} = Enum.find(detail_rows, &(&1.label == "Cache evidence status"))

    assert %{value: "binding-flight"} =
             Enum.find(detail_rows, &(&1.label == "Requested source binding"))

    assert [
             %DashboardAction{target: :source_health, query: %{"logical_source" => "telemetry"}},
             %DashboardAction{
               target: :source_inventory,
               query: %{"logical_source" => "telemetry"}
             }
           ] = actions

    refute EvidencePresentation.evidence_inspector(result, %{
             "kind" => "source",
             "source-request-id" => "missing-cache-source",
             "logical-source" => "telemetry"
           })
  end

  test "source evidence inspector surfaces capability posture context without an incident" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             status_text: "context_only",
             subject: "req-telemetry",
             subject_rows: subject_rows,
             detail_rows: detail_rows,
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "execution",
               "source-capability-status" => "fallback",
               "source-request-id" => "req-telemetry",
               "logical-source" => "telemetry",
               "realm" => "flight",
               "data-source-id" => "questdb-flight",
               "source-binding-id" => "binding-flight",
               "requested-time-axis" => "generation_time",
               "executed-time-axis" => "receipt_time",
               "supported-time-axes" => "receipt_time",
               "source-capability-fallbacks" =>
                 "time_axis:generation_time:receipt_time:unsupported_time_axis"
             })

    assert %{value: "req-telemetry"} = Enum.find(subject_rows, &(&1.label == "Source request"))

    assert %{value: "fallback"} =
             Enum.find(detail_rows, &(&1.label == "Source capability status"))

    assert %{value: "generation_time"} =
             Enum.find(detail_rows, &(&1.label == "Requested time axis"))

    assert %{value: "receipt_time"} = Enum.find(detail_rows, &(&1.label == "Executed time axis"))

    assert [
             %DashboardAction{target: :source_health, query: %{"logical_source" => "telemetry"}},
             %DashboardAction{
               target: :source_inventory,
               query: %{"logical_source" => "telemetry"}
             }
           ] = actions
  end

  test "source evidence inspector summarizes widget source-status drilldowns without incidents" do
    result = %DashboardResolveResult{}

    assert %{
             kind: :source,
             title: "Telemetry Source Status",
             status_text: "stale",
             subject: "telemetry",
             message: stale_message,
             detail_rows: detail_rows,
             evidence: [],
             links: [],
             actions: actions
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "source",
               "source-evidence-mode" => "health",
               "source-evidence-state" => "stale",
               "logical-source" => "telemetry",
               "data-source-id" => "questdb-flight",
               "source-binding-id" => "binding-flight",
               "time-mode" => "archive",
               "time-axis" => "packet_time"
             })

    assert stale_message =~ "Widget source status is stale"

    assert %{value: "stale"} =
             Enum.find(detail_rows, &(&1.label == "Widget source status"))

    assert %{value: "health"} =
             Enum.find(detail_rows, &(&1.label == "Widget evidence mode"))

    assert %{value: "archive"} = Enum.find(detail_rows, &(&1.label == "Time mode"))
    assert %{value: "packet_time"} = Enum.find(detail_rows, &(&1.label == "Time axis"))

    assert [
             %DashboardAction{
               target: :source_health,
               query: %{
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry"
               }
             },
             %DashboardAction{
               target: :source_inventory,
               query: %{
                 "data_source_id" => "questdb-flight",
                 "source_binding_id" => "binding-flight",
                 "logical_source" => "telemetry"
               }
             }
           ] = actions
  end

  test "frame evidence details include selected data view" do
    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-counter" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "source-request-1:HK.counter",
              source: :telemetry,
              shape: :scalar,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
                %Field{
                  name: "HK.counter",
                  kind: :number,
                  values: [41],
                  metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
                }
              ],
              meta: %{
                logical_source: :telemetry,
                observable_id: "HK.counter",
                sampling: :latest,
                data_view: :all_revisions,
                value_type: :engineering,
                returned_points: 1,
                warning_codes: [:all_revisions_view]
              }
            }
          ]
        }
      }
    }

    assert %{detail_rows: detail_rows} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-counter",
               "observable-id" => "HK.counter"
             })

    assert %{value: "all_revisions"} = Enum.find(detail_rows, &(&1.label == "Data view"))

    assert %{value: "[:all_revisions_view]"} =
             Enum.find(detail_rows, &(&1.label == "Warning codes"))
  end

  test "frame evidence details and evidence refs summarize selected semantic intervals" do
    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-counter" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "source-request-1:HK.counter",
              source: :telemetry,
              shape: :scalar,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-21 20:30:00Z]]},
                %Field{
                  name: "HK.counter",
                  kind: :number,
                  values: [12.4],
                  metadata: %{
                    evidence: [
                      %EvidenceRef{
                        kind: :application_binding_interval,
                        id: "application-binding-interval-1",
                        source: :operational_event,
                        confidence: :selected,
                        observed_at: ~U[2026-06-21 20:30:00Z]
                      }
                    ]
                  }
                }
              ],
              meta: %{
                logical_source: :telemetry,
                observable_id: "HK.counter",
                evidence: [
                  %EvidenceRef{
                    kind: :source_binding_interval,
                    id: "source-binding-interval-1",
                    source: :telemetry,
                    confidence: :selected,
                    observed_at: ~U[2026-06-21 20:30:00Z]
                  },
                  %EvidenceRef{
                    kind: :binding_set_interval,
                    id: "binding-set-interval-1",
                    source: :operational_event,
                    confidence: :selected,
                    observed_at: ~U[2026-06-21 20:30:00Z]
                  }
                ],
                source_binding_interval: %{
                  binding_id: "flight-telemetry",
                  data_binding_event_id: "source-binding-event-1",
                  data_source_id: "mission-questdb-v1",
                  active_from: ~U[2026-06-21 20:00:00Z],
                  active_to: nil
                },
                selected_operational_intervals: [
                  %{
                    kind: :binding_set,
                    subject_id: "runtime-apps-a",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: nil,
                    source_event_id: "operational-event-binding-set"
                  },
                  %{
                    kind: :application_binding,
                    subject_id: "runtime-apps-a-packet-counter-rule",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: nil,
                    source_event_id: "operational-event-application-binding"
                  },
                  %{
                    kind: :catalog_revision,
                    subject_id: "catalog-revision-a",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: ~U[2026-06-21 21:00:00Z],
                    source_event_id: "operational-event-catalog"
                  }
                ]
              }
            }
          ]
        }
      }
    }

    assert %{detail_rows: detail_rows, evidence: evidence} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-counter",
               "observable-id" => "HK.counter"
             })

    assert %{value: "source-binding-event-1"} =
             Enum.find(detail_rows, &(&1.label == "Source binding interval"))

    assert %{value: "flight-telemetry"} =
             Enum.find(detail_rows, &(&1.label == "Source binding interval binding"))

    assert %{value: "mission-questdb-v1"} =
             Enum.find(detail_rows, &(&1.label == "Source binding interval data source"))

    assert %{value: "2026-06-21T20:00:00Z -> open"} =
             Enum.find(detail_rows, &(&1.label == "Source binding interval window"))

    assert %{value: "runtime-apps-a (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Binding set interval"))

    assert %{value: "operational-event-binding-set"} =
             Enum.find(detail_rows, &(&1.label == "Binding set interval source event"))

    assert %{
             value: "runtime-apps-a-packet-counter-rule (2026-06-21T20:00:00Z -> open)"
           } =
             Enum.find(detail_rows, &(&1.label == "Application binding interval"))

    assert %{value: "catalog-revision-a (2026-06-21T20:00:00Z -> 2026-06-21T21:00:00Z)"} =
             Enum.find(detail_rows, &(&1.label == "Catalog revision interval"))

    assert %{
             kind_text: "source binding interval",
             source: :telemetry,
             source_text: "telemetry",
             confidence: :selected,
             confidence_text: "selected",
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(evidence, :source_binding_interval, "source-binding-interval-1")

    assert %{
             kind_text: "binding set interval",
             source: :operational_event,
             source_text: "operational_event",
             confidence: :selected,
             confidence_text: "selected",
             observed_at_text: "2026-06-21T20:30:00Z"
           } = evidence_ref_summary(evidence, :binding_set_interval, "binding-set-interval-1")

    assert %{
             kind_text: "application binding interval",
             source: :operational_event,
             source_text: "operational_event",
             confidence: :selected,
             confidence_text: "selected",
             observed_at_text: "2026-06-21T20:30:00Z"
           } =
             evidence_ref_summary(
               evidence,
               :application_binding_interval,
               "application-binding-interval-1"
             )
  end

  test "limits frame evidence details expose selected limit definition and catalog revision" do
    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-limit-state" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "limits-request-1:HK.counter:latest_state",
              source: :limits,
              shape: :scalar,
              time_axis: :receipt_time,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-21 20:30:00Z]]},
                %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
                %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
                %Field{name: "violation", kind: :boolean, values: [true]}
              ],
              meta: %{
                logical_source: :limits,
                source_request_id: "limits-request-1",
                source_binding_id: "default_flight_limits",
                data_source_id: "managed_limits_projection",
                realm: :flight,
                observable_id: "HK.counter",
                sampling: :latest_state,
                semantics_mode: :observed,
                returned_points: 1,
                selected_limit_definition_intervals: [
                  %{
                    definition_activation_key: "limit-activation-1",
                    limit_definition_lifecycle_event_id: "limit-lifecycle-1",
                    limit_definition_id: "limit-def-1",
                    limit_definition_version: 3,
                    limit_set_name: "ops",
                    active_from: ~U[2026-06-21 20:00:00Z],
                    active_to: nil
                  }
                ],
                selected_operational_intervals: [
                  %{
                    kind: :catalog_revision,
                    subject_id: "catalog-revision-limits",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: nil,
                    source_event_id: "operational-event-catalog-limits"
                  }
                ],
                evidence: [
                  %EvidenceRef{
                    kind: :limit_event,
                    id: "limit-event-1",
                    source: :limits,
                    confidence: :direct,
                    observed_at: ~U[2026-06-21 20:30:00Z]
                  },
                  %EvidenceRef{
                    kind: :limit_definition_interval,
                    id: "effective_interval:limit_definition:limit-activation-1",
                    source: :limits,
                    confidence: :direct,
                    observed_at: ~U[2026-06-21 20:00:00Z]
                  },
                  %EvidenceRef{
                    kind: :limit_definition_lifecycle_event,
                    id: "limit-lifecycle-1",
                    source: :limits,
                    confidence: :direct,
                    observed_at: ~U[2026-06-21 20:00:00Z]
                  },
                  %EvidenceRef{
                    kind: :catalog_revision_interval,
                    id: "limits-catalog-revision-interval-1",
                    source: :limits,
                    confidence: :projected,
                    observed_at: ~U[2026-06-21 20:00:00Z]
                  }
                ]
              }
            }
          ]
        }
      }
    }

    assert %{detail_rows: detail_rows, evidence: evidence} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-limit-state",
               "observable-id" => "HK.counter"
             })

    assert %{value: "latest_state"} = Enum.find(detail_rows, &(&1.label == "Sampling"))

    assert %{value: "limit-def-1 v3 / ops (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Limit definition interval"))

    assert %{value: "limit-lifecycle-1"} =
             Enum.find(detail_rows, &(&1.label == "Limit definition interval lifecycle event"))

    assert %{value: "catalog-revision-limits (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Catalog revision interval"))

    assert %{value: "operational-event-catalog-limits"} =
             Enum.find(detail_rows, &(&1.label == "Catalog revision interval source event"))

    assert %{
             source: :limits,
             source_text: "limits",
             confidence: :direct,
             confidence_text: "direct",
             observed_at_text: "2026-06-21T20:00:00Z"
           } =
             evidence_ref_summary(
               evidence,
               :limit_definition_interval,
               "effective_interval:limit_definition:limit-activation-1"
             )

    assert %{
             source: :limits,
             source_text: "limits",
             confidence: :projected,
             confidence_text: "projected",
             observed_at_text: "2026-06-21T20:00:00Z"
           } =
             evidence_ref_summary(
               evidence,
               :catalog_revision_interval,
               "limits-catalog-revision-interval-1"
             )
  end

  test "telemetry frame evidence details include selected limits overlay intervals" do
    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-counter" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "telemetry-request-1:HK.counter:latest",
              source: :telemetry,
              shape: :scalar,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-21 20:30:00Z]]},
                %Field{name: "HK.counter", kind: :number, values: [42]}
              ],
              meta: %{
                logical_source: :telemetry,
                source_request_id: "telemetry-request-1",
                source_binding_id: "default_flight_telemetry",
                data_source_id: "managed_questdb_primary",
                realm: :flight,
                observable_id: "HK.counter",
                sampling: :latest
              }
            }
          ],
          overlays: %{
            limits: [
              %Frame{
                frame_id: "limits-request-1:HK.counter:latest_state",
                source: :limits,
                shape: :scalar,
                fields: [
                  %Field{name: "time", kind: :time, values: [~U[2026-06-21 20:30:00Z]]},
                  %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
                  %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
                  %Field{name: "violation", kind: :boolean, values: [true]}
                ],
                meta: %{
                  logical_source: :limits,
                  source_request_id: "limits-request-1",
                  source_binding_id: "default_flight_limits",
                  data_source_id: "managed_limits_projection",
                  realm: :flight,
                  observable_id: "HK.counter",
                  sampling: :latest_state,
                  selected_limit_definition_intervals: [
                    %{
                      interval_id: "effective_interval:limit_definition:limit-activation-1",
                      subject_id: "limit-activation-1",
                      starts_at: ~U[2026-06-21 20:00:00Z],
                      ends_at: nil,
                      source_event_id: "limit-lifecycle-1",
                      payload: %{
                        limit_definition_id: "limit-def-1",
                        limit_definition_version: 3,
                        limit_set_name: "ops"
                      }
                    }
                  ],
                  selected_operational_intervals: [
                    %{
                      kind: :catalog_revision,
                      subject_id: "catalog-revision-limits",
                      starts_at: ~U[2026-06-21 20:00:00Z],
                      ends_at: nil,
                      source_event_id: "operational-event-catalog-limits"
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }

    assert %{detail_rows: detail_rows} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-counter",
               "observable-id" => "HK.counter"
             })

    assert %{value: "latest"} = Enum.find(detail_rows, &(&1.label == "Sampling"))

    assert %{value: "limit-def-1 v3 / ops (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Limit definition interval"))

    assert %{value: "limit-lifecycle-1"} =
             Enum.find(detail_rows, &(&1.label == "Limit definition interval lifecycle event"))

    assert %{value: "catalog-revision-limits (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Catalog revision interval"))

    assert %{value: "operational-event-catalog-limits"} =
             Enum.find(detail_rows, &(&1.label == "Catalog revision interval source event"))
  end

  test "operational metric-history frame evidence details expose product family and selected intervals" do
    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-rf-snr-history" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "source-request-1:link_rf_metric_history:link-alpha",
              source: :operational_observables,
              shape: :wide,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-21 20:30:00Z]]},
                %Field{
                  name: "link.snr_db",
                  kind: :number,
                  values: [12.5],
                  metadata: %{
                    observable_id: "link.snr_db",
                    resource_id: "link-alpha"
                  }
                }
              ],
              meta: %{
                logical_source: :operational_observables,
                supported_capability: :link_rf_metric_history,
                product_family: :link_rf,
                observable_id: "link.snr_db",
                resource_id: "link-alpha",
                returned_points: 1,
                evidence: [
                  %EvidenceRef{
                    kind: :binding_set_interval,
                    id: "metric-binding-set-interval-1",
                    source: :operational_observables,
                    confidence: :projected,
                    observed_at: ~U[2026-06-21 20:30:00Z]
                  },
                  %EvidenceRef{
                    kind: :application_binding_interval,
                    id: "metric-application-binding-interval-1",
                    source: :operational_observables,
                    confidence: :projected,
                    observed_at: ~U[2026-06-21 20:30:00Z]
                  }
                ],
                selected_operational_intervals: [
                  %{
                    kind: :binding_set,
                    subject_id: "runtime-apps-a",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: nil,
                    source_event_id: "operational-event-metric-binding-set"
                  },
                  %{
                    kind: :application_binding,
                    subject_id: "runtime-apps-a-link-rule",
                    starts_at: ~U[2026-06-21 20:00:00Z],
                    ends_at: nil,
                    source_event_id: "operational-event-metric-application-binding"
                  }
                ]
              }
            }
          ]
        }
      }
    }

    assert %{detail_rows: detail_rows, evidence: evidence} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-rf-snr-history",
               "observable-id" => "link.snr_db"
             })

    assert %{value: "link_rf_metric_history"} =
             Enum.find(detail_rows, &(&1.label == "Supported capability"))

    assert %{value: "link_rf"} = Enum.find(detail_rows, &(&1.label == "Product family"))

    assert %{value: "runtime-apps-a (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Binding set interval"))

    assert %{value: "operational-event-metric-binding-set"} =
             Enum.find(detail_rows, &(&1.label == "Binding set interval source event"))

    assert %{value: "runtime-apps-a-link-rule (2026-06-21T20:00:00Z -> open)"} =
             Enum.find(detail_rows, &(&1.label == "Application binding interval"))

    assert %{
             source: :operational_observables,
             source_text: "operational_observables",
             confidence: :projected,
             confidence_text: "projected"
           } =
             evidence_ref_summary(
               evidence,
               :binding_set_interval,
               "metric-binding-set-interval-1"
             )

    assert %{
             source: :operational_observables,
             source_text: "operational_observables",
             confidence: :projected,
             confidence_text: "projected"
           } =
             evidence_ref_summary(
               evidence,
               :application_binding_interval,
               "metric-application-binding-interval-1"
             )
  end

  test "frame evidence inspectors carry telemetry action metadata" do
    action = %DashboardAction{
      action_id: "telemetry-explore:req-1:HK.counter:frame",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{"point_id" => "HK.counter", "realm" => "flight"},
      source: :frame
    }

    field_action = %DashboardAction{
      action
      | action_id: "telemetry-explore:req-1:HK.counter:field",
        source: :field
    }

    result = %DashboardResolveResult{
      frames_by_placement: %{
        "placement-counter" => %PlacementFrames{
          primary: [
            %Frame{
              frame_id: "req-1:HK.counter",
              source: :telemetry,
              shape: :scalar,
              time_axis: :receipt_time,
              fields: [
                %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
                %Field{
                  name: "HK.counter",
                  kind: :number,
                  values: [42],
                  metadata: %{actions: [field_action]}
                }
              ],
              meta: %{
                observable_id: "HK.counter",
                logical_source: :telemetry,
                sampling: :latest,
                actions: [action]
              }
            }
          ]
        }
      }
    }

    assert %{actions: actions} =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "frame",
               "placement-id" => "placement-counter",
               "observable-id" => "HK.counter"
             })

    assert Enum.map(actions, & &1.source) == [:frame, :field]
    assert Enum.all?(actions, &(&1.target == :telemetry_explore))
  end

  test "evidence inspector resolves placement warnings through runtime result accessors" do
    result = %{
      "frames_by_placement" => %{
        "placement-counter" => %PlacementFrames{
          warnings: [
            %ResolveWarning{
              code: :source_degraded,
              severity: :warning,
              message: "Telemetry source degraded",
              details: %{source_binding_id: "binding-flight"}
            }
          ]
        }
      }
    }

    assert %{
             kind: :warning,
             subject: "source_degraded",
             status_text: "warning",
             message: "Telemetry source degraded",
             detail_rows: detail_rows
           } =
             EvidencePresentation.evidence_inspector(result, %{
               "kind" => "warning",
               "placement-id" => "placement-counter",
               "warning-code" => "source_degraded"
             })

    assert %{label: "Source binding id", value: "binding-flight"} in detail_rows
  end

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
