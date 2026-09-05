defmodule Cadence.Applications.OpsConsoleActionProviderTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext, OpsConsole}
  alias Cadence.Applications.OpsConsole.ActionProvider
  alias Cadence.Auth.{Scope, ServiceIdentity}

  test "keeps declared legacy actions fail-closed until their exact adapter exists" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh",
      params: %{}
    }

    assert {:error, :ops_console_action_pending_exact_wiring} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "rejects an action with a cross-mission parameter" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh",
      params: %{"mission_id" => "mission-2"}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "rejects malformed action input" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "refresh",
      params: %{"nested" => %{"unsupported" => self()}}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(scope(), HostContext.mission("mission-1"), request)
  end

  test "action dispatch covers exactly the declared Ops vocabulary" do
    assert Enum.sort(OpsConsole.action_ids()) ==
             OpsConsole.definition().actions |> Enum.map(& &1.action_id) |> Enum.sort()
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
