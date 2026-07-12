defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationTelemetryFrameTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardAction,
    DashboardResolveResult,
    EvidenceRef,
    Field,
    Frame,
    PlacementFrames
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

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

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
