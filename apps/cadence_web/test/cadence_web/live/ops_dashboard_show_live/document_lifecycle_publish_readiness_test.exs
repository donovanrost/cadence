defmodule CadenceWeb.OpsDashboardShowLive.DocumentLifecyclePublishReadinessTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, ValidationResult}
  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle

  test "builds reasoned publish validation freshness for current drafts" do
    freshness =
      document(2, %{})
      |> DocumentLifecycle.publish_validation_freshness_for(%{
        draft_version: 2,
        latest_version: 2,
        published_version: 1
      })

    assert Map.take(freshness, [
             :draft_version,
             :summary_draft_version,
             :latest_version,
             :published_version,
             :state,
             :state_label,
             :reason,
             :reason_label,
             :message
           ]) == %{
             draft_version: "2",
             summary_draft_version: "2",
             latest_version: "2",
             published_version: "1",
             state: "current",
             state_label: "current draft",
             reason: "draft_current",
             reason_label: "draft current",
             message: "Publish readiness was evaluated against the current draft version."
           }

    assert is_binary(freshness.evaluated_at)
  end

  test "builds reasoned publish validation freshness for stale drafts" do
    freshness =
      document(2, %{})
      |> DocumentLifecycle.publish_validation_freshness_for(%{
        draft_version: 3,
        latest_version: 3,
        published_version: 1
      })

    assert Map.take(freshness, [:state, :state_label, :reason, :reason_label, :message]) == %{
             state: "stale",
             state_label: "stale draft",
             reason: "draft_version_changed",
             reason_label: "draft changed",
             message: "The dashboard draft changed after this publish readiness check."
           }
  end

  test "builds reasoned publish validation freshness for unknown draft summaries" do
    freshness = DocumentLifecycle.publish_validation_freshness_for(document(2, %{}), nil)

    assert Map.take(freshness, [:state, :state_label, :reason, :reason_label, :message]) == %{
             state: "unknown",
             state_label: "draft state unknown",
             reason: "draft_version_unknown",
             reason_label: "draft unknown",
             message: "The current draft version could not be compared to the dashboard summary."
           }
  end

  test "builds source evidence freshness when current draft has stale source warnings" do
    validation = stale_source_validation()

    freshness =
      document(2, %{})
      |> DocumentLifecycle.publish_validation_freshness_for(
        %{draft_version: 2, latest_version: 2, published_version: 1},
        validation
      )

    assert Map.take(freshness, [:state, :state_label, :reason, :reason_label, :message]) == %{
             state: "stale",
             state_label: "source evidence stale",
             reason: "source_watermark_stale",
             reason_label: "source stale",
             message:
               "Source watermark evidence is stale; re-check readiness after source data advances."
           }
  end

  test "builds publish readiness payload with freshness reason and source evidence codes" do
    payload =
      DocumentLifecycle.publish_readiness_payload_for(
        document(2, %{}),
        stale_source_validation(),
        %{draft_version: 2, latest_version: 2, published_version: 1}
      )

    assert %{
             "draft_version" => 2,
             "result" => "resolved_with_warnings",
             "valid" => true,
             "warning_count" => 1,
             "issue_codes" => ["stale_data"],
             "source_warning_codes" => ["stale_data"],
             "source_evidence_contexts" => [
               %{
                 "warning_code" => "stale_data",
                 "placement_id" => "tile-1",
                 "source_request_id" => "request-telemetry-latest",
                 "logical_source" => "telemetry",
                 "source_binding_id" => "rehearsal-binding",
                 "data_source_id" => "rehearsal-source",
                 "realm" => "rehearsal",
                 "dataset" => "ai-and-t",
                 "time_mode" => "replay_run",
                 "replay_run_id" => "replay-run-7",
                 "requested_data_source_id" => "requested-source",
                 "requested_source_binding_id" => "requested-binding"
               }
             ],
             "freshness_state" => "stale",
             "freshness_reason" => "source_watermark_stale",
             "freshness_reason_label" => "source stale",
             "freshness_message" =>
               "Source watermark evidence is stale; re-check readiness after source data advances."
           } = payload

    assert [
             %{
               "id" => "warning:stale_data:tile-1:stale_data",
               "code" => "stale_data",
               "severity" => "warning"
             }
           ] =
             Map.fetch!(payload, "issue_summaries")
  end

  test "builds publish readiness payload for failed source connection tests" do
    validation = %ValidationResult{
      valid?: false,
      errors: [
        %{
          code: :unready_publish_source_request,
          details: %{
            source_warning_code: :source_connection_failed,
            placement_id: "tile-1",
            details: %{
              source_request_id: "request-telemetry-latest",
              logical_source: :telemetry,
              binding_id: "rehearsal-binding",
              data_source_id: "rehearsal-source",
              realm: :rehearsal,
              dataset: "ai-and-t",
              connection_test_result: "failed",
              connection_test_kind: "adapter_io",
              connection_test_message: "Adapter connection test failed."
            }
          }
        }
      ]
    }

    payload =
      DocumentLifecycle.publish_readiness_payload_for(
        document(2, %{}),
        validation,
        %{draft_version: 2, latest_version: 2, published_version: 1}
      )

    assert payload["result"] == "still_blocked"
    assert payload["source_warning_codes"] == ["source_connection_failed"]

    assert [
             %{
               "warning_code" => "source_connection_failed",
               "source_request_id" => "request-telemetry-latest",
               "logical_source" => "telemetry",
               "source_binding_id" => "rehearsal-binding",
               "data_source_id" => "rehearsal-source",
               "connection_test_result" => "failed",
               "connection_test_kind" => "adapter_io",
               "connection_test_message" => "Adapter connection test failed."
             }
           ] = payload["source_evidence_contexts"]

    assert [
             %{
               "code" => "unready_publish_source_request",
               "message" => "Dashboard source connection test failed for the publish context.",
               "action" => %{
                 "label" => "Fix source connection",
                 "target" => "data_sources",
                 "params" => %{
                   "data_source_id" => "rehearsal-source",
                   "source_binding_id" => "rehearsal-binding",
                   "source_empty_reason" => "connection_test_failed",
                   "selected_evidence_kind" => "source",
                   "selected_source_evidence_mode" => "health",
                   "selected_source_evidence_state" => "connection_test_failed",
                   "connection_test_result" => "failed",
                   "connection_test_kind" => "adapter_io",
                   "connection_test_message" => "Adapter connection test failed."
                 },
                 "typed_action" => %{
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
                     "source_empty_reason" => "connection_test_failed",
                     "selected_evidence_kind" => "source",
                     "selected_source_evidence_mode" => "health",
                     "selected_source_evidence_state" => "connection_test_failed",
                     "connection_test_result" => "failed",
                     "connection_test_kind" => "adapter_io",
                     "connection_test_message" => "Adapter connection test failed."
                   },
                   "context" => %{
                     "data_source_id" => "rehearsal-source",
                     "source_binding_id" => "rehearsal-binding",
                     "realm" => "rehearsal",
                     "dataset" => "ai-and-t",
                     "source_request_id" => "request-telemetry-latest",
                     "logical_source" => "telemetry",
                     "source_empty_reason" => "connection_test_failed",
                     "connection_test_result" => "failed",
                     "connection_test_kind" => "adapter_io",
                     "connection_test_message" => "Adapter connection test failed.",
                     "selected_evidence_kind" => "source",
                     "selected_source_evidence_mode" => "health",
                     "selected_source_evidence_state" => "connection_test_failed"
                   },
                   "presentation" => "button",
                   "source" => "warning"
                 }
               }
             }
           ] = payload["issue_summaries"]

    assert [
             %{
               "action_id" => "dashboard-publish-source-readiness-action",
               "issue_id" =>
                 "error:unready_publish_source_request:tile-1:source_connection_failed",
               "target" => "source_health",
               "query" => %{
                 "data_source_id" => "rehearsal-source",
                 "source_binding_id" => "rehearsal-binding",
                 "source_empty_reason" => "connection_test_failed",
                 "selected_source_evidence_state" => "connection_test_failed"
               }
             }
           ] = payload["typed_remediation_actions"]
  end

  defp stale_source_validation do
    %ValidationResult{
      warnings: [
        %{
          code: :stale_data,
          details: %{
            source_warning_code: :stale_data,
            placement_id: "tile-1",
            details: %{
              source_request_id: "request-telemetry-latest",
              logical_source: :telemetry,
              source_binding_id: "rehearsal-binding",
              data_source_id: "rehearsal-source",
              realm: :rehearsal,
              dataset: "ai-and-t",
              time_mode: :replay_run,
              replay_run_id: "replay-run-7",
              requested_data_source_id: "requested-source",
              requested_source_binding_id: "requested-binding"
            }
          }
        }
      ]
    }
  end

  defp document(version, defaults) do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard",
      defaults: defaults,
      metadata: %{version: version}
    }
  end
end
