defmodule Cadence.SemanticObservations.LivePolicies do
  @moduledoc """
  What a generation keeps of a mission's monitoring policies, per group of spacecraft (#451, after
  M): each composition's craft run that composition's revision, so a policy is live on a craft when
  the craft's group has it. A group is `%{policies: [policy_id], spacecraft: [spacecraft_id] | :all}`
  (`:all`: a mission whose activation has no per-craft assignment, one model for every craft).

  A craft in no group runs nothing, so nothing is live on it; a mission-wide alarm (no spacecraft)
  is live when any group keeps its policy.

  "A craft in no group retires everything" is safe only because the groups come from
  `MissionModels.revisions_at/3` AT the generation's `applied_at`, and a craft's runtime receipt
  cannot come after its generation's `applied_at`: a craft that is running this generation is
  already in a group. Keep the groups tied to that instant; read at an earlier time they would
  retire the alarms of craft whose receipt had not been recorded yet.
  """

  @type group :: %{policies: [binary()], spacecraft: [binary()] | :all}
  @type t :: %{
          union: MapSet.t(binary()),
          by_craft: %{optional(binary()) => MapSet.t(binary())},
          all: MapSet.t(binary()) | nil
        }

  @doc "The lookup structure of `groups`."
  @spec new([group()]) :: t()
  def new(groups) do
    sets = Enum.map(groups, &{&1.spacecraft, MapSet.new(&1.policies)})

    %{
      union:
        Enum.reduce(sets, MapSet.new(), fn {_crafts, set}, acc -> MapSet.union(acc, set) end),
      by_craft:
        for({crafts, set} <- sets, is_list(crafts), craft <- crafts, into: %{}, do: {craft, set}),
      all: Enum.find_value(sets, fn {crafts, set} -> crafts == :all && set end)
    }
  end

  @doc "Whether `policy_id` is live on `spacecraft_id` (nil: a mission-wide alarm)."
  @spec live?(t(), binary() | nil, binary()) :: boolean()
  def live?(%{union: union}, nil, policy_id), do: MapSet.member?(union, policy_id)

  def live?(%{by_craft: by_craft, all: all}, spacecraft_id, policy_id) do
    case Map.fetch(by_craft, spacecraft_id) do
      {:ok, set} -> MapSet.member?(set, policy_id)
      :error -> all != nil and MapSet.member?(all, policy_id)
    end
  end

  @doc "The groups as stored (JSON)."
  @spec dump([group()]) :: [map()]
  def dump(groups) do
    Enum.map(groups, fn %{policies: policies, spacecraft: spacecraft} ->
      %{
        "policies" => policies,
        "spacecraft" => if(spacecraft == :all, do: "all", else: spacecraft)
      }
    end)
  end

  @doc "The groups from their stored form."
  @spec load([map()]) :: [group()]
  def load(stored) when is_list(stored) do
    Enum.map(stored, fn %{"policies" => policies, "spacecraft" => spacecraft} ->
      %{policies: policies, spacecraft: if(spacecraft == "all", do: :all, else: spacecraft)}
    end)
  end

  def load(_other), do: []

  @doc "The union of the groups' policies."
  @spec union([group()]) :: [binary()]
  def union(groups), do: groups |> new() |> Map.fetch!(:union) |> MapSet.to_list()
end
