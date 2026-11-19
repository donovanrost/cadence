defmodule Cadence.Applications.OpsConsoleMissionOperationsTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.MissionOperations
  alias Cadence.Auth.{Scope, ServiceIdentity}

  @data_operation_actions ~w(
    validate-request record-historical-workflow-request transition-group retry-group
    request-correction
  )

  test "declares only the activation decision; the data operations surfaces bind nothing" do
    assert MissionOperations.bindings() == [{"activation_requests", "decide"}]
  end

  # The data operations workflow decisions go through the native path (reason, evidence, lock);
  # the host action endpoint refuses every one, on both surfaces, whatever the input.
  test "refuses every data operations action on both surfaces" do
    for surface_id <- ~w(data_operations data_operations_manage),
        action_id <- @data_operation_actions do
      request = %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action_id,
        surface_id: surface_id,
        surface_version: 1,
        params: %{"group-id" => "group-1", "stage" => "approved"}
      }

      assert {:error, :unsupported_application_action} =
               MissionOperations.execute(
                 scope(),
                 HostContext.mission("mission-1"),
                 surface_id,
                 request
               ),
             "#{surface_id} #{action_id}"
    end
  end

  test "rejects a host context from the wrong mission" do
    assert {:error, :forbidden} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-2"),
               "activation_requests",
               decide_request()
             )
  end

  test "rejects an unknown binding" do
    assert {:error, :unsupported_application_action} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-1"),
               "activation_requests",
               %ActionRequest{
                 application_key: "ops_console",
                 application_version: 1,
                 action_id: "unknown",
                 params: %{}
               }
             )
  end

  test "rejects malformed JSON input" do
    request = %{decide_request() | params: %{"activation_decision" => %{"reason" => self()}}}

    assert {:error, :unsupported} =
             MissionOperations.execute(
               scope(),
               HostContext.mission("mission-1"),
               "activation_requests",
               request
             )
  end

  defp decide_request do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "decide",
      surface_id: "activation_requests",
      surface_version: 1,
      params: %{
        "activation_decision" => %{"request_id" => "request-1", "reason" => "Checked"},
        "decision" => "approved"
      }
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
