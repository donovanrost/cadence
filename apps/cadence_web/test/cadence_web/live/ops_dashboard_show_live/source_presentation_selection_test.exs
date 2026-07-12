defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentationSelectionTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DashboardResolveResult
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  test "source_selection_summaries expose selected and skipped dashboard sources" do
    result = %DashboardResolveResult{
      plan_metadata: %{
        source_selection_by_request_id: %{
          "req-telemetry" => %{
            logical_source: :telemetry,
            strategy: :current_binding,
            selected_source_binding_id: "secondary-flight",
            selected_data_source_id: "secondary-questdb",
            selected_dataset: "flight",
            requested_realm: :flight,
            candidate_count: 2,
            eligible_candidate_count: 1,
            candidates: [
              %{
                binding_id: "primary-flight",
                data_source_id: "primary-questdb",
                logical_source: :telemetry,
                realm: :flight,
                decision: :rejected,
                started_at: ~U[2026-06-21 20:00:00Z],
                ended_at: ~U[2026-06-21 21:00:00Z],
                reasons: [:source_unavailable],
                source_health: :unavailable,
                source_health_reason: :source_connection_failed,
                source_health_freshness: :fresh,
                source_readiness_policy_id: :default,
                capability_posture: %{
                  requested_products: [:link_rf_metric_history],
                  supported_products: [:transport_bitrate_history],
                  unsupported: [
                    %{
                      capability: :products,
                      requested: [:link_rf_metric_history],
                      supported: [:transport_bitrate_history],
                      missing: [:link_rf_metric_history],
                      fallback: :none
                    }
                  ]
                }
              },
              %{
                binding_id: "secondary-flight",
                data_source_id: "secondary-questdb",
                logical_source: :telemetry,
                realm: :flight,
                decision: :selected,
                reasons: []
              }
            ]
          }
        }
      }
    }

    assert [
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
               skipped_candidate_count: 1,
               state: :selected,
               state_text: "selected",
               candidates: [rejected, selected]
             }
           ] = SourcePresentation.source_selection_summaries(result)

    assert rejected.binding_id == "primary-flight"
    assert rejected.decision == :rejected
    assert rejected.reasons_text == "source_unavailable"
    assert rejected.source_health_text == "unavailable"
    assert rejected.source_health_reason_text == "source_connection_failed"
    assert rejected.source_health_freshness_text == "fresh"
    assert rejected.requested_products_text == "link_rf_metric_history"
    assert rejected.supported_products_text == "transport_bitrate_history"
    assert rejected.missing_products_text == "link_rf_metric_history"
    assert rejected.readiness_policy_id_text == "default"
    assert rejected.started_at_text == "2026-06-21T20:00:00Z"
    assert rejected.ended_at_text == "2026-06-21T21:00:00Z"
    assert rejected.inventory_action_label == "Open source inventory"

    assert rejected.inventory_query == %{
             "data_source_id" => "primary-questdb",
             "logical_source" => "telemetry",
             "realm" => "flight",
             "source_binding_id" => "primary-flight"
           }

    assert selected.binding_id == "secondary-flight"
    assert selected.decision == :selected
    assert selected.reasons_text == ""

    assert selected.inventory_query == %{
             "data_source_id" => "secondary-questdb",
             "logical_source" => "telemetry",
             "realm" => "flight",
             "source_binding_id" => "secondary-flight"
           }
  end
end
