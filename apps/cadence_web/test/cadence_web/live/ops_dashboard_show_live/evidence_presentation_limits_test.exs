defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationLimitsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    EvidenceRef,
    Field,
    Frame,
    PlacementFrames
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

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

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
