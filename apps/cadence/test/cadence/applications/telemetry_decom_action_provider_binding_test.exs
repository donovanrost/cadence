defmodule Cadence.Applications.TelemetryDecomActionProviderBindingTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionContractLedger, ActionRequest, HostContext, Registry}
  alias Cadence.Applications.TelemetryDecom.ActionProvider
  alias Cadence.Auth.Scope

  test "Telemetry Decom is headless: no surface binds its actions (#669)" do
    {:ok, definition} = Registry.fetch("telemetry_decom", 1)

    assert definition.surfaces == []
    refute Enum.any?(ActionContractLedger.declared(), &(elem(&1, 0) == "telemetry_decom"))
  end

  test "refuses every request, with or without a surface" do
    base = %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      action_id: "save_configuration",
      surface_id: "manage",
      surface_version: 1,
      params: %{}
    }

    requests = [
      base,
      %{base | surface_id: nil, surface_version: nil},
      %{base | action_id: "request_activation"},
      %{base | action_id: "save_packet_bindings", surface_id: "packet_bindings"},
      %{base | action_id: "not_declared"}
    ]

    for request <- requests do
      assert {:error, :unsupported_application_action} =
               ActionProvider.execute(
                 %Scope{},
                 HostContext.spacecraft("mission-telemetry", "spacecraft-1"),
                 request
               )
    end
  end
end
