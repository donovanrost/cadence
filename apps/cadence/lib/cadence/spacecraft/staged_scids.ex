defmodule Cadence.Spacecraft.StagedScids do
  @moduledoc """
  The SCIDs a mission can't give a new spacecraft, and the stage-time refusal of one another
  staged change already uses (S9, #313; ux U20: a browser's guess can collide).

  **In use** (`in_use/2`): every live spacecraft's SCID, archived ones included (they keep theirs:
  the mission's unique index has no archive filter), plus every SCID a staged op of the mission's
  active change set gives a spacecraft (a create's document, or an update's `scid` change), by
  any author. A staged update that moves a live spacecraft to another SCID holds both until it
  applies.

  **Next free** (`next_free/1`): the lowest of 1..1023 not in use; never 0 (it stays accepted when
  typed); nil when none is free. Defined from `in_use/2`, so the two can't disagree.

  **At stage** (`conflicts/5`, `ConfigKind.stage_conflicts/5`): a spacecraft op whose SCID another
  spacecraft's staged op holds, or an earlier op of the same request gives to another spacecraft,
  is refused on its `scid` field with mms-ux's words (11-19). An op never collides with a staged
  op for the same spacecraft: re-staging replaces one's own op (fe-setup). The live collision
  ("already used in this mission") stays validate/6's, at preview and apply.
  """

  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.SpacecraftStore

  @kind "spacecraft"
  @suggested 1..1023

  @doc "Every SCID in use in the mission: live, archived and staged; sorted, deduplicated."
  @spec in_use(String.t(), String.t()) :: [non_neg_integer()]
  def in_use(organization_id, mission_id) do
    live =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id, include_archived: true)
      |> Enum.map(& &1.scid)

    staged = mission_id |> staged_ops() |> Enum.map(&scid/1)

    (live ++ staged) |> Enum.filter(&is_integer/1) |> Enum.uniq() |> Enum.sort()
  end

  @doc "The lowest of 1..1023 not in `in_use`; nil when none is free."
  @spec next_free([non_neg_integer()]) :: pos_integer() | nil
  def next_free(in_use) do
    taken = MapSet.new(in_use)
    Enum.find(@suggested, &(not MapSet.member?(taken, &1)))
  end

  @doc """
  `:ok`, or `{:error, {:invalid_op, index, [field_error]}}` for the first op of `prepared` (in
  request order) whose SCID another spacecraft's staged op holds, or an earlier op of the same
  request gives to another spacecraft. `set_state` words "the open change set" or "a change set
  under review".
  """
  @spec conflicts(String.t(), String.t(), String.t(), [map()], [map()]) ::
          :ok | {:error, {:invalid_op, non_neg_integer(), [map()]}}
  def conflicts(organization_id, mission_id, set_state, staged, prepared) do
    staged = holders(Enum.filter(staged, &spacecraft?/1))

    names =
      live_names(organization_id, mission_id, staged ++ Enum.filter(prepared, &spacecraft?/1))

    in_review = set_state == "in_review"

    context = %{staged: staged, names: names, in_review: in_review}

    prepared
    |> Enum.with_index()
    |> Enum.reduce_while(%{}, &check(&1, &2, context))
    |> case do
      {:error, _} = error -> error
      _earlier -> :ok
    end
  end

  # One op of the request, given the earlier ones' SCIDs: continue, or halt with the refusal.
  defp check({op, index}, earlier, context) do
    with true <- spacecraft?(op),
         scid when is_integer(scid) <- scid(op),
         {source, holder} <- clash(op, scid, context.staged, earlier) do
      error = refusal(scid, name(holder, context.names), source, context.in_review)
      {:halt, {:error, {:invalid_op, index, [error]}}}
    else
      nil -> {:cont, Map.put_new(earlier, scid(op), op)}
      _not_a_scid -> {:cont, earlier}
    end
  end

  # A staged op holds its SCID against every OTHER spacecraft; the same spacecraft's own op is
  # replaced by this stage, so it never counts.
  defp clash(op, scid, staged, earlier) do
    case other_holder(staged, scid, op) do
      nil -> request_clash(other(Map.get(earlier, scid), op))
      holder -> {"staged", holder}
    end
  end

  defp request_clash(nil), do: nil
  defp request_clash(holder), do: {"request", holder}

  defp other_holder(staged, scid, op),
    do: staged |> Enum.filter(&(scid(&1) == scid)) |> Enum.find(&(&1.entity_id != op.entity_id))

  defp other(nil, _op), do: nil
  defp other(holder, op), do: if(holder.entity_id != op.entity_id, do: holder)

  defp holders(staged), do: Enum.filter(staged, &is_integer(scid(&1)))

  # mms-ux 11-19 (field errors take no final period; U25: no name for another spacecraft).
  defp refusal(scid, name, source, in_review) do
    %{
      path: "scid",
      message: message(scid, name || "another spacecraft", source, in_review),
      details: %{scid: scid, spacecraft_name: name, source: source, in_review: in_review}
    }
  end

  defp message(scid, holder, "request", _in_review),
    do: "SCID #{scid} is also given to #{holder} in this batch; choose another"

  defp message(scid, holder, "staged", in_review),
    do: "SCID #{scid} is already staged for #{holder} in #{where(in_review)}; choose another"

  defp where(true), do: "a change set under review"
  defp where(false), do: "the open change set"

  # The op's own name when it stages one (a create, or an update renaming), else the live one.
  defp name(op, live_names), do: staged_name(op) || Map.get(live_names, op.entity_id)

  defp live_names(organization_id, mission_id, ops) do
    if Enum.any?(ops, &(staged_name(&1) == nil)) do
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id, include_archived: true)
      |> Map.new(&{&1.spacecraft_id, &1.display_name})
    else
      %{}
    end
  end

  defp staged_ops(mission_id) do
    case ChangeSetStore.active(mission_id) do
      nil -> []
      set -> set.change_set_id |> ChangeSetStore.staged_ops() |> Enum.filter(&spacecraft?/1)
    end
  end

  defp spacecraft?(op), do: to_string(op.kind) == @kind

  defp scid(op), do: value(op, "scid")
  defp staged_name(op), do: present(value(op, "display_name"))

  defp value(%{action: action, payload: %{"document" => document}}, key)
       when action in ["create", :create] and is_map(document),
       do: Map.get(document, key)

  defp value(%{action: action, payload: %{"changes" => changes}}, key)
       when action in ["update", :update] and is_list(changes) do
    Enum.find_value(changes, fn change -> if change["path"] == key, do: change["value"] end)
  end

  defp value(_op, _key), do: nil

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_none), do: nil
end
