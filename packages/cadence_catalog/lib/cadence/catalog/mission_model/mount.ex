defmodule Cadence.Catalog.MissionModel.Mount do
  @moduledoc """
  Where each imported layer sits in a composed revision (#444; ADR-020 Addendum 1, DECISIONS #92:
  imported layers coexist under their own subtrees).

  The mount is a compile input, `mounts: %{layer_id => path}`, never part of a layer, so a layer's
  id and content don't move with it. D's composition record (#445) will own the mounts; until then
  callers pass them.

  - **One imported layer** at '/' (the default) compiles exactly as before: nothing is rebased,
    and the revision's ids and hashes are unchanged (#108; golden test).
  - **More than one imported layer** (#537, api-ops: identities never move silently): one import
    may stay at '/' as the **primary**, keeping every semantic id and qualified name, and its own
    '/' stays the root. Every further import needs a non-root mount
    (`{:error, {:mission_model_mount_required, layer_ids}}` names the second and later ones at '/'),
    disjoint from the primary's top-level names and from every other mount. With no primary, the
    compiler owns '/'. Authored layers are never mounted: they address the composed tree.
  - **Rebasing a layer to `/m`:** each declaration's qualified name and space-system path move
    under `/m`, its semantic id is recomputed from the new path, and the layer's own '/' becomes
    the `/m` SpaceSystem. An algorithm's outputs name the moved parameter.
  - **References keep the source's text.** An absolute reference written in a mounted layer
    resolves under its mount; a relative one resolves from the moved declaration. Lowering matches
    definition entries to references by that text, so it never needs rewriting.
  - **Collisions are blocking diagnostics:** two imports at one mount, or one mount nested under
    another (`MM_MOUNT_COLLISION`, per pair; nesting waits for D's record), a
    duplicate across layers (`MM_DUPLICATE_IDENTITY`, naming both layers and the mount), and two
    mounts lowering the same packet, parameter or command short name into one target
    (`MM_TARGET_NAME_COLLISION`; qualified runtime names are phase 5).
  """

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Diagnostic, Layer, Path}

  @typedoc "How a compile mounts its layers. `mounted?: false` is today's single-root compile."
  @type t :: %{
          mounted?: boolean(),
          by_layer: %{binary() => binary()},
          layer_order: [binary()],
          primary: binary() | nil,
          primary_top: MapSet.t(),
          mounted_refs: %{binary() => {binary(), MapSet.t()}}
        }

  # CB-13 (#537): a composition holds at most 8 imported layers, mounted at most 4 segments deep.
  @max_layers 8
  @max_depth 4

  @unmounted %{
    mounted?: false,
    by_layer: %{},
    layer_order: [],
    primary: nil,
    primary_top: MapSet.new(),
    mounted_refs: %{}
  }

  # The targets whose runtime still keys these kinds by short name (target_lowering.ex).
  @short_name_targets %{container: :telemetry, parameter: :telemetry, command: :command}

  @doc "Checks `mounts` against `layers` and rebases the mounted ones."
  @spec prepare([Layer.t()], term()) :: {:ok, [Layer.t()], t()} | {:error, term()}
  def prepare(layers, mounts) when is_map(mounts) do
    imported = Enum.filter(layers, &(&1.layer_kind == :imported))

    with :ok <- validate(layers, mounts),
         by_layer = Map.new(imported, &{&1.layer_id, Map.get(mounts, &1.layer_id, "/")}),
         :ok <- within_bounds(imported),
         :ok <- require_mounts(imported, by_layer) do
      if Enum.all?(Map.values(by_layer), &(&1 == "/")) do
        {:ok, layers, @unmounted}
      else
        rebased = Enum.map(layers, &rebase(&1, by_layer))
        primary = Enum.find(imported, &(by_layer[&1.layer_id] == "/"))

        {:ok, rebased,
         %{
           mounted?: true,
           by_layer: by_layer,
           layer_order: Enum.map(imported, & &1.layer_id),
           primary: primary && primary.layer_id,
           primary_top: top_names(primary),
           mounted_refs: mounted_refs(rebased, by_layer)
         }}
      end
    end
  end

  def prepare(_layers, _mounts), do: {:error, {:mission_model_mount_invalid, nil, :not_a_map}}

  @doc """
  Whether `layers` at `mounts` make a well-formed composition, without compiling (#537, D1): the
  grammar and bounds (`prepare/2`) and the collision rules, equal or nested mounts and a mount on one
  of the primary's top-level names. `:ok`, or the first refusal: the composition record refuses
  its INSERT with it, so a bad composition is never stored.
  """
  @spec check([Layer.t()], map()) :: :ok | {:error, term()}
  def check(layers, mounts) do
    with {:ok, _layers, plan} <- prepare(layers, mounts) do
      case mount_collisions(plan) ++ primary_collisions(plan) do
        [] -> :ok
        [first | _] -> {:error, {:mission_model_mount_collision, first.metadata}}
      end
    end
  end

  @doc "The declarations composition starts from: the compiler's own '/' when mounted."
  @spec initial(t()) :: %{binary() => Declaration.t()}
  def initial(%{mounted?: false}), do: %{}

  # A primary import's own '/' is the root; the compiler makes one only when no import stays there.
  def initial(%{mounted?: true, primary: primary}) when is_binary(primary), do: %{}

  def initial(%{mounted?: true}) do
    root = Declaration.new(%{kind: :space_system, qualified_name: "/"})
    %{root.semantic_id => root}
  end

  @doc "Where an absolute reference written in `declaration` points, given the mounts."
  @spec resolve(t(), Declaration.t(), struct()) :: binary()
  def resolve(%{mounted_refs: refs}, declaration, reference) do
    case Map.fetch(refs, declaration.semantic_id) do
      {:ok, {mount, keys}} ->
        if MapSet.member?(keys, ref_key(reference)),
          do: rebase_path(Path.normalize(reference.source_ref), mount),
          else: Path.resolve(declaration.qualified_name, reference.source_ref)

      :error ->
        Path.resolve(declaration.qualified_name, reference.source_ref)
    end
  end

  @doc "The revision metadata recording the mounts (none when unmounted, so it stays unchanged)."
  @spec metadata(map(), t()) :: map()
  def metadata(metadata, %{mounted?: false}), do: metadata
  def metadata(metadata, %{by_layer: by_layer}), do: Map.put(metadata, "mounts", by_layer)

  @doc """
  The mounted compile's own diagnostics, plus composition diagnostics annotated with the layer
  that already held a duplicate and the mount.
  """
  @spec diagnostics(t(), [Layer.t()], [Diagnostic.t()], %{binary() => Declaration.t()}) ::
          {[Diagnostic.t()], [Diagnostic.t()]}
  def diagnostics(%{mounted?: false}, _layers, composition, _declarations), do: {composition, []}

  def diagnostics(plan, layers, composition, declarations) do
    annotated = Enum.map(composition, &annotate(&1, layers, plan))

    {annotated,
     mount_collisions(plan) ++
       primary_collisions(plan) ++ short_name_collisions(plan, declarations)}
  end

  ## Validation

  defp validate(layers, mounts) do
    by_id = Map.new(layers, &{&1.layer_id, &1})

    mounts
    |> Enum.sort()
    |> Enum.find_value(:ok, fn {layer_id, path} ->
      case invalid(Map.get(by_id, layer_id), path) do
        nil -> nil
        reason -> {:error, {:mission_model_mount_invalid, layer_id, reason}}
      end
    end)
  end

  defp invalid(nil, _path), do: :unknown_layer
  defp invalid(%Layer{layer_kind: :authored}, _path), do: :authored_layer

  defp invalid(%Layer{}, path) do
    cond do
      not (is_binary(path) and plain_absolute?(path)) -> :invalid_path
      depth(path) > @max_depth -> :too_deep
      true -> nil
    end
  end

  defp depth(path), do: path |> String.split("/", trim: true) |> length()

  # CB-13 (#537): at most @max_layers imported layers in one composition.
  defp within_bounds(imported) when length(imported) > @max_layers,
    do: {:error, {:mission_model_too_many_layers, length(imported)}}

  defp within_bounds(_imported), do: :ok

  # '/' or '/a/b': absolute, already normal, no '.' or '..' segments.
  defp plain_absolute?("/"), do: true

  defp plain_absolute?("/" <> _rest = path) do
    segments = String.split(path, "/") |> tl()
    # The composition record's CHECK allows the same segments (#541), so neither refuses what the
    # other accepts.
    Path.normalize(path) == path and
      Enum.all?(
        segments,
        &(&1 not in ["", ".", ".."] and Regex.match?(~r/^[A-Za-z0-9_.-]+$/, &1))
      )
  end

  defp plain_absolute?(_path), do: false

  defp require_mounts([_one], _by_layer), do: :ok
  defp require_mounts([], _by_layer), do: :ok

  # #537 (api-ops): the first import at '/' is the primary and keeps every identity; only a
  # second or later import at '/' needs a mount.
  defp require_mounts(imported, by_layer) do
    case for(layer <- imported, by_layer[layer.layer_id] == "/", do: layer.layer_id) do
      [_primary | [_ | _] = later] -> {:error, {:mission_model_mount_required, later}}
      _none_or_primary -> :ok
    end
  end

  ## Rebasing

  defp rebase(%Layer{layer_kind: :imported} = layer, by_layer) do
    case Map.fetch!(by_layer, layer.layer_id) do
      "/" ->
        layer

      mount ->
        %Layer{layer | declarations: Enum.map(layer.declarations, &rebase_declaration(&1, mount))}
    end
  end

  defp rebase(%Layer{} = layer, _by_layer), do: layer

  defp rebase_declaration(%Declaration{qualified_name: "/"} = declaration, mount) do
    moved(declaration, mount, mount, Path.parent(mount))
    |> Map.put(:name, mount |> String.split("/", trim: true) |> List.last())
  end

  defp rebase_declaration(%Declaration{} = declaration, mount) do
    moved(
      declaration,
      rebase_path(declaration.qualified_name, mount),
      mount,
      rebase_path(declaration.space_system_path, mount)
    )
  end

  defp moved(%Declaration{} = declaration, qualified_name, mount, space_system_path) do
    %Declaration{
      declaration
      | qualified_name: qualified_name,
        semantic_id: Canonical.semantic_id(declaration.kind, qualified_name),
        space_system_path: space_system_path,
        definition: rebase_outputs(declaration.kind, declaration.definition, mount)
    }
  end

  defp rebase_path("/", mount), do: mount
  defp rebase_path(path, "/"), do: path
  defp rebase_path(path, mount), do: Path.join(mount, path)

  # An algorithm names its output parameters by id and path (the XTCE translator); they move with
  # the parameters, or the plan would write a parameter that no longer exists.
  defp rebase_outputs(:algorithm, definition, mount) when is_map(definition) do
    Enum.reduce([:outputs, "outputs"], definition, fn key, acc ->
      case Map.fetch(acc, key) do
        {:ok, outputs} when is_list(outputs) ->
          Map.put(acc, key, Enum.map(outputs, &rebase_output(&1, mount)))

        _absent ->
          acc
      end
    end)
  end

  defp rebase_outputs(_kind, definition, _mount), do: definition

  defp rebase_output(output, mount) when is_map(output) do
    output
    |> rebase_output_path(:qualified_name, :parameter_id, mount)
    |> rebase_output_path("qualified_name", "parameter_id", mount)
  end

  defp rebase_output(output, _mount), do: output

  defp rebase_output_path(output, path_key, id_key, mount) do
    case Map.fetch(output, path_key) do
      {:ok, "/" <> _rest = path} ->
        moved = rebase_path(Path.normalize(path), mount)

        output
        |> Map.put(path_key, moved)
        |> Map.put(id_key, Canonical.semantic_id(:parameter, moved))

      _other ->
        output
    end
  end

  # The absolute references each mounted declaration was written with. A later layer that
  # replaces or removes the declaration takes its references with it.
  defp mounted_refs(layers, by_layer) do
    replaced =
      for layer <- layers,
          %Declaration{operation: op} = declaration <- layer.declarations,
          op in [:replace, :remove],
          into: MapSet.new(),
          do: declaration.semantic_id

    for %Layer{layer_kind: :imported} = layer <- layers,
        mount <- [Map.fetch!(by_layer, layer.layer_id)],
        mount != "/",
        declaration <- layer.declarations,
        not MapSet.member?(replaced, declaration.semantic_id),
        into: %{} do
      keys =
        for reference <- declaration.references,
            match?("/" <> _rest, reference.source_ref),
            into: MapSet.new(),
            do: ref_key(reference)

      {declaration.semantic_id, {mount, keys}}
    end
  end

  defp ref_key(reference), do: {reference.expected_kind, reference.source_ref, reference.role}

  ## Diagnostics

  defp annotate(%Diagnostic{code: "MM_DUPLICATE_IDENTITY"} = diagnostic, layers, plan) do
    layer_id = diagnostic.metadata[:layer_id]
    existing = first_adder(layers, diagnostic.semantic_id, layer_id)

    metadata =
      Map.merge(diagnostic.metadata, %{
        existing_layer_id: existing,
        mount: Map.get(plan.by_layer, layer_id)
      })

    %Diagnostic{diagnostic | metadata: metadata}
  end

  defp annotate(diagnostic, _layers, _plan), do: diagnostic

  defp first_adder(layers, semantic_id, layer_id) do
    Enum.find_value(layers, fn layer ->
      layer.layer_id != layer_id and
        Enum.any?(layer.declarations, &(&1.semantic_id == semantic_id and &1.operation == :add)) and
        layer.layer_id
    end)
  end

  # Domain (#456 review): one mount equal to, or under, another is refused; nesting waits for D's
  # composition record. One diagnostic per pair, naming both layers and both mounts.
  defp mount_collisions(plan) do
    mounted = Enum.map(plan.layer_order, &{&1, Map.fetch!(plan.by_layer, &1)})

    for {{first, first_mount}, i} <- Enum.with_index(mounted),
        {{second, second_mount}, j} <- Enum.with_index(mounted),
        i < j,
        overlap?(first_mount, second_mount) do
      Diagnostic.new(%{
        code: "MM_MOUNT_COLLISION",
        severity: :error,
        stage: :composition,
        message: "Imported layers can't share or nest mounts: #{first_mount} and #{second_mount}",
        metadata: %{layer_ids: [first, second], mounts: [first_mount, second_mount]}
      })
    end
  end

  # The primary at '/' contains every path, so it's checked by its top-level names instead.
  defp overlap?("/", _right), do: false
  defp overlap?(_left, "/"), do: false
  defp overlap?(left, right), do: under?(left, right) or under?(right, left)

  # #537: a mount must be disjoint from the primary's top-level names, or the two layers would
  # share a subtree.
  defp primary_collisions(%{primary: nil}), do: []

  defp primary_collisions(plan) do
    for {layer_id, mount} <- Enum.map(plan.layer_order, &{&1, Map.fetch!(plan.by_layer, &1)}),
        mount != "/",
        MapSet.member?(plan.primary_top, top_name(mount)) do
      Diagnostic.new(%{
        code: "MM_MOUNT_COLLISION",
        severity: :error,
        stage: :composition,
        message: "#{mount} is already a top-level name of the import at /",
        metadata: %{layer_ids: [plan.primary, layer_id], mounts: ["/", mount]}
      })
    end
  end

  defp top_name(path), do: path |> String.split("/", trim: true) |> List.first()

  defp top_names(nil), do: MapSet.new()

  defp top_names(%Layer{declarations: declarations}),
    do: for(d <- declarations, name = top_name(d.qualified_name), into: MapSet.new(), do: name)

  defp short_name_collisions(plan, declarations) do
    declarations
    |> Map.values()
    |> Enum.filter(&Map.has_key?(@short_name_targets, &1.kind))
    |> Enum.group_by(&{&1.kind, &1.name})
    |> Enum.flat_map(fn {{kind, name}, group} ->
      mounts = group |> Enum.map(&mount_of(plan, &1)) |> Enum.uniq() |> Enum.sort()

      if length(mounts) > 1,
        do: [short_name_collision(plan, kind, name, group, mounts)],
        else: []
    end)
    |> Enum.sort_by(&{&1.target, &1.metadata.kind, &1.metadata.name})
  end

  defp short_name_collision(plan, kind, name, group, mounts) do
    first = Enum.min_by(group, & &1.qualified_name)
    target = Map.fetch!(@short_name_targets, kind)

    Diagnostic.new(%{
      code: "MM_TARGET_NAME_COLLISION",
      severity: :error,
      stage: :legalization,
      target: target,
      semantic_id: first.semantic_id,
      message:
        "More than one mounted layer lowers #{kind} #{name} into the #{target} target, " <>
          "which still names it by its short name",
      provenance: first.provenance,
      metadata: %{
        kind: kind,
        name: name,
        mounts: mounts,
        layer_ids: order(plan, for({id, m} <- plan.by_layer, m in mounts, do: id)),
        semantic_ids: group |> Enum.map(& &1.semantic_id) |> Enum.sort()
      }
    })
  end

  # The deepest mount a declaration sits under; '/' for the compiler's root and authored paths
  # outside every mount.
  defp mount_of(plan, declaration) do
    plan.by_layer
    |> Map.values()
    |> Enum.filter(&under?(declaration.qualified_name, &1))
    |> Enum.max_by(&String.length/1, fn -> "/" end)
  end

  defp under?(_path, "/"), do: true
  defp under?(path, mount), do: path == mount or String.starts_with?(path, mount <> "/")

  # Layer ids in the compile's own layer order.
  defp order(plan, layer_ids), do: Enum.filter(plan.layer_order, &(&1 in layer_ids))
end
