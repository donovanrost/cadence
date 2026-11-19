defmodule Cadence.Spacecraft.ConfigKinds.ScidHolds do
  @moduledoc """
  The same-SCID HOLD (`scid_shared_in_organization`, acknowledge; ux U81 §1): a spacecraft
  create, or an update that changes its SCID, when another mission of the same organization flies
  that SCID through a provider account this mission also uses. The provider's stations route by
  SCID, so they can't tell the two spacecraft's uplinks apart. Never across organizations.

  The kind doesn't know who is looking, so it raises ONE folded item per spacecraft that names no
  mission: `mission` nil, `mission_count` the number of missions. `Cadence.Control.Configuration`
  splits out a named item for each mission the viewer can open (`for_viewer/4`), so no other
  mission's id or name leaves through any other path.

  `details` always carries all four keys: `scid`, `provider_accounts` (`[%{id, name}]`, sorted by
  name, `name` nullable; the union on a folded item), `mission` (`%{id, name}` or nil) and
  `mission_count`. Sentences are ux's; an unnamed account is counted, never shown by id.

  The sharing read comes through the `:scid_sharing` adapter, so the spacecraft kind keeps no
  compile-time edge to ground networks.
  """

  @reason :scid_shared_in_organization

  @spec reason() :: atom()
  def reason, do: @reason

  @spec holds(binary(), binary(), [map()]) :: [map()]
  def holds(organization_id, mission_id, entries) do
    case Application.get_env(:cadence, :scid_sharing) do
      nil ->
        []

      sharing ->
        for {id, scid} <- new_scids(entries),
            shared = sharing.shared(organization_id, mission_id, scid),
            shared != [] do
          item(id, scid, Enum.flat_map(shared, & &1.provider_accounts), nil, length(shared))
        end
    end
  end

  @doc """
  One HOLD item: named (`mission` `%{id, name}`, count 1) or folded (`mission` nil, `count`
  missions the viewer can't open).
  """
  @spec item(binary(), non_neg_integer(), [map()], map() | nil, pos_integer()) :: map()
  def item(entity_id, scid, accounts, mission, count) do
    accounts =
      accounts |> Enum.uniq_by(& &1.id) |> Enum.sort_by(&{is_nil(&1.name), &1.name, &1.id})

    %{
      op_id: nil,
      change_id: nil,
      kind: "spacecraft",
      entity_id: entity_id,
      reason: @reason,
      blocking: false,
      sentence: sentence(scid, accounts, mission, count),
      details: %{
        scid: scid,
        provider_accounts: Enum.map(accounts, &Map.take(&1, [:id, :name])),
        mission: mission && Map.take(mission, [:id, :name]),
        mission_count: count
      }
    }
  end

  # Created spacecraft, and updated ones whose SCID changed.
  defp new_scids(entries) do
    for %{kind: "spacecraft", op: op, entity_id: id} = entry <- entries,
        op in [:create, :update],
        scid = scid(Map.get(entry, :proposed)),
        is_integer(scid),
        scid != scid(Map.get(entry, :previous)),
        do: {id, scid}
  end

  defp scid(%{"scid" => scid}), do: scid
  defp scid(_document), do: nil

  defp sentence(scid, accounts, mission, count) do
    "#{opening(mission, count)} SCID #{scid} through #{through(accounts)}. " <>
      "#{stations(accounts)} can't tell #{uplinks(mission, count)} apart."
  end

  defp opening(%{name: name}, _count),
    do: "Another mission in this organization, #{name}, also flies"

  defp opening(nil, 1), do: "Another mission in this organization also flies"
  defp opening(nil, count), do: "#{count} other missions in this organization also fly"

  defp uplinks(nil, count) when count > 1, do: "the spacecraft's uplinks"
  defp uplinks(_mission, _count), do: "the two spacecraft's uplinks"

  defp through(accounts) do
    named = for %{name: name} when is_binary(name) <- accounts, do: name

    case {named, length(accounts) - length(named)} do
      {_named, 0} -> join(named)
      {[], 1} -> "a provider account you share"
      {[], unnamed} -> "#{unnamed} provider accounts you share"
      {named, 1} -> join(named ++ ["1 other provider account"])
      {named, unnamed} -> join(named ++ ["#{unnamed} other provider accounts"])
    end
  end

  defp stations([%{name: name}]) when is_binary(name), do: "#{name}'s stations"
  defp stations([_unnamed]), do: "Its stations"
  defp stations(_accounts), do: "Their stations"

  defp join([only]), do: only
  defp join(words), do: Enum.join(Enum.drop(words, -1), ", ") <> " and " <> List.last(words)
end
