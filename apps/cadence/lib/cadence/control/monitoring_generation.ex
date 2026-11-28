defmodule Cadence.Control.MonitoringGeneration do
  @moduledoc """
  The generation a monitoring change set's apply makes (ADR-020 P3 slice M2, #451; the design
  agreed with commanding and mm-engineer on #1106).

  Inside the apply's transaction, under its locks:

    1. the next authored layer is built from the set's entries (`MissionModels.AuthoredLayer`):
       the head's declarations with the set's monitoring changes, as version head + 1 of this set;
    2. it's recorded as that version for the revision this apply writes
       (`Control.AuthoredVersions.record/5`, checked again by the database at commit);
    3. every composition in use compiles at the new head, once each
       (`Compositions.effective_revision/5`); a declaration that doesn't resolve in a composition
       it's scoped to is a NO-GO naming the composition;
    4. each craft's contribution is recompiled in memory against its composition's head revision,
       from the craft's **existing** configuration assignment: a monitoring change changes no
       craft's configuration, so no assignment row is written;
    5. one generation through the model gate and activation, with no pin move.

  `at_head/3` is the same step for a configuration apply: every generation runs a craft at its
  composition's current head.
  """

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Assignments, Review}
  alias Cadence.Catalog.CompositionPins
  alias Cadence.Control.{AuthoredVersions, ConfigurationGeneration}
  alias Cadence.MissionModels.{AuthoredHead, AuthoredLayer, Compositions}
  alias Cadence.Missions
  alias Cadence.SourceEndpoints

  @spec build(map()) :: {:ok, nil | map()} | {:error, term()}
  def build(%{set: set} = input) do
    org = set.organization_id
    mission_id = set.mission_id

    with {:ok, mission} <- Missions.fetch_mission(org, mission_id),
         active = active(mission),
         {compositions, by_catalog} = in_use(active, mission),
         {:ok, layer} <-
           AuthoredLayer.next(org, mission_id, input.entries, compositions, set.change_set_id),
         {:ok, _version} <-
           AuthoredVersions.record(
             org,
             mission_id,
             layer.layer_id,
             set.change_set_id,
             input.revision
           ) do
      generate(mission, input, active, {compositions, by_catalog}, layer.layer_id)
    end
  end

  @doc """
  The compositions the mission's active fleet runs, by id: each craft's pinned composition, else
  its catalog revision's one-layer composition. The kind's preview checks and the apply use the
  same set.
  """
  @spec compositions_in_use(binary(), binary()) :: [binary()]
  def compositions_in_use(organization_id, mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id) do
      mission |> active() |> in_use(mission) |> elem(0)
    else
      _none -> []
    end
  end

  @doc """
  The revision a craft of `composition_id` runs: `base` (its selected revision) compiled at the
  mission's current authored head, or `base` itself before the first monitoring apply.
  """
  @spec at_head(map(), binary() | nil, binary() | nil) :: {:ok, binary() | nil} | {:error, term()}
  def at_head(_mission, nil, base), do: {:ok, base}

  def at_head(mission, composition_id, base) do
    case AuthoredHead.head(mission.organization_id, mission.mission_id) do
      nil -> {:ok, base}
      %{layer_id: head} -> compile_at(mission, composition_id, head)
    end
  end

  # No active fleet: the version is recorded and the next fleet generation runs at it.
  defp generate(_mission, _input, nil, _compositions, _head), do: {:ok, nil}

  defp generate(mission, input, active, {compositions, by_catalog}, head) do
    with {:ok, heads} <- heads(mission, compositions, head),
         {:ok, items} <- recompile(mission, active.entries, heads, by_catalog),
         {:ok, binding_set} <- ConfigurationGeneration.next_binding_set(mission, active, items) do
      changed = Map.new(items, &{&1.id, &1.entry})
      ConfigurationGeneration.activate(input, active, binding_set, changed)
    end
  end

  defp active(mission) do
    case Active.load(mission) do
      {:ok, %{activation: %{}} = active} -> active
      _none -> nil
    end
  end

  defp in_use(nil, _mission), do: {[], %{}}

  # The composition each craft runs: its entry's (a pinned composition), else its catalog
  # revision's one-layer composition, looked up once per distinct catalog, never per craft.
  defp in_use(active, mission) do
    unpinned =
      for {_id, %{"catalog_revision_id" => catalog} = entry} <- active.entries,
          not is_binary(entry["composition_id"]),
          is_binary(catalog),
          uniq: true,
          do: catalog

    by_catalog =
      for catalog <- unpinned,
          {:ok, composition} <- [
            CompositionPins.for_catalog_revision(
              mission.organization_id,
              mission.mission_id,
              catalog
            )
          ],
          into: %{},
          do: {catalog, composition}

    compositions =
      active.entries
      |> Map.values()
      |> Enum.map(&composition_of(&1, by_catalog))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.sort()

    {compositions, by_catalog}
  end

  defp composition_of(%{"composition_id" => id}, _by_catalog) when is_binary(id), do: id
  defp composition_of(entry, by_catalog), do: Map.get(by_catalog, entry["catalog_revision_id"])

  # `%{composition_id => head revision id}`, one compile per composition.
  defp heads(mission, compositions, head) do
    Enum.reduce_while(compositions, {:ok, %{}}, fn composition_id, {:ok, acc} ->
      case compile_at(mission, composition_id, head) do
        {:ok, revision_id} -> {:cont, {:ok, Map.put(acc, composition_id, revision_id)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp compile_at(mission, composition_id, head) do
    case Compositions.effective_revision(
           mission.organization_id,
           mission.mission_id,
           composition_id,
           head
         ) do
      {:ok, revision_id} -> {:ok, revision_id}
      {:error, reason} -> {:error, {:monitoring_composition_invalid, composition_id, reason}}
    end
  end

  # Each craft on a composition in use, recompiled against its head revision from its existing
  # assignment: inputs once per {catalog, revision} (Review.cached_inputs), sources in one read.
  defp recompile(mission, entries, heads, by_catalog) do
    org = mission.organization_id
    mission_id = mission.mission_id

    on_heads =
      for {id, entry} <- entries,
          composition = composition_of(entry, by_catalog),
          is_map_key(heads, composition),
          into: %{},
          do: {id, Map.put(entry, "composition_id", composition)}

    rows =
      org
      |> Assignments.fetch_many(
        mission_id,
        on_heads |> Map.values() |> Enum.map(& &1["configuration_revision_id"]) |> Enum.uniq()
      )

    sources =
      org
      |> SourceEndpoints.list_source_endpoints_for_spacecrafts(mission_id, Map.keys(on_heads))
      |> Map.new(fn {id, endpoints} -> {id, Enum.map(endpoints, & &1.source_endpoint_id)} end)

    on_heads
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, [], %{}}, fn {id, entry}, {:ok, items, cache} ->
      with %{} = row <-
             Map.get(rows, entry["configuration_revision_id"]) ||
               {:error, :spacecraft_configuration_not_found},
           revision = Map.fetch!(heads, entry["composition_id"]),
           {:ok, inputs, cache} <-
             Review.cached_inputs(cache, mission, entry["catalog_revision_id"], revision),
           {:ok, item} <- Review.compile(mission, id, row, inputs, Map.get(sources, id, [])) do
        {:cont, {:ok, [item | items], cache}}
      else
        {:error, reason} -> {:halt, {:error, {reason, id}}}
      end
    end)
    |> case do
      {:ok, items, _cache} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end
end
