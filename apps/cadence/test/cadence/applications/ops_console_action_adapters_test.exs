defmodule Cadence.Applications.OpsConsoleActionAdaptersTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions
  alias Cadence.Auth.Scope

  @scope %Scope{organization_id: "org-1"}
  @host_context HostContext.mission("mission-1")

  test "dashboard adapter fails closed for missing and wrong surface versions" do
    missing = request("dashboard_editor", nil, "layout_changed", %{})
    wrong = request("dashboard_editor", 2, "layout_changed", %{})

    assert {:error, :unsupported_application_action} =
             Actions.DashboardDeepActions.execute(@scope, @host_context, missing)

    assert {:error, :unsupported_application_action} =
             Actions.DashboardDeepActions.execute(@scope, @host_context, wrong)
  end

  test "mission and source adapters reject cross-surface action pairs" do
    source_request = request("data_source_settings", 1, "register-source", %{})
    mission_request = request("data_operations_manage", 1, "retry-group", %{})

    assert {:error, :unsupported_application_action} =
             Actions.DataSources.execute(@scope, @host_context, source_request)

    assert {:error, :invalid_action_input} =
             Actions.MissionOperations.execute(@scope, @host_context, mission_request)
  end

  test "source action payloads are exact before policy or domain calls" do
    request =
      request("data_source_settings", 1, "retry-deployment-run", %{
        "job-id" => "job-1",
        "unexpected" => "rejected"
      })

    assert {:error, :malformed_action_input} =
             Actions.DataSources.execute(@scope, @host_context, request)
  end

  defp request(surface_id, surface_version, action_id, params) do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action_id,
      surface_id: surface_id,
      surface_version: surface_version,
      params: params
    }
  end
end
