defmodule CadenceWeb.ApplicationHostBridgeTest do
  use ExUnit.Case, async: true

  alias Cadence.Auth.Scope
  alias CadenceWeb.ApplicationHostBridge

  test "rejects recursively oversized query input before provider dispatch" do
    params = %{"params" => Enum.to_list(1..101)}

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationHostBridge.query(%Scope{}, %{}, params)
  end

  test "rejects invalid action scalar input before provider dispatch" do
    params = %{"input" => %{"value" => self()}}

    assert {:error, :application_surface_bounds_exceeded} =
             ApplicationHostBridge.action(%Scope{}, %{}, params, "bridge-test-key")
  end

  test "returns stable host ids for every application scope" do
    assert ApplicationHostBridge.host_dom_id(:mission) == "mission-application-host"
    assert ApplicationHostBridge.host_dom_id(:spacecraft) == "spacecraft-application-host"
    assert ApplicationHostBridge.host_dom_id(:organization) == "organization-application-host"
    assert ApplicationHostBridge.host_dom_id(:user) == "user-application-host"
    assert ApplicationHostBridge.host_dom_id(:admin) == "admin-application-host"
  end
end
