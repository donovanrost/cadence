defmodule Cadence.Control.ScidSharing do
  @moduledoc """
  Which other missions of the organization fly a SCID through a provider account this mission
  also uses (the same-SCID HOLD, ux U81 §1): a provider's stations route by SCID, so they can't
  tell the two spacecraft's uplinks apart. Never across organizations.

  A mission "uses" an account when any of its non-archived providers is on it, whether or not a
  transport selects that provider today (lead: over-counting is fine for a warning; a transport
  can only pick one of its own mission's providers). Configured as `:scid_sharing` so the
  spacecraft kind needs no compile-time edge to ground networks.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Configuration.Access
  alias Cadence.GroundNetworks.{MissionProviders, ProviderAccounts}
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft.ConfigKinds.ScidHolds
  alias Cadence.SpacecraftStore.Bulk

  @type account :: %{id: binary(), name: binary() | nil}
  @type shared :: %{mission_id: binary(), provider_accounts: [account()]}

  @doc """
  Per SCID, the other missions (by id) and the provider accounts each shares with `mission_id`:
  `%{scid => [shared]}`, a SCID nobody shares left out. The reads are one for the SCIDs, one for
  this mission's accounts, and one pair per other mission and per account found, however many
  SCIDs and spacecraft ask (#1049).
  """
  @spec shared_many(binary(), binary(), [non_neg_integer()]) :: %{non_neg_integer() => [shared()]}
  def shared_many(organization_id, mission_id, scids) do
    case Bulk.missions_flying_scids(organization_id, scids, mission_id) do
      flying when flying == %{} ->
        %{}

      flying ->
        mine = account_ids(organization_id, mission_id)
        common = common_accounts(organization_id, mine, flying)
        accounts = named_accounts(organization_id, common)

        for {scid, missions} <- flying,
            shared = sharing(missions, common, accounts),
            shared != [],
            into: %{},
            do: {scid, shared}
    end
  end

  # Per other mission, the provider accounts it shares with this one.
  defp common_accounts(organization_id, mine, flying) do
    flying
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Map.new(&{&1, MapSet.intersection(mine, account_ids(organization_id, &1))})
  end

  defp named_accounts(organization_id, common) do
    common
    |> Map.values()
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    |> Map.new(&{&1, account(organization_id, &1)})
  end

  defp sharing(missions, common, accounts) do
    for other <- missions, shared = Map.fetch!(common, other), MapSet.size(shared) > 0 do
      %{mission_id: other, provider_accounts: Enum.map(shared, &accounts[&1])}
    end
  end

  @doc """
  The same-SCID HOLDs of a preview (or of a submit/review refusal carrying one) as `scope` sees
  them: the kind's folded item becomes one named item per mission the viewer can open, sorted by
  name, plus one folded item counting the rest. Anything else passes through unchanged.
  """
  @spec for_viewer(term(), Scope.t(), Mission.t()) :: term()
  def for_viewer({:ok, %{checks: _} = preview}, scope, mission),
    do: {:ok, for_viewer(preview, scope, mission)}

  def for_viewer({:error, {tag, %{checks: _} = preview}}, scope, mission)
      when tag in [:holds_not_acknowledged, :holds_blocking, :checks_failed],
      do: {:error, {tag, for_viewer(preview, scope, mission)}}

  def for_viewer(%{checks: checks} = preview, %Scope{} = scope, %Mission{} = mission) do
    shared =
      shared_many(mission.organization_id, mission.mission_id, held_scids(checks))

    %{preview | checks: Enum.map(checks, &viewer_check(&1, scope, shared))}
  end

  def for_viewer(other, _scope, _mission), do: other

  # Every SCID the folded items name, read once for all of them.
  defp held_scids(checks) do
    for %{items: items} <- checks,
        %{details: %{scid: scid}} = item <- items,
        item[:reason] == ScidHolds.reason(),
        uniq: true,
        do: scid
  end

  defp viewer_check(%{items: items} = check, scope, shared),
    do: %{check | items: Enum.flat_map(items, &viewer_items(&1, scope, shared))}

  defp viewer_check(check, _scope, _shared), do: check

  defp viewer_items(%{entity_id: id, details: %{scid: scid}} = item, scope, shared) do
    if item[:reason] == ScidHolds.reason(),
      do: split(item, id, scid, scope, Map.get(shared, scid, [])),
      else: [item]
  end

  defp viewer_items(item, _scope, _shared), do: [item]

  defp split(item, _id, _scid, _scope, []), do: [item]

  defp split(_item, id, scid, scope, shared) do
    {named, hidden} = Enum.reduce(shared, {[], []}, &by_visibility(&1, &2, scope))
    named_items(id, scid, named) ++ folded(id, scid, hidden)
  end

  defp by_visibility(other, {named, hidden}, scope) do
    case Access.authorize(scope, other.mission_id, :read) do
      {:ok, %Mission{} = seen} -> {[{seen, other} | named], hidden}
      {:error, _not_visible} -> {named, [other | hidden]}
    end
  end

  defp named_items(id, scid, named) do
    named
    |> Enum.sort_by(fn {seen, _other} -> {seen.display_name, seen.mission_id} end)
    |> Enum.map(fn {seen, other} ->
      mission_ref = %{id: seen.mission_id, name: seen.display_name}
      ScidHolds.item(id, scid, other.provider_accounts, mission_ref, 1)
    end)
  end

  defp folded(_id, _scid, []), do: []

  defp folded(id, scid, hidden),
    do: [
      ScidHolds.item(id, scid, Enum.flat_map(hidden, & &1.provider_accounts), nil, length(hidden))
    ]

  defp account_ids(organization_id, mission_id) do
    for provider <- MissionProviders.list_providers(organization_id, mission_id),
        is_binary(provider.provider_account_id),
        into: MapSet.new(),
        do: provider.provider_account_id
  end

  defp account(organization_id, account_id) do
    case ProviderAccounts.fetch_for_system(organization_id, account_id) do
      {:ok, account, _version} -> %{id: account_id, name: account.display_name}
      {:error, _reason} -> %{id: account_id, name: nil}
    end
  end
end
