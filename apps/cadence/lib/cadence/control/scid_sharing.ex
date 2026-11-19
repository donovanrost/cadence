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
  alias Cadence.SpacecraftStore

  @type account :: %{id: binary(), name: binary() | nil}
  @type shared :: %{mission_id: binary(), provider_accounts: [account()]}

  @doc "Per other mission (by id), the provider accounts it shares with `mission_id`."
  @spec shared(binary(), binary(), non_neg_integer()) :: [shared()]
  def shared(organization_id, mission_id, scid) do
    case SpacecraftStore.missions_flying_scid(organization_id, scid, mission_id) do
      [] ->
        []

      others ->
        mine = account_ids(organization_id, mission_id)

        for other <- others,
            common = MapSet.intersection(mine, account_ids(organization_id, other)),
            MapSet.size(common) > 0 do
          %{
            mission_id: other,
            provider_accounts: Enum.map(common, &account(organization_id, &1))
          }
        end
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

  def for_viewer(%{checks: checks} = preview, %Scope{} = scope, %Mission{} = mission),
    do: %{preview | checks: Enum.map(checks, &viewer_check(&1, scope, mission))}

  def for_viewer(other, _scope, _mission), do: other

  defp viewer_check(%{items: items} = check, scope, mission),
    do: %{check | items: Enum.flat_map(items, &viewer_items(&1, scope, mission))}

  defp viewer_check(check, _scope, _mission), do: check

  defp viewer_items(%{entity_id: id, details: %{scid: scid}} = item, scope, mission) do
    if item[:reason] == ScidHolds.reason(),
      do: split(item, id, scid, scope, mission),
      else: [item]
  end

  defp viewer_items(item, _scope, _mission), do: [item]

  defp split(item, id, scid, scope, mission) do
    case shared(mission.organization_id, mission.mission_id, scid) do
      [] ->
        [item]

      shared ->
        {named, hidden} = Enum.reduce(shared, {[], []}, &by_visibility(&1, &2, scope))
        named_items(id, scid, named) ++ folded(id, scid, hidden)
    end
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
