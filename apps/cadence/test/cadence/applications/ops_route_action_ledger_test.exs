defmodule Cadence.Applications.OpsRouteActionLedgerTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.OpsConsole
  alias Cadence.Applications.OpsConsole.ActionProvider

  test "provider and residual actions form an exact disjoint surface partition" do
    declared_pairs = MapSet.new(OpsConsole.surface_action_pairs())
    provider_pairs = MapSet.new(ActionProvider.binding_keys())
    residual_pairs = residual_pairs()

    assert length(OpsConsole.definition().actions) == 89
    assert length(OpsConsole.surface_action_pairs()) == 108
    assert OpsConsole.residual_action_ledger() == Map.new(OpsConsole.surface_ids(), &{&1, []})
    assert ActionProvider.duplicate_binding_keys() == []
    assert length(ActionProvider.binding_keys()) == 108
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

    assert expected_residual_count == 0
    assert OpsConsole.route_action_completion() == {:complete, 0}
  end

  defp residual_pairs do
    OpsConsole.residual_action_ledger()
    |> Enum.flat_map(fn {surface_id, actions} -> Enum.map(actions, &{surface_id, &1}) end)
    |> MapSet.new()
  end

  defp residual_pair_count, do: residual_pairs() |> MapSet.size()
end
