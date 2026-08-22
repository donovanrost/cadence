defmodule Cadence.Applications.ActionDispatcherTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionDispatcher, ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  @host_context HostContext.spacecraft("mission-actions", "spacecraft-actions")

  test "rejects actions that the registered definition does not declare" do
    request = request("not_declared")

    assert {:error, :undeclared_application_action} =
             ActionDispatcher.dispatch(scope(), @host_context, request)
  end

  test "rejects action requests pinned to an unsupported application version" do
    request = %ActionRequest{request("disable") | application_version: 99}

    assert {:error, :unsupported_application_version} =
             ActionDispatcher.dispatch(scope(), @host_context, request)
  end

  test "requires an authenticated organization scope" do
    assert {:error, :application_action_scope_required} =
             ActionDispatcher.dispatch(%Scope{}, @host_context, request("disable"))
  end

  defp request(action_id) do
    %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      action_id: action_id
    }
  end

  defp scope, do: %Scope{organization_id: "org-actions"}
end
