defmodule Cadence.Management.Commanding.ApprovedCommandTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.{CommandApproval, CommandRequest}
  alias Cadence.Management.Commanding.ApprovedCommand

  test "captures an immutable approved basis independently of operational lifecycle" do
    approved_at = DateTime.utc_now()

    request =
      CommandRequest.new(%{
        command_request_id: "request-1",
        organization_id: "organization-1",
        mission_id: "mission-1",
        source_endpoint_ref: "endpoint-1",
        mission_model_revision_id: "mission-model-1",
        command_id: "command-1",
        lifecycle_state: :approved,
        requested_by: %{"user_id" => "requester"},
        resolved_argument_values: %{"mode" => 2},
        requested_at: DateTime.add(approved_at, -1, :second)
      })

    approval =
      CommandApproval.new(%{
        command_approval_id: "approval-1",
        organization_id: "organization-1",
        mission_id: "mission-1",
        command_request_id: "request-1",
        decision: :approved,
        decided_by: %{"user_id" => "approver"},
        decided_at: approved_at
      })

    assert {:ok, approved_command} = ApprovedCommand.new(request, approval)
    assert approved_command.command_request_id == "request-1"
    assert approved_command.resolved_argument_values == %{"mode" => 2}

    assert ApprovedCommand.matches_request?(approved_command, %{
             request
             | lifecycle_state: :queued
           })

    refute ApprovedCommand.matches_request?(approved_command, %{
             request
             | resolved_argument_values: %{"mode" => 3}
           })
  end
end
