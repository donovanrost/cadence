defmodule CadenceWeb.OpsDashboardShowLive.EvidencePresentationOperationalMetricsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    EvidenceRef,
    Field,
    Frame,
    PlacementFrames
  }

  alias CadenceWeb.OpsDashboardShowLive.EvidencePresentation

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

  defp evidence_ref_summary(evidence, kind, id) do
    Enum.find(evidence, &(&1.kind == kind and &1.id == id))
  end
end
