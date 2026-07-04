defmodule Cadence.Dashboards.PublishReadinessPayloadTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, PublishReadinessPayload, ValidationResult}

  test "builds reasoned freshness for current drafts" do
    freshness =
      document(2, %{})
      |> PublishReadinessPayload.publish_validation_freshness_for(%{
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
  end

  test "builds publish readiness payload with source evidence and typed remediation" do
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
      PublishReadinessPayload.publish_readiness_payload_for(
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
               "connection_test_result" => "failed"
             }
           ] = payload["source_evidence_contexts"]

    assert [
             %{
               "action_id" => "dashboard-publish-source-readiness-action",
               "issue_id" =>
                 "error:unready_publish_source_request:tile-1:source_connection_failed",
               "target" => "source_health",
               "kind" => "invoke",
               "query" => %{
                 "data_source_id" => "rehearsal-source",
                 "source_binding_id" => "rehearsal-binding",
                 "source_empty_reason" => "connection_test_failed",
                 "selected_source_evidence_state" => "connection_test_failed"
               }
             }
           ] = payload["typed_remediation_actions"]
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
