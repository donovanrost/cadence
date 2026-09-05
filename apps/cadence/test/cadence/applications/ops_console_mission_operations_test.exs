defmodule Cadence.Applications.OpsConsoleMissionOperationsTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.MissionOperations
  alias Cadence.Auth.{Scope, ServiceIdentity}

  @workflow_keys ~w(
    workflow run_id realm data_source_id source_binding_id observable_id point_id point_ids
    source_from source_to dashboard_id dashboard_version dashboard_time_mode
    dashboard_replay_run_id dashboard_data_view dashboard_limit_mode
    comparison_review_request_event_id comparison_review_request_kind comparison_review_open_count
    comparison_review_open_placement_ids comparison_review_workflow_kind
    comparison_review_workflow_action comparison_review_workflow_selection_kind
    comparison_review_workflow_selection_count comparison_review_primary_data_view
    comparison_review_compare_data_view comparison_review_scope_kind comparison_review_scope_ids
    comparison_review_contact_ids comparison_review_resource_ids comparison_review_transport_ids
    comparison_review_source_endpoint_ids comparison_review_ground_station_ids
    comparison_review_scope_link_ids reason confirmed
  )

  test "declares only the completed mission host bindings" do
    assert MissionOperations.bindings() == [
             {"activation_requests", "decide"},
             {"data_operations", "validate-request"},
             {"data_operations", "record-historical-workflow-request"},
             {"data_operations", "transition-group"},
             {"data_operations", "retry-group"},
             {"data_operations", "request-correction"}
           ]
  end

  test "returns the authoritative validation result for a valid request" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "validate-request",
      params: %{"historical_workflow_request" => Map.new(@workflow_keys, &{&1, ""})}
    }

    assert {:ok, %{"valid" => true}} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-1"),
               "data_operations",
               request
             )
  end

  test "rejects a host context from the wrong mission" do
    request = valid_request()

    assert {:error, :forbidden} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-2"),
               "data_operations",
               request
             )
  end

  test "rejects an unknown binding" do
    assert {:error, :unsupported_application_action} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-1"),
               "data_operations",
               %ActionRequest{
                 application_key: "ops_console",
                 application_version: 1,
                 action_id: "unknown",
                 params: %{}
               }
             )
  end

  test "rejects malformed JSON input" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "validate-request",
      params: %{"historical_workflow_request" => %{"workflow" => self()}}
    }

    assert {:error, :unsupported} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-1"),
               "data_operations",
               request
             )
  end

  defp valid_request do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "validate-request",
      params: %{"historical_workflow_request" => Map.new(@workflow_keys, &{&1, ""})}
    }
  end

  defp scope do
    identity = %ServiceIdentity{
      service_identity_id: "service-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: "Ops test service",
      lifecycle_state: :active
    }

    %Scope{
      actor_kind: :service,
      organization_id: "org-1",
      mission_id: "mission-1",
      service_identity: identity,
      capabilities: MapSet.new()
    }
  end
end
