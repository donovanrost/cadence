defmodule Cadence.Dashboards.PublishReadinessPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{PublishReadinessPresentation, ValidationResult}

  test "builds publish readiness issues with typed source remediation actions" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :source_connection_failed,
            placement_id: "tile-1",
            details: %{
              logical_source: :telemetry,
              binding_id: "rehearsal-binding",
              data_source_id: "rehearsal-source",
              connection_test_result: "failed",
              connection_test_kind: "adapter_io",
              connection_test_message: "Adapter connection test failed."
            }
          }
        }
      ]
    }

    assert %{
             status: "blocked",
             issues: [
               %{
                 id: "error:unready_publish_source_request:tile-1:source_connection_failed",
                 message: "Dashboard source connection test failed for the publish context.",
                 action: %{
                   label: "Fix source connection",
                   target: "data_sources",
                   params: %{
                     "data_source_id" => "rehearsal-source",
                     "source_binding_id" => "rehearsal-binding",
                     "source_empty_reason" => "connection_test_failed",
                     "selected_source_evidence_state" => "connection_test_failed"
                   },
                   typed_action: %{
                     "action_id" => "dashboard-publish-source-readiness-action",
                     "target" => "source_health",
                     "kind" => "invoke",
                     "query" => %{
                       "data_source_id" => "rehearsal-source",
                       "source_binding_id" => "rehearsal-binding",
                       "source_empty_reason" => "connection_test_failed",
                       "selected_source_evidence_state" => "connection_test_failed"
                     },
                     "context" => %{
                       "data_source_id" => "rehearsal-source",
                       "source_binding_id" => "rehearsal-binding",
                       "connection_test_result" => "failed"
                     }
                   }
                 }
               }
             ]
           } = PublishReadinessPresentation.build(validation)
  end

  test "presents unsupported observable scope as a dashboard editor action" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :unsupported_observable_scope,
            placement_id: "placement-ground-state",
            details: %{
              logical_source: :operational_observables,
              requested_scope_kind: :spacecraft,
              requested_scope_ids: [],
              unsupported_observables: ["ground.station.connection_state"]
            }
          }
        }
      ]
    }

    assert %{
             issues: [
               %{
                 message:
                   "Dashboard context cannot support selected operational observables: ground.station.connection_state.",
                 summary_rows: [
                   %{key: "placement_id", label: "Placement", value: "placement-ground-state"},
                   %{key: "requested_scope", label: "Context", value: "spacecraft"},
                   %{
                     key: "unsupported_observables",
                     label: "Observables",
                     value: "ground.station.connection_state"
                   }
                 ],
                 action: %{
                   label: "Change widget context",
                   target: "dashboard_editor",
                   params: %{
                     "placement_id" => "placement-ground-state",
                     "logical_source" => "operational_observables",
                     "scope_kind" => "spacecraft",
                     "source_empty_reason" => "unsupported_observable_scope",
                     "unsupported_observables" => "ground.station.connection_state"
                   },
                   typed_action: %{
                     "target" => "dashboard_editor",
                     "query" => %{
                       "placement_id" => "placement-ground-state",
                       "source_empty_reason" => "unsupported_observable_scope"
                     }
                   }
                 }
               }
             ]
           } = PublishReadinessPresentation.build(validation)
  end

  test "presents operational source capability blockers as editor guidance" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :unsupported_source_capability,
            placement_id: "placement-link-history",
            details: %{
              logical_source: :operational_observables,
              requested_sampling: :raw_series,
              supported_sampling: [:latest, :event_history],
              requested_observables: ["link.snr_db"],
              unsupported_observables: ["link.snr_db"],
              requested_products: [:link_rf],
              requested_source_products: [:link_rf_metric_history],
              requested_product_families: [:link_rf],
              supported_products: [:operational_metric_history],
              source_binding_id: "default_flight_operational_observables",
              data_source_id: "managed_operational_observables"
            }
          }
        }
      ]
    }

    assert %{
             issues: [
               %{
                 message: "Dashboard source cannot satisfy a planned widget request.",
                 action: %{
                   label: "Review operational history binding",
                   target: "dashboard_editor",
                   params: %{
                     "placement_id" => "placement-link-history",
                     "source_empty_reason" => "unsupported_source_capability",
                     "requested_observables" => "link.snr_db",
                     "unsupported_observables" => "link.snr_db",
                     "requested_sampling" => "raw_series",
                     "requested_source_products" => "link_rf_metric_history",
                     "requested_product_families" => "link_rf"
                   }
                 },
                 detail_rows: detail_rows
               }
             ]
           } = PublishReadinessPresentation.build(validation)

    assert %{label: "Requested source products", value: "link_rf_metric_history"} in detail_rows
    assert %{label: "Requested product families", value: "link_rf"} in detail_rows
  end
end
