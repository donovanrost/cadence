defmodule Cadence.MissionModels.SystemSelection do
  @moduledoc """
  Which definitions of a mission-model revision a spacecraft decodes, by SpaceSystem (ADR-020 P5,
  #1078 slice B1).

  The lowered plans say which system owns each container, command, algorithm and monitoring
  entry (`space_system_id`, slice A). This module reads that ownership:

    * `contributions/2`: per system of a revision, what it holds (the choices a binding offers);
    * `select/2`: the packet definitions a selection picks (today an APID list: the decom compile
      selects through it, so the input can change to systems without touching the compile);
    * `effective/2`: the systems an APID selection amounts to, for a craft's read: each system
      that owns a selected container, and whether all of its containers are selected.

  Systems nest: binding a system binds its descendants (B2). Pure over a revision and its plans.
  """

  alias Cadence.Catalog.MissionModel.{Revision, RuntimePlan, SpaceSystem}

  @type selection :: {:apids, [non_neg_integer()]}

  @doc "The definitions in `definitions` (anything with an `apid`) that `selection` picks."
  @spec select([struct() | map()], selection()) :: [struct() | map()]
  def select(definitions, {:apids, apids}) when is_list(definitions) and is_list(apids) do
    allowed = MapSet.new(apids)
    Enum.filter(definitions, &MapSet.member?(allowed, &1.apid))
  end

  @doc """
  Every system of `revision` with what it owns, by path:
  `[%{system_id, path, name, parent_id, packets, commands, algorithms, policies}]`. `packets` and
  `commands` list their definitions (`packets`: `packet_definition_id`, `name`, `runtime_name`,
  `apid`); `algorithms` and `policies` are counts.
  """
  @spec contributions(Revision.t(), %{optional(atom()) => RuntimePlan.t()}) :: [map()]
  def contributions(%Revision{} = revision, plans) when is_map(plans) do
    packets = owned(plans, :telemetry, "packet_definitions")
    commands = owned(plans, :command, "runtime_definitions")
    algorithms = owned(plans, :algorithm, "algorithms")
    policies = owned(plans, :monitoring, "policies")

    revision.space_systems
    |> Map.values()
    |> Enum.sort_by(& &1.qualified_name)
    |> Enum.map(fn %SpaceSystem{} = system ->
      %{
        system_id: system.semantic_id,
        path: system.qualified_name,
        name: system.name,
        parent_id: system.parent_id,
        packets: packets |> Map.get(system.semantic_id, []) |> Enum.map(&packet/1) |> sort(),
        commands: commands |> Map.get(system.semantic_id, []) |> Enum.map(&command/1) |> sort(),
        algorithms: length(Map.get(algorithms, system.semantic_id, [])),
        policies: policies |> Map.get(system.semantic_id, []) |> distinct_policies()
      }
    end)
  end

  @doc """
  The systems a selection amounts to, from the telemetry plan alone (one row, not the revision
  and all four plans): each system owning a selected container, as `%{system_id, path, name,
  bound: :all | :some, apids}`, by path. `bound: :all` when every container of the system is
  selected. `selection` is `{:apids, [apid]}` or `:all` (a nil `handled_apids`: every container,
  so every system that has one). A plan that isn't ready, or nil, binds nothing.
  """
  @spec effective(RuntimePlan.t() | nil, selection() | :all) :: [map()]
  def effective(%RuntimePlan{status: :ready, plan: plan}, selection) do
    chosen = if selection == :all, do: :all, else: MapSet.new(elem(selection, 1))

    plan
    |> Map.get("packet_definitions", [])
    |> Enum.filter(&is_binary(&1["space_system_id"]))
    |> Enum.group_by(&{&1["space_system_id"], &1["space_system_path"]})
    |> Enum.flat_map(fn {{system_id, path}, packets} ->
      picked = Enum.filter(packets, &(chosen == :all or MapSet.member?(chosen, &1["apid"])))

      if picked == [],
        do: [],
        else: [
          %{
            system_id: system_id,
            path: path,
            name: name_of(path),
            bound: if(length(picked) == length(packets), do: :all, else: :some),
            apids: picked |> Enum.map(& &1["apid"]) |> Enum.uniq() |> Enum.sort()
          }
        ]
    end)
    |> Enum.sort_by(& &1.path)
  end

  def effective(_plan, _selection), do: []

  defp name_of("/"), do: "/"
  defp name_of(path), do: path |> String.split("/", trim: true) |> List.last()

  defp owned(plans, target, key) do
    case Map.get(plans, target) do
      %RuntimePlan{status: :ready, plan: plan} ->
        plan |> Map.get(key, []) |> Enum.group_by(&Map.get(&1, "space_system_id"))

      _none ->
        %{}
    end
  end

  defp packet(document),
    do: %{
      packet_definition_id: document["packet_definition_id"],
      name: document["packet_name"],
      runtime_name: document["runtime_name"],
      apid: document["apid"]
    }

  defp command(document),
    do: %{
      command_id: document["command_id"],
      name: document["name"],
      runtime_name: document["runtime_name"]
    }

  defp sort(entries), do: Enum.sort_by(entries, &(&1.runtime_name || &1.name))

  # A policy with per-craft overrides is several entries; the system holds one policy.
  defp distinct_policies(entries), do: entries |> Enum.uniq_by(& &1["policy_id"]) |> length()
end
