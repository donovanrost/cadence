defmodule Cadence.Applications.TelemetryDecomActionProviderBindingTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext, Registry}
  alias Cadence.Applications.TelemetryDecom.ActionProvider
  alias Cadence.Auth.Scope

  @expected [
    {"manage", 1, "save_configuration"},
    {"manage", 1, "request_activation"},
    {"manage", 1, "disable"},
    {"packet_bindings", 1, "save_packet_bindings"}
  ]

  test "freezes the exact 4-row Telemetry Decom surface/action ledger" do
    {:ok, definition} = Registry.fetch("telemetry_decom", 1)

    definition_pairs =
      definition.surfaces
      |> Enum.flat_map(fn surface ->
        Enum.map(surface.actions, &{surface.surface_id, surface.version, &1})
      end)

    assert definition_pairs == @expected
    assert ActionProvider.surface_action_bindings() == @expected
    assert :ok = ActionProvider.validate_bindings(@expected)
    assert length(Enum.uniq(@expected)) == 4
  end

  test "rejects omitted, wrong-version, cross-surface, and undeclared bindings" do
    base = %ActionRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      action_id: "save_configuration",
      surface_id: "manage",
      surface_version: 1,
      params: %{}
    }

    requests = [
      %{base | surface_id: nil, surface_version: nil},
      %{base | surface_version: 2},
      %{base | action_id: "save_packet_bindings", surface_id: "manage"},
      %{base | action_id: "save_configuration", surface_id: "packet_bindings"},
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

  test "rejects duplicate binding rows" do
    assert {:error, :duplicate_action_bindings} =
             ActionProvider.validate_bindings(@expected ++ [List.first(@expected)])
  end
end
