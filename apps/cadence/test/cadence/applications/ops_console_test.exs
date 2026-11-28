defmodule Cadence.Applications.OpsConsoleTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ApplicationDefinition, OpsConsole, ReleaseContribution}

  test "declares the additive route-level cohort and preserves host entry points" do
    assert %ApplicationDefinition{} = definition = OpsConsole.definition()
    assert ApplicationDefinition.validate(definition) == :ok
    assert definition.application_key == "ops_console"
    assert definition.installable_scopes == [:mission]

    assert Enum.take(definition.surfaces, 2)
           |> Enum.map(&{&1.surface_id, &1.placement, &1.data_contract}) == [
             {"workspace", :application_workspace,
              %{query_id: "cadence.ops.workspace", version: 1}},
             {"telemetry_explore", :ops_workspace,
              %{query_id: "cadence.ops.telemetry_explore", version: 1}}
           ]

    assert length(definition.surfaces) == 7
    assert length(definition.actions) == 17
    assert Enum.count(definition.surfaces, &(&1.placement == :ops_workspace)) == 6

    assert Enum.uniq(Enum.map(definition.surfaces, & &1.surface_id)) ==
             Enum.map(definition.surfaces, & &1.surface_id)

    assert OpsConsole.route_action_completion() == {:complete, 0}
  end

  test "contributes exact release identity for each surface" do
    contributions = OpsConsole.release_contributions()

    assert length(contributions) == 7

    assert Enum.take(contributions, 1) |> Enum.map(&ReleaseContribution.key/1) == [
             {"ops_console", 1, "workspace", 1}
           ]

    assert Enum.all?(contributions, fn contribution ->
             ReleaseContribution.validate(contribution) == :ok and
               contribution.remote_name == "cadence_ops_console" and
               contribution.manifest_path ==
                 "/assets/application-host/ops-console/mf-manifest.json"
           end)
  end

  test "resolves non-workspace mission surfaces for filtered host catalogs" do
    definition = OpsConsole.definition()

    assert Enum.map(
             Cadence.Applications.Registry.workspace_surfaces(definition, :mission),
             & &1.surface_id
           ) == [
             "workspace"
           ]

    assert {:ok, surface} =
             Cadence.Applications.Registry.fetch_surface(
               definition,
               :mission,
               "telemetry_explore"
             )

    assert surface.placement == :ops_workspace
    assert surface.surface_id == "telemetry_explore"
  end

  test "keeps query contributions and the action seam domain-owned" do
    assert Enum.map(OpsConsole.surface_query_contributions(), & &1.query_id) ==
             Enum.map(OpsConsole.definition().surfaces, & &1.data_contract.query_id)

    assert OpsConsole.action_provider() == Cadence.Applications.OpsConsole.ActionProvider
  end

  test "declares exact deep-route query identity and fail-closed interaction ledgers" do
    assert OpsConsole.surface_query_contract("data_source_registration") ==
             {:ok, %{subject_param: nil, query_params: []}}

    assert Enum.all?(
             [
               "data_source_registration",
               "data_source_settings"
             ],
             fn surface_id ->
               ledger = OpsConsole.deep_route_interaction_ledger()[surface_id]

               expected =
                 Enum.filter(OpsConsole.surface_action_pairs(), &match?({^surface_id, _}, &1))

               ledger.host_actions == Enum.map(expected, &elem(&1, 1)) and
                 ledger.phoenix_events == []
             end
           )

    assert OpsConsole.route_action_completion() == {:complete, 0}

    Enum.each(OpsConsole.deep_route_interaction_ledger(), fn {surface_id, ledger} ->
      surface = Enum.find(OpsConsole.definition().surfaces, &(&1.surface_id == surface_id))

      assert surface
      assert MapSet.subset?(MapSet.new(ledger.host_actions), MapSet.new(surface.actions))

      assert MapSet.subset?(
               MapSet.new(ledger.phoenix_events),
               MapSet.new(surface.actions)
             )
    end)
  end

  test "matches the complete route parity table" do
    assert Enum.map(OpsConsole.definition().surfaces, fn surface ->
             {
               surface.surface_id,
               surface.purpose,
               surface.scope,
               surface.placement,
               surface.data_contract.query_id,
               surface.actions
             }
           end) == [
             {"workspace", :overview, :mission, :application_workspace, "cadence.ops.workspace",
              []},
             {"telemetry_explore", :operations, :mission, :ops_workspace,
              "cadence.ops.telemetry_explore", ["apply_filters", "apply_question"]},
             {"data_sources", :configuration, :mission, :ops_workspace,
              "cadence.ops.data_sources",
              [
                "register-source",
                "change-binding",
                "disable-source",
                "enable-source",
                "reconcile-tsdb-backend",
                "deprovision-tsdb-backend",
                "provision-tsdb-backend",
                "probe-source",
                "rotate-source-credential",
                "retry-deployment-run",
                "requeue-deployment-run"
              ]},
             {"data_source_registration", :configuration, :mission, :ops_workspace,
              "cadence.ops.data_source_registration", ["register-source"]},
             {"data_source_settings", :configuration, :mission, :ops_workspace,
              "cadence.ops.data_source_settings",
              [
                "change-binding",
                "disable-source",
                "enable-source",
                "reconcile-tsdb-backend",
                "deprovision-tsdb-backend",
                "provision-tsdb-backend",
                "probe-source",
                "rotate-source-credential",
                "retry-deployment-run",
                "requeue-deployment-run"
              ]},
             {"alarms", :operations, :mission, :ops_workspace, "cadence.ops.alarms",
              ["filter", "reset_filters"]},
             {"timeline", :activity, :mission, :ops_workspace, "cadence.ops.timeline",
              ["apply_timeline_filters", "clear_timeline_selection"]}
           ]
  end
end
