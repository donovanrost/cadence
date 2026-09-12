defmodule Cadence.Applications.OpsConsole.Actions.UiInteractionsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.UiInteractions
  alias Cadence.Auth.{Scope, ServiceIdentity}

  test "declares only the owned alarm and timeline host bindings" do
    assert UiInteractions.bindings() == [
             {"alarms", "filter"},
             {"alarms", "reset_filters"},
             {"timeline", "apply_timeline_filters"},
             {"timeline", "clear_timeline_selection"}
           ]
  end

  test "executes a mission-scoped alarm filter through the Phoenix read model" do
    request = request("filter", %{"filters" => %{"severity" => "critical"}})

    assert {:ok,
            %{
              "actionId" => "filter",
              "surfaceId" => "alarms",
              "missionId" => "mission-1",
              "filters" => %{"severity" => "critical", "state" => "active"},
              "rows" => []
            }} =
             UiInteractions.execute(scope(), HostContext.mission("mission-1"), "alarms", request)
  end

  test "executes mission timeline filters through the Phoenix read model" do
    request = request("apply_timeline_filters", %{"timeline" => %{"category" => "operations"}})

    assert {:ok,
            %{
              "actionId" => "apply_timeline_filters",
              "surfaceId" => "timeline",
              "missionId" => "mission-1",
              "filters" => %{"category" => "operations"},
              "events" => [],
              "props" => %{"mission_id" => "mission-1", "query" => %{"category" => "operations"}}
            }} =
             UiInteractions.execute(
               scope(),
               HostContext.mission("mission-1"),
               "timeline",
               request
             )
  end

  test "rejects a host context for a different mission" do
    request = request("reset_filters", %{})

    assert {:error, :forbidden} =
             UiInteractions.execute(scope(), HostContext.mission("mission-2"), "alarms", request)
  end

  test "rejects unknown and malformed actions before domain execution" do
    unknown = request("refresh", %{})

    assert {:error, :unsupported_application_action} =
             UiInteractions.execute(scope(), HostContext.mission("mission-1"), "ops", unknown)

    malformed = request("filter", %{"filters" => %{"severity" => self()}})

    assert {:error, :unsupported_application_action} =
             UiInteractions.execute(
               scope(),
               HostContext.mission("mission-1"),
               "alarms",
               malformed
             )
  end

  defp request(action_id, params) do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action_id,
      params: params
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
