defmodule Cadence.Applications.OpsConsoleActionProviderTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext, OpsConsole}
  alias Cadence.Applications.OpsConsole.ActionProvider
  alias Cadence.Auth.{Scope, ServiceIdentity}

  test "rejects an action that is not admitted on its surface" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh",
      surface_id: "ops",
      surface_version: 1,
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "rejects an undeclared surface/action pair" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "reset_filters",
      surface_id: "alarms",
      surface_version: 1,
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "rejects a cross-surface action even when the action exists elsewhere" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "filter",
      surface_id: "commands",
      surface_version: 1,
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "rejects a missing or wrong surface version" do
    for surface_version <- [nil, 2] do
      request = %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: "filter",
        surface_id: "alarms",
        surface_version: surface_version,
        params: %{}
      }

      assert {:error, :unsupported_application_action} =
               ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
    end
  end

  test "rejects an action with a cross-mission parameter" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh",
      surface_id: "ops",
      surface_version: 1,
      params: %{"mission_id" => "mission-2"}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "preserves an admitted adapter's malformed input error" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "filter_dashboards",
      surface_id: "dashboard_directory",
      surface_version: 1,
      params: %{"directory" => %{"query" => self()}}
    }

    assert {:error, %Cadence.Applications.ActionFailure{code: "invalid_action_input"}} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "preserves an admitted adapter's authorization error" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "filter_dashboards",
      surface_id: "dashboard_directory",
      surface_version: 1,
      params: %{"directory" => %{}}
    }

    assert {:error, :forbidden} =
             ActionProvider.execute(denied_scope(), HostContext.mission("mission-1"), request)
  end

  test "action dispatch covers exactly the declared Ops vocabulary" do
    assert Enum.sort(OpsConsole.action_ids()) ==
             OpsConsole.definition().actions |> Enum.map(& &1.action_id) |> Enum.sort()
  end

  test "composed cohort bindings are unique" do
    assert ActionProvider.duplicate_binding_keys() == []
    assert ActionProvider.binding_keys() == Enum.uniq(ActionProvider.binding_keys())
    assert {"dashboard_editor", "publish_dashboard"} in ActionProvider.binding_keys()
    assert {"alarms", "filter"} in ActionProvider.binding_keys()
    assert {"contact_schedule", "search"} in ActionProvider.binding_keys()
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

  defp denied_scope do
    identity = %ServiceIdentity{
      service_identity_id: "service-denied",
      organization_id: "org-1",
      mission_id: "mission-other",
      display_name: "Denied Ops service",
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
