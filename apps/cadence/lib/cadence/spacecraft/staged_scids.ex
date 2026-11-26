defmodule Cadence.Spacecraft.StagedScids do
  @moduledoc """
  The SCIDs a mission can't give a new spacecraft, and the stage-time refusal of one another
  staged change already uses (S9, #313; ux U20: a browser's guess can collide).

  **In use** (`in_use/3`): every live spacecraft's SCID, archived ones included (they keep theirs:
  the mission's unique index has no archive filter), plus every SCID a staged op of the mission's
  active change set gives a spacecraft (a create's document, or an update's `scid` change), by
  any author. A staged update that moves a live spacecraft to another SCID holds both until it
  applies.

  **Next free** (`next_free/1`): the lowest of 1..1023 not in use; never 0 (it stays accepted when
  typed); nil when none is free. Defined from `in_use/3`, so the two can't disagree.

  **At stage** (`conflicts/4`, `ConfigKind.stage_conflicts/4`): a spacecraft op whose SCID another
  spacecraft's staged op holds, or an earlier op of the same request gives to another spacecraft,
  is refused on its `scid` field with mms-ux's words (11-19). An op never collides with a staged
  op for the same spacecraft: re-staging replaces one's own op (fe-setup). The live collision
  ("already used in this mission") stays validate/6's, at preview and apply.
  """

  alias Cadence.SpacecraftStore

  @kind "spacecraft"
  @suggested 1..1023

  @doc "Every SCID in use in the mission: live, archived and staged; sorted, deduplicated."
  @spec in_use(String.t(), String.t(), [map()]) :: [non_neg_integer()]
  def in_use(organization_id, mission_id, staged_ops) do
    live = SpacecraftStore.scids(organization_id, mission_id)
    staged = staged_ops |> Enum.filter(&spacecraft?/1) |> Enum.map(&scid/1)

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
  request gives to another spacecraft. Staging runs only on an open set (`Staging` refuses one in
  review first), so the words always name the open change set.
  """
  @spec conflicts(String.t(), String.t(), [map()], [map()]) ::
          :ok | {:error, {:invalid_op, non_neg_integer(), [map()]}}
  def conflicts(organization_id, mission_id, staged, prepared) do
    context = %{
      organization_id: organization_id,
      mission_id: mission_id,
      staged: by_scid(staged)
    }

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
      error = refusal(scid, name(holder, context), source)
      {:halt, {:error, {:invalid_op, index, [error]}}}
    else
      nil -> {:cont, Map.put_new(earlier, scid(op), op)}
      _not_a_scid -> {:cont, earlier}
    end
  end

  # A staged op holds its SCID against every OTHER spacecraft; the same spacecraft's own op is
  # replaced by this stage, so it never counts.
  defp clash(op, scid, staged, earlier) do
    case staged |> Map.get(scid, []) |> Enum.find(&(&1.entity_id != op.entity_id)) do
      nil -> request_clash(other(Map.get(earlier, scid), op))
      holder -> {"staged", holder}
    end
  end

  defp request_clash(nil), do: nil
  defp request_clash(holder), do: {"request", holder}

  defp other(nil, _op), do: nil
  defp other(holder, op), do: if(holder.entity_id != op.entity_id, do: holder)

  # The set's staged spacecraft ops by the SCID they give, built once per stage (500-craft floor:
  # each request op then looks up only its own SCID's holders).
  defp by_scid(staged) do
    staged
    |> Enum.filter(&(spacecraft?(&1) and is_integer(scid(&1))))
    |> Enum.group_by(&scid/1)
  end

  # mms-ux 11-19 (field errors take no final period; U25: no name for another spacecraft).
  defp refusal(scid, name, source) do
    %{
      path: "scid",
      message: message(scid, name || "another spacecraft", source),
      details: %{scid: scid, spacecraft_name: name, source: source}
    }
  end

  defp message(scid, holder, "request"),
    do: "SCID #{scid} is also given to #{holder} in this batch; choose another"

  defp message(scid, holder, "staged"),
    do: "SCID #{scid} is already staged for #{holder} in the open change set; choose another"

  # The op's own name when it stages one (a create, or an update renaming), else the live one:
  # one row, read only for the holder a refusal names.
  defp name(op, context), do: staged_name(op) || live_name(op.entity_id, context)

  defp live_name(spacecraft_id, %{organization_id: organization_id, mission_id: mission_id}) do
    case SpacecraftStore.display_names(organization_id, mission_id, [spacecraft_id]) do
      {:ok, [%{"name" => name}]} -> present(name)
      _none -> nil
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
