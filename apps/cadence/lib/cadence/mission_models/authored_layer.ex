defmodule Cadence.MissionModels.AuthoredLayer do
  @moduledoc """
  Builds the next version of the mission's authored monitoring layer from a monitoring change set
  (ADR-020 P3 slice M2, #451).

  A version is **cumulative** (`AuthoredHead`): the next layer is the current head's declarations
  with the set's monitoring entries applied, each keyed by its declaration's semantic id:

    * a mission policy's create adds a declaration under `#{"/mission/monitoring"}`, its update
      replaces it, its delete drops it;
    * an update of a **catalog** policy adds an explicit `:replace` of it, pinned to the catalog
      declaration's fingerprint **as the compiler composes it** (the imported layer's declaration
      at its mount, never the stored revision's resolved one), so a catalog that moved underneath
      is a drift NO-GO at compile, never a silent overwrite. The fingerprint must be the same in
      every composition in use that has the policy (`:monitoring_catalog_policy_differs`).

  Each version is its own layer: the layer carries its version (the head's + 1) and the change set
  that makes it, so a set that returns a policy to an earlier value still makes a new layer
  (mm-engineer, #1106). The preview and the apply of one set build the same layer id. A set that
  changes nothing is refused (`:monitoring_set_changes_nothing`), a catalog policy can't be
  deleted (turn it off with a replace, `disabled: true`), and a layer holds at most
  #{5_000} declarations.

  **Composition scope.** A declaration may name the compositions it applies to (`compositions`;
  absent: every composition in use). It must resolve in each composition it's scoped to; the
  compile filters the layer by scope before composing (`Compositions.effective_revision/5`), so
  a limit on a point only one catalog has is authored for that composition alone.

  `next/5` persists the layer (insert-or-get) and returns it; recording it as a version is the
  apply's (`Control.AuthoredVersions.record/5`).
  """

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Layer, Mount}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredHead, AuthoredScope, Compositions}

  @namespace "/mission/monitoring"
  # derived_parameter joins with M2b.
  @kinds ["monitoring_policy"]
  @max_declarations 5_000

  @type entry :: %{
          kind: binary(),
          op: :create | :update | :delete,
          entity_id: binary(),
          previous: map() | nil,
          proposed: map() | nil
        }

  @doc "The qualified name a mission policy named `name` is declared under."
  @spec qualified_name(binary()) :: binary()
  def qualified_name(name) when is_binary(name), do: @namespace <> "/" <> slug(name)

  @doc "The entity id (the declaration's semantic id) of a mission policy named `name`."
  @spec entity_id(binary()) :: binary()
  def entity_id(name), do: Canonical.semantic_id(:monitoring_policy, qualified_name(name))

  @doc "The mission's current authored declarations, by semantic id (none before a first apply)."
  @spec current(binary(), binary()) :: %{binary() => Declaration.t()}
  def current(organization_id, mission_id) do
    with %{layer_id: layer_id} <- AuthoredHead.head(organization_id, mission_id),
         {:ok, %Layer{declarations: declarations}} <-
           MissionModels.fetch_layer(organization_id, mission_id, layer_id) do
      Map.new(declarations, &{&1.semantic_id, &1})
    else
      _none -> %{}
    end
  end

  @doc """
  The next authored layer: the current head's declarations with `entries` (the set's monitoring
  entries) applied, as version head + 1 of `change_set_id`, persisted. `compositions` are the
  composition ids in use, for a catalog policy's replace.
  """
  @spec next(binary(), binary(), [entry()], [binary()], binary()) ::
          {:ok, Layer.t()} | {:error, term()}
  def next(organization_id, mission_id, entries, compositions, change_set_id) do
    with {:ok, layer} <- build(organization_id, mission_id, entries, compositions, change_set_id),
         do: MissionModels.persist_layer(layer)
  end

  @doc "The layer `next/5` would persist, without persisting it (for a preview's checks)."
  @spec build(binary(), binary(), [entry()], [binary()], binary()) ::
          {:ok, Layer.t()} | {:error, term()}
  def build(organization_id, mission_id, entries, compositions, change_set_id) do
    current = current(organization_id, mission_id)
    catalog = catalog_index(organization_id, mission_id, entries, current, compositions)

    with :ok <- monitoring_only(entries),
         {:ok, declarations} <- apply_entries(current, entries, catalog),
         :ok <- scoped_in_use(declarations, compositions),
         :ok <- changed(declarations, current),
         :ok <- bounded(declarations) do
      {:ok,
       layer(
         organization_id,
         mission_id,
         declarations,
         next_version(organization_id, mission_id),
         change_set_id
       )}
    end
  end

  defp changed(declarations, current) do
    if fingerprints(declarations) == fingerprints(current),
      do: {:error, :monitoring_set_changes_nothing},
      else: :ok
  end

  defp fingerprints(declarations),
    do:
      Map.new(declarations, fn {id, declaration} -> {id, Declaration.fingerprint(declaration)} end)

  defp bounded(declarations) do
    if map_size(declarations) <= @max_declarations,
      do: :ok,
      else: {:error, {:monitoring_layer_too_large, @max_declarations}}
  end

  defp next_version(organization_id, mission_id) do
    case AuthoredHead.head(organization_id, mission_id) do
      nil -> 1
      %{version: version} -> version + 1
    end
  end

  defp apply_entries(declarations, entries, catalog) do
    Enum.reduce_while(entries, {:ok, declarations}, fn entry, {:ok, acc} ->
      case apply_entry(acc, entry, catalog) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # A mission declaration retires by leaving the next version; a catalog one can't be deleted
  # here (it changes by import, or is turned off by a replace with `disabled: true`).
  defp apply_entry(declarations, %{op: :delete, entity_id: id}, _catalog)
       when is_map_key(declarations, id),
       do: {:ok, Map.delete(declarations, id)}

  defp apply_entry(_declarations, %{op: :delete, entity_id: id}, _catalog),
    do: {:error, {:monitoring_catalog_policy_delete, id}}

  defp apply_entry(declarations, %{entity_id: id, proposed: proposed}, catalog) do
    case {Map.has_key?(declarations, id), Map.get(catalog, id, [])} do
      {false, [_ | _] = composed} -> replace(declarations, id, proposed, composed)
      _mission -> {:ok, Map.put(declarations, id, mission_declaration(proposed))}
    end
  end

  # A mission-owned declaration: added (or, on update, replaced in this layer, which owns it).
  defp mission_declaration(document) do
    Declaration.new(%{
      kind: :monitoring_policy,
      qualified_name: qualified_name(document["name"]),
      references: references(document),
      definition: definition(document)
    })
  end

  defp replace(declarations, id, proposed, [catalog | others]) do
    fingerprint = Declaration.fingerprint(catalog)

    if Enum.all?(others, &(Declaration.fingerprint(&1) == fingerprint)),
      do:
        {:ok,
         Map.put(
           declarations,
           id,
           Declaration.new(%{
             kind: :monitoring_policy,
             qualified_name: catalog.qualified_name,
             operation: :replace,
             expected_fingerprint: fingerprint,
             references: catalog.references,
             definition: definition(proposed)
           })
         )},
      else: {:error, {:monitoring_catalog_policy_differs, id}}
  end

  # The catalog's monitoring policies as each composition in use composes them (its imported
  # layers at their mounts, what the compiler checks a replace's fingerprint against), by semantic
  # id: read once per build, and only when an entry edits a policy the head doesn't own
  # (mm-engineer, #1106: never per edited policy).
  defp catalog_index(organization_id, mission_id, entries, current, compositions) do
    if Enum.any?(entries, &(not Map.has_key?(current, &1.entity_id))),
      do: build_index(organization_id, mission_id, compositions),
      else: %{}
  end

  defp build_index(org, mission, compositions) do
    for composition_id <- compositions,
        {:ok, composition} <- [Compositions.fetch(org, mission, composition_id)],
        {:ok, layers} <- [layers(org, mission, composition)],
        mounts = Map.new(composition.imported_layers, &{&1.layer_id, &1.mount}),
        {:ok, mounted, _mount} <- [Mount.prepare(layers, mounts)],
        layer <- mounted,
        %Declaration{kind: :monitoring_policy} = declaration <- layer.declarations,
        reduce: %{} do
      acc -> Map.update(acc, declaration.semantic_id, [declaration], &(&1 ++ [declaration]))
    end
  end

  # A monitoring set holds only monitoring kinds (one lane); anything else is refused, never
  # dropped (commanding, #1106).
  defp monitoring_only(entries) do
    case Enum.find(entries, &(&1.kind not in @kinds)) do
      nil -> :ok
      %{kind: kind} -> {:error, {:not_a_monitoring_kind, kind}}
    end
  end

  # Every composition a declaration is scoped to must be one in use: a scope naming none would
  # apply to nothing, silently (mm-engineer, #1106).
  defp scoped_in_use(declarations, compositions) do
    in_use = MapSet.new(compositions)

    unknown =
      for {_id, declaration} <- declarations,
          id <- AuthoredScope.scope(declaration),
          not MapSet.member?(in_use, id),
          uniq: true,
          do: id

    case unknown do
      [] -> :ok
      ids -> {:error, {:monitoring_scope_not_in_use, Enum.sort(ids)}}
    end
  end

  defp layers(org, mission, composition) do
    composition.imported_layers
    |> Enum.reduce_while({:ok, []}, fn %{layer_id: layer_id}, {:ok, acc} ->
      case MissionModels.fetch_layer(org, mission, layer_id) do
        {:ok, layer} -> {:cont, {:ok, [layer | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, layers} -> {:ok, Enum.reverse(layers)}
      error -> error
    end
  end

  defp references(document) do
    parameter = [
      %{expected_kind: :parameter, source_ref: document["parameter"], role: :parameter}
    ]

    case document["overrides"] do
      target when is_binary(target) ->
        parameter ++ [%{expected_kind: :monitoring_policy, source_ref: target, role: :overrides}]

      _none ->
        parameter
    end
  end

  @definition_fields ~w(policy_kind default_rules contexts minimum_violations minimum_conformance
    missing_state invalid_state disabled spacecraft_ids description compositions)

  defp definition(document), do: Map.take(document, @definition_fields)

  defp layer(organization_id, mission_id, declarations, version, change_set_id) do
    Layer.new(%{
      organization_id: organization_id,
      mission_id: mission_id,
      layer_kind: :authored,
      version: version,
      name: "Mission monitoring",
      metadata: %{"change_set_id" => change_set_id},
      declarations: declarations |> Map.values() |> Enum.sort_by(& &1.qualified_name)
    })
  end

  defp slug(name) do
    name
    |> String.trim()
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "_")
  end
end
