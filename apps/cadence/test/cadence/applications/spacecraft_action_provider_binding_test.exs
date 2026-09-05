defmodule Cadence.Applications.SpacecraftActionProviderBindingTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext, Spacecraft}
  alias Cadence.Applications.Spacecraft.ActionProvider
  alias Cadence.Auth.Scope

  @expected [
    {"new", 1, "validate"},
    {"new", 1, "save"},
    {"profile_new", 1, "validate"},
    {"profile_new", 1, "save"},
    {"edit", 1, "validate"},
    {"edit", 1, "save"},
    {"applications", 1, "install"},
    {"applications", 1, "disable"},
    {"applications", 1, "uninstall"},
    {"telemetry_decom", 1, "save_configuration"},
    {"telemetry_decom", 1, "request_activation"},
    {"telemetry_decom", 1, "disable"}
  ]

  test "freezes the exact 12-row Spacecraft surface/action ledger" do
    definition_pairs =
      Spacecraft.definition().surfaces
      |> Enum.flat_map(fn surface ->
        Enum.map(surface.actions, &{surface.surface_id, surface.version, &1})
      end)

    assert definition_pairs == @expected
    assert ActionProvider.surface_action_bindings() == @expected
    assert :ok = ActionProvider.validate_bindings(@expected)
    assert length(Enum.uniq(@expected)) == 12
  end

  test "rejects omitted, wrong-version, cross-surface, and undeclared bindings" do
    base = %ActionRequest{
      application_key: "spacecraft",
      application_version: 1,
      action_id: "validate",
      surface_id: "new",
      surface_version: 1,
      params: %{}
    }

    requests = [
      %{base | surface_id: nil, surface_version: nil},
      %{base | surface_version: 2},
      %{base | action_id: "save_configuration", surface_id: "new"},
      %{base | action_id: "install", surface_id: "telemetry_decom"},
      %{base | action_id: "disable", surface_id: "new"},
      %{base | action_id: "not_declared"}
    ]

    for request <- requests do
      assert {:error, :unsupported_application_action} =
               ActionProvider.execute(
                 %Scope{},
                 HostContext.spacecraft("mission-spacecraft", "spacecraft-1"),
                 request
               )
    end
  end

  test "rejects duplicate binding rows" do
    assert {:error, :duplicate_action_bindings} =
             ActionProvider.validate_bindings(@expected ++ [List.first(@expected)])
  end
end
