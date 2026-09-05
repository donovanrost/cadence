defmodule Cadence.Applications.OpsConsoleActionProviderTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, OpsConsole}
  alias Cadence.Applications.OpsConsole.ActionProvider

  test "binds every declared action exactly once for the five mutable surfaces" do
    expected =
      OpsConsole.surface_action_pairs()
      |> Enum.filter(fn {surface_id, _action_id} ->
        surface_id in [
          "dashboard_editor",
          "dashboard_activity",
          "data_operations_manage",
          "data_source_registration",
          "data_source_settings"
        ]
      end)

    assert length(expected) == 37
    assert ActionProvider.bindings() == expected
    assert length(ActionProvider.bindings()) == length(Enum.uniq(ActionProvider.bindings()))
    assert ActionProvider.validate_bindings() == :ok
  end

  test "rejects omitted, wrong-version, and cross-surface requests before domain dispatch" do
    request = fn attrs ->
      struct!(
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          action_id: "register-source",
          params: %{}
        },
        attrs
      )
    end

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(%{}, %{}, request.(%{surface_id: "data_source_registration"}))

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(
               %{},
               %{},
               request.(%{surface_id: "data_source_registration", surface_version: 2})
             )

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(
               %{},
               %{},
               request.(%{surface_id: "data_source_settings", surface_version: 1})
             )
  end

  test "does not admit the actionless dashboard viewer surface" do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: "publish_dashboard",
      surface_id: "dashboard_show",
      surface_version: 1,
      params: %{}
    }

    assert {:error, :unsupported_application_action} =
             ActionProvider.execute(%{}, %{}, request)
  end
end
