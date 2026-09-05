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
             {"ops", :ops_workspace, %{query_id: "cadence.ops.console", version: 1}}
           ]

    assert Enum.at(definition.surfaces, 1).actions == [
             "validate",
             "save",
             "filter",
             "refresh",
             "select",
             "open_data_link",
             "open_evidence",
             "set_chart_time_range"
           ]

    assert length(definition.surfaces) == 30
    assert length(definition.actions) == 82
    assert Enum.count(definition.surfaces, &(&1.placement == :ops_workspace)) == 29

    assert Enum.uniq(Enum.map(definition.surfaces, & &1.surface_id)) ==
             Enum.map(definition.surfaces, & &1.surface_id)

    assert {:residual, 77} = OpsConsole.route_action_completion()
  end

  test "contributes exact release identity for each surface" do
    contributions = OpsConsole.release_contributions()

    assert length(contributions) == 30

    assert Enum.take(contributions, 2) |> Enum.map(&ReleaseContribution.key/1) == [
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
    assert Enum.map(OpsConsole.surface_query_contributions(), & &1.query_id) ==
             Enum.map(OpsConsole.definition().surfaces, & &1.data_contract.query_id)

    assert OpsConsole.action_provider() == Cadence.Applications.OpsConsole.ActionProvider
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
             {"ops", :operations, :mission, :ops_workspace, "cadence.ops.console",
              [
                "validate",
                "save",
                "filter",
                "refresh",
                "select",
                "open_data_link",
                "open_evidence",
                "set_chart_time_range"
              ]},
             {"contact_requirement_list", :collection, :mission, :ops_workspace,
              "cadence.ops.contact_requirement_list", []},
             {"contact_requirement_new", :configuration, :mission, :ops_workspace,
              "cadence.ops.contact_requirement_new", ["validate", "save"]},
             {"contact_requirement_show", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.contact_requirement_show",
              ["plan", "toggle-opportunity", "create-plan"]},
             {"contact_requirement_template", :configuration, :mission, :ops_workspace,
              "cadence.ops.contact_requirement_template",
              [
                "validate-template",
                "create-template",
                "pause-template",
                "activate-template",
                "close-template"
              ]},
             {"contact_schedule", :operations, :mission, :ops_workspace,
              "cadence.ops.contact_schedule", ["validate", "search", "reserve", "cancel"]},
             {"contact_plan_show", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.contact_plan_show",
              ["submit-plan", "approve-plan", "reject-plan", "execute-plan"]},
             {"contact_detail", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.contact_detail",
              ["approve-provider-change", "reject-provider-change", "acknowledge-provider-change"]},
             {"contact_record", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.contact_record", []},
             {"dashboard_directory", :collection, :mission, :ops_workspace,
              "cadence.ops.dashboard_directory",
              ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"]},
             {"dashboard_new", :configuration, :mission, :ops_workspace,
              "cadence.ops.dashboard_new", ["validate", "save"]},
             {"dashboard_library", :collection, :mission, :ops_workspace,
              "cadence.ops.dashboard_library",
              ["stage-library-item", "create-library-item", "add-library-version"]},
             {"dashboard_playlists", :collection, :mission, :ops_workspace,
              "cadence.ops.dashboard_playlists", ["create-playlist"]},
             {"dashboard_playlist_present", :operations, :mission, :ops_workspace,
              "cadence.ops.dashboard_playlist_present", ["next-dashboard"]},
             {"dashboard_settings", :configuration, :mission, :ops_workspace,
              "cadence.ops.dashboard_settings",
              [
                "validate-settings",
                "save-settings",
                "create-share",
                "revoke-share",
                "create-snapshot",
                "archive-dashboard"
              ]},
             {"dashboard_share", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.dashboard_share", []},
             {"dashboard_snapshot", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.dashboard_snapshot", []},
             {"dashboard_diagnostics", :activity, :mission, :ops_workspace,
              "cadence.ops.dashboard_diagnostics", []},
             {"fleet_planning", :operations, :mission, :ops_workspace,
              "cadence.ops.fleet_planning", ["refresh-planning"]},
             {"fleet_planning_new", :configuration, :mission, :ops_workspace,
              "cadence.ops.fleet_planning_new", ["validate-fleet-run", "create-fleet-run"]},
             {"fleet_planning_policy", :configuration, :mission, :ops_workspace,
              "cadence.ops.fleet_planning_policy",
              [
                "validate-policy",
                "save-policy",
                "approve-policy",
                "validate-grant",
                "issue-grant",
                "revoke-grant"
              ]},
             {"fleet_planning_run", :subject_detail, :mission, :ops_workspace,
              "cadence.ops.fleet_planning_run", ["refresh-fleet-run", "repair-fleet-run"]},
             {"activation_requests", :operations, :mission, :ops_workspace,
              "cadence.ops.activation_requests", ["review", "decide"]},
             {"commands", :operations, :mission, :ops_workspace, "cadence.ops.commands",
              ["filter", "reset_filters", "follow_command", "clear_command_focus"]},
             {"telemetry_explore", :operations, :mission, :ops_workspace,
              "cadence.ops.telemetry_explore",
              ["apply_filters", "apply_question", "add_to_dashboard", "clear_selected_sample"]},
             {"data_operations", :operations, :mission, :ops_workspace,
              "cadence.ops.data_operations",
              [
                "validate-request",
                "record-historical-workflow-request",
                "transition-group",
                "retry-group",
                "request-correction"
              ]},
             {"data_sources", :configuration, :mission, :ops_workspace,
              "cadence.ops.data_sources",
              [
                "open-register-source",
                "cancel-register-source",
                "register-source",
                "open-change-binding",
                "cancel-change-binding",
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
