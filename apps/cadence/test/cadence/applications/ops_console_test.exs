defmodule Cadence.Applications.OpsConsoleTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ApplicationDefinition, OpsConsole}

  test "is a valid platform application on the mission" do
    assert %ApplicationDefinition{} = definition = OpsConsole.definition()
    assert ApplicationDefinition.validate(definition) == :ok
    assert definition.application_key == "ops_console"
    assert definition.installation_policy == :platform
    assert definition.installable_scopes == [:mission]
  end

  test "its identity names the extension package that contributes it" do
    assert OpsConsole.identity() == %{
             application_key: "ops_console",
             application_version: 1,
             package_id: "cadence.ops_console",
             package_version: 1
           }
  end
end
