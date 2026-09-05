defmodule Cadence.Applications.OpsRouteActionLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.OpsConsole
  alias Cadence.Applications.OpsConsole.ActionProvider

  @residual_action_ledger %{
    "workspace" => [],
    "ops" => [
      "validate",
      "save",
      "filter",
      "refresh",
      "select",
      "open_data_link",
      "open_evidence",
      "set_chart_time_range"
    ],
    "contact_requirement_list" => [],
    "contact_requirement_new" => [],
    "contact_requirement_show" => ["toggle-opportunity"],
    "contact_requirement_template" => [],
    "contact_schedule" => [],
    "contact_plan_show" => [],
    "contact_detail" => [],
    "contact_record" => [],
    "dashboard_directory" => [],
    "dashboard_show" => [],
    "dashboard_editor" => [],
    "dashboard_activity" => [],
    "dashboard_new" => [],
    "dashboard_library" => [],
    "dashboard_playlists" => [],
    "dashboard_playlist_present" => [],
    "dashboard_settings" => [],
    "dashboard_share" => [],
    "dashboard_snapshot" => [],
    "dashboard_diagnostics" => [],
    "fleet_planning" => [],
    "fleet_planning_new" => ["validate-fleet-run"],
    "fleet_planning_policy" => ["validate-policy", "validate-grant"],
    "fleet_planning_run" => [],
    "activation_requests" => ["review"],
    "commands" => ["filter", "reset_filters", "follow_command", "clear_command_focus"],
    "telemetry_explore" => [
      "apply_filters",
      "apply_question",
      "add_to_dashboard",
      "clear_selected_sample"
    ],
    "data_operations" => [],
    "data_operations_manage" => [],
    "data_sources" => [
      "open-register-source",
      "cancel-register-source",
      "open-change-binding",
      "cancel-change-binding"
    ],
    "data_source_registration" => [],
    "data_source_settings" => [],
    "alarms" => [],
    "timeline" => []
  }

  test "provider and residual actions form an exact disjoint surface partition" do
    declared_pairs = MapSet.new(OpsConsole.surface_action_pairs())
    provider_pairs = MapSet.new(ActionProvider.binding_keys())
    residual_pairs = residual_pairs()

    assert length(OpsConsole.definition().actions) == 103
    assert @residual_action_ledger == OpsConsole.residual_action_ledger()
    assert ActionProvider.duplicate_binding_keys() == []
    assert MapSet.size(provider_pairs) == length(ActionProvider.binding_keys())
    assert MapSet.size(residual_pairs) == residual_pair_count()
    assert MapSet.disjoint?(provider_pairs, residual_pairs)
    assert MapSet.union(provider_pairs, residual_pairs) == declared_pairs
    assert MapSet.equal?(declared_pairs, MapSet.union(provider_pairs, residual_pairs))

    specs = Map.new(OpsConsole.surface_specs(), &{&1.id, &1})

    assert Map.keys(OpsConsole.residual_action_ledger()) |> Enum.sort() ==
             Map.keys(specs) |> Enum.sort()

    Enum.each(OpsConsole.surface_specs(), fn surface ->
      declared = MapSet.new(Enum.map(surface.actions, &{surface.id, &1}))

      provider =
        MapSet.filter(provider_pairs, fn {surface_id, _action} -> surface_id == surface.id end)

      residual =
        MapSet.filter(residual_pairs, fn {surface_id, _action} -> surface_id == surface.id end)

      assert MapSet.disjoint?(provider, residual)
      assert MapSet.union(provider, residual) == declared
    end)

    expected_residual_count =
      OpsConsole.residual_action_ledger()
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> length()

    assert {:residual, ^expected_residual_count} = OpsConsole.route_action_completion()
  end

  defp residual_pairs do
    OpsConsole.residual_action_ledger()
    |> Enum.flat_map(fn {surface_id, actions} -> Enum.map(actions, &{surface_id, &1}) end)
    |> MapSet.new()
  end

  defp residual_pair_count, do: residual_pairs() |> MapSet.size()
end
