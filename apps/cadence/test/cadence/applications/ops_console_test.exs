defmodule Cadence.Applications.OpsConsoleTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ApplicationDefinition, OpsConsole, ReleaseContribution}

  test "declares both first-party mission Ops surfaces and workspace coverage" do
    assert %ApplicationDefinition{} = definition = OpsConsole.definition()
    assert ApplicationDefinition.validate(definition) == :ok
    assert definition.application_key == "ops_console"
    assert definition.installable_scopes == [:mission]

    assert Enum.map(definition.surfaces, &{&1.surface_id, &1.placement}) == [
             {"workspace", :application_workspace},
             {"ops", :ops_workspace}
           ]

    assert Enum.map(definition.surfaces, &{&1.surface_id, &1.actions}) == [
             {"workspace", []},
             {
               "ops",
               [
                 "validate",
                 "save",
                 "filter",
                 "refresh",
                 "select",
                 "open_data_link",
                 "open_evidence",
                 "set_chart_time_range"
               ]
             }
           ]

    assert Enum.map(definition.actions, & &1.action_id) == [
             "validate",
             "save",
             "filter",
             "refresh",
             "select",
             "open_data_link",
             "open_evidence",
             "set_chart_time_range"
           ]
  end

  test "contributes exact release identity for each surface" do
    contributions = OpsConsole.release_contributions()

    assert Enum.map(contributions, &ReleaseContribution.key/1) == [
             {"ops_console", 1, "workspace", 1},
             {"ops_console", 1, "ops", 1}
           ]

    assert Enum.all?(contributions, fn contribution ->
             ReleaseContribution.validate(contribution) == :ok and
               contribution.remote_name == "cadence_ops_console" and
               contribution.manifest_path ==
                 "/assets/application-host/ops-console/mf-manifest.json"
           end)
  end

  test "keeps query contributions and the action seam domain-owned" do
    assert Enum.map(OpsConsole.surface_query_contributions(), & &1.query_id) == [
             "cadence.ops.workspace",
             "cadence.ops.console"
           ]

    assert OpsConsole.action_provider() == Cadence.Applications.OpsConsole.ActionProvider
  end
end
