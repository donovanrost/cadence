defmodule Cadence.Applications.OpsRouteActionLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.OpsConsole

  @legacy_events %{
    "activation_requests" => ["review", "decide"],
    "alarms" => ["filter", "reset_filters"],
    "commands" => ["filter", "reset_filters", "follow_command", "clear_command_focus"],
    "contact_detail" => [
      "approve-provider-change",
      "reject-provider-change",
      "acknowledge-provider-change"
    ],
    "contact_plan_show" => ["submit-plan", "approve-plan", "reject-plan", "execute-plan"],
    "contact_requirement_new" => ["validate", "save"],
    "contact_requirement_show" => ["plan", "toggle-opportunity", "create-plan"],
    "contact_requirement_template" => [
      "validate-template",
      "create-template",
      "pause-template",
      "activate-template",
      "close-template"
    ],
    "contact_schedule" => ["validate", "search", "reserve", "cancel"],
    "dashboard_directory" => ["filter_dashboards", "toggle_dashboard_star", "restore_dashboard"],
    "dashboard_library" => ["stage-library-item", "create-library-item", "add-library-version"],
    "dashboard_new" => ["validate", "save"],
    "dashboard_playlist_present" => ["next-dashboard"],
    "dashboard_playlists" => ["create-playlist"],
    "dashboard_settings" => [
      "validate-settings",
      "save-settings",
      "create-share",
      "revoke-share",
      "create-snapshot",
      "archive-dashboard"
    ],
    "data_operations" => [
      "validate-request",
      "record-historical-workflow-request",
      "transition-group",
      "retry-group",
      "request-correction"
    ],
    "data_sources" => [
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
    ],
    "fleet_planning" => ["refresh-planning"],
    "fleet_planning_new" => ["validate-fleet-run", "create-fleet-run"],
    "fleet_planning_policy" => [
      "validate-policy",
      "save-policy",
      "approve-policy",
      "validate-grant",
      "issue-grant",
      "revoke-grant"
    ],
    "fleet_planning_run" => ["refresh-fleet-run", "repair-fleet-run"],
    "telemetry_explore" => [
      "apply_filters",
      "apply_question",
      "add_to_dashboard",
      "clear_selected_sample"
    ],
    "timeline" => ["apply_timeline_filters", "clear_timeline_selection"]
  }

  test "every removed listener remains declared or is an explicit residual" do
    specs = Map.new(OpsConsole.surface_specs(), &{&1.id, &1})

    assert @legacy_events == OpsConsole.residual_action_ledger()

    Enum.each(@legacy_events, fn {surface_id, events} ->
      assert Map.has_key?(specs, surface_id)
      surface = specs[surface_id]

      assert MapSet.new(events) == MapSet.new(surface.actions)
      assert Enum.all?(events, &(&1 in OpsConsole.action_ids()))
    end)

    assert {:residual, 77} = OpsConsole.route_action_completion()
  end
end
