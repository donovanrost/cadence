defmodule Cadence.Catalog.MissionModel.Compiler do
  @moduledoc "Deterministic Mission Model layer composition and reference resolution."

  alias Cadence.Catalog.MissionModel.{
    CompilerResult,
    Declaration,
    Defaults,
    Diagnostic,
    Inheritance,
    Layer,
    Path,
    Reference,
    Revision,
    SpaceSystem,
    Target,
    Validator
  }

  @compiler_version "2"

  @spec compile([Layer.t()], keyword()) :: {:ok, CompilerResult.t()} | {:error, term()}
  def compile(layers, opts \\ [])

  def compile([%Layer{} | _rest] = layers, opts) do
    with :ok <- validate_layer_scope(layers),
         {declarations, composition_diagnostics} <- compose(layers),
         declarations <- Defaults.apply(declarations),
         {systems, hierarchy_diagnostics} <- build_space_systems(declarations),
         {resolved_declarations, edges, reference_diagnostics} <- resolve(declarations),
         {inherited_declarations, inheritance_diagnostics} <-
           Inheritance.apply(resolved_declarations, edges),
         validation_diagnostics <- Validator.validate(inherited_declarations),
         graph_diagnostics <- validate_graph(resolved_declarations, edges) do
      revision =
        Revision.build(%{
          organization_id: hd(layers).organization_id,
          mission_id: hd(layers).mission_id,
          compiler_version: @compiler_version,
          layer_ids: Enum.map(layers, & &1.layer_id),
          declarations: inherited_declarations,
          space_systems: systems,
          edges: edges,
          diagnostics:
            source_diagnostics(layers) ++
              composition_diagnostics ++
              hierarchy_diagnostics ++
              reference_diagnostics ++
              inheritance_diagnostics ++ validation_diagnostics ++ graph_diagnostics,
          metadata: Keyword.get(opts, :metadata, %{})
        })

      targets = Keyword.get(opts, :targets, Map.keys(Target.contracts()))
      plans = Map.new(targets, &{&1, Target.compile(revision, &1)})
      {:ok, %CompilerResult{revision: revision, plans: plans}}
    end
  end

  def compile([], _opts), do: {:error, :mission_model_layers_required}

  @spec compiler_version() :: binary()
  def compiler_version, do: @compiler_version

  defp validate_layer_scope([first | rest]) do
    if Enum.all?(rest, &same_scope?(first, &1)) do
      :ok
    else
      {:error, :mission_model_layer_scope_mismatch}
    end
  end

  defp same_scope?(left, right) do
    left.organization_id == right.organization_id and left.mission_id == right.mission_id
  end

  defp source_diagnostics(layers) do
    Enum.flat_map(layers, fn layer ->
      layer.metadata
      |> Map.get("source_diagnostics", Map.get(layer.metadata, :source_diagnostics, []))
      |> Enum.map(fn source ->
        Diagnostic.new(%{
          code: value(source, :code),
          severity: value(source, :severity),
          stage: :source_validation,
          message: value(source, :message),
          metadata: %{
            layer_id: layer.layer_id,
            path: value(source, :path, []),
            source_metadata: value(source, :metadata, %{})
          }
        })
      end)
    end)
  end

  defp compose(layers) do
    Enum.reduce(layers, {%{}, []}, fn layer, {declarations, diagnostics} ->
      Enum.reduce(layer.declarations, {declarations, diagnostics}, fn declaration, acc ->
        apply_declaration(layer, declaration, acc)
      end)
    end)
  end

  defp apply_declaration(
         layer,
         %Declaration{operation: :add} = declaration,
         {declarations, diagnostics}
       ) do
    case Map.fetch(declarations, declaration.semantic_id) do
      :error ->
        {Map.put(declarations, declaration.semantic_id, declaration), diagnostics}

      {:ok, existing} ->
        {declarations, [duplicate_diagnostic(layer, declaration, existing) | diagnostics]}
    end
  end

  defp apply_declaration(
         layer,
         %Declaration{operation: :extend} = declaration,
         {declarations, diagnostics}
       ) do
    change_existing(layer, declaration, declarations, diagnostics, fn %Declaration{} = existing ->
      %Declaration{
        existing
        | aliases: Enum.uniq(existing.aliases ++ declaration.aliases),
          definition: deep_merge(existing.definition, declaration.definition),
          references: merge_references(existing.references, declaration.references),
          extensions: deep_merge(existing.extensions, declaration.extensions),
          provenance: declaration.provenance || existing.provenance
      }
    end)
  end

  defp apply_declaration(
         layer,
         %Declaration{operation: :replace} = declaration,
         {declarations, diagnostics}
       ) do
    change_existing(layer, declaration, declarations, diagnostics, fn _existing ->
      %Declaration{declaration | operation: :add}
    end)
  end

  defp apply_declaration(
         layer,
         %Declaration{operation: :remove} = declaration,
         {declarations, diagnostics}
       ) do
    case fetch_expected(layer, declaration, declarations) do
      {:ok, _existing} -> {Map.delete(declarations, declaration.semantic_id), diagnostics}
      {:error, diagnostic} -> {declarations, [diagnostic | diagnostics]}
    end
  end

  defp change_existing(layer, declaration, declarations, diagnostics, fun) do
    case fetch_expected(layer, declaration, declarations) do
      {:ok, existing} ->
        {Map.put(declarations, declaration.semantic_id, fun.(existing)), diagnostics}

      {:error, diagnostic} ->
        {declarations, [diagnostic | diagnostics]}
    end
  end

  defp fetch_expected(layer, declaration, declarations) do
    case Map.fetch(declarations, declaration.semantic_id) do
      :error -> {:error, missing_override_diagnostic(layer, declaration)}
      {:ok, existing} -> validate_expected_fingerprint(layer, declaration, existing)
    end
  end

  defp validate_expected_fingerprint(layer, declaration, existing) do
    case declaration.expected_fingerprint do
      nil ->
        {:error, missing_fingerprint_diagnostic(layer, declaration)}

      expected ->
        if expected == Declaration.fingerprint(existing) do
          {:ok, existing}
        else
          {:error, drift_diagnostic(layer, declaration)}
        end
    end
  end

  defp build_space_systems(declarations) do
    system_declarations = Enum.filter(Map.values(declarations), &(&1.kind == :space_system))
    by_path = Map.new(system_declarations, &{&1.qualified_name, &1})

    Enum.reduce(system_declarations, {%{}, []}, fn declaration, {systems, diagnostics} ->
      parent_path = Path.parent(declaration.qualified_name)

      cond do
        declaration.qualified_name == "/" ->
          system = SpaceSystem.new(Map.from_struct(declaration))
          {Map.put(systems, system.semantic_id, system), diagnostics}

        is_nil(Map.get(by_path, parent_path)) ->
          diagnostic =
            Diagnostic.new(%{
              code: "MM_SPACE_SYSTEM_PARENT_MISSING",
              severity: :error,
              stage: :namespace,
              semantic_id: declaration.semantic_id,
              message: "SpaceSystem parent #{parent_path} does not exist",
              provenance: declaration.provenance
            })

          {systems, [diagnostic | diagnostics]}

        true ->
          parent = Map.fetch!(by_path, parent_path)

          system =
            SpaceSystem.new(%{
              semantic_id: declaration.semantic_id,
              name: declaration.name,
              qualified_name: declaration.qualified_name,
              parent_id: parent.semantic_id,
              aliases: declaration.aliases,
              metadata: declaration.definition,
              provenance: declaration.provenance
            })

          {Map.put(systems, system.semantic_id, system), diagnostics}
      end
    end)
  end

  defp resolve(declarations) do
    symbols =
      Map.new(declarations, fn {_id, declaration} ->
        {{declaration.kind, declaration.qualified_name}, declaration}
      end)

    Enum.reduce(declarations, {%{}, [], []}, fn {id, %Declaration{} = declaration},
                                                {resolved, edges, diagnostics} ->
      {references, reference_edges, reference_diagnostics} =
        resolve_references(declaration, symbols)

      resolved_declaration = %Declaration{declaration | references: references}

      {
        Map.put(resolved, id, resolved_declaration),
        reference_edges ++ edges,
        reference_diagnostics ++ diagnostics
      }
    end)
  end

  defp resolve_references(declaration, symbols) do
    Enum.reduce(declaration.references, {[], [], []}, fn %Reference{} = reference,
                                                         {references, edges, diagnostics} ->
      qualified_name = Path.resolve(declaration.qualified_name, reference.source_ref)

      case Map.fetch(symbols, {reference.expected_kind, qualified_name}) do
        {:ok, target} ->
          resolved_reference = %Reference{
            reference
            | resolved_id: target.semantic_id,
              resolved_qualified_name: target.qualified_name
          }

          edge = %{
            from: declaration.semantic_id,
            to: target.semantic_id,
            role: reference.role,
            required: reference.required
          }

          {[resolved_reference | references], [edge | edges], diagnostics}

        :error ->
          diagnostic =
            unresolved_reference_diagnostic(declaration, reference, qualified_name, symbols)

          {[reference | references], edges, [diagnostic | diagnostics]}
      end
    end)
    |> then(fn {references, edges, diagnostics} ->
      {Enum.reverse(references), Enum.reverse(edges), Enum.reverse(diagnostics)}
    end)
  end

  defp validate_graph(declarations, edges) do
    algorithm_ids =
      declarations
      |> Enum.filter(fn {_id, declaration} -> declaration.kind == :algorithm end)
      |> Map.new(fn {id, _declaration} -> {id, true} end)

    direct_algorithm_edges =
      Enum.filter(edges, fn edge ->
        Map.has_key?(algorithm_ids, edge.from) and Map.has_key?(algorithm_ids, edge.to)
      end)

    producer_by_parameter =
      edges
      |> Enum.filter(fn edge ->
        Map.has_key?(algorithm_ids, edge.from) and edge.role == :output
      end)
      |> Enum.group_by(& &1.to, & &1.from)

    derived_algorithm_edges =
      edges
      |> Enum.filter(fn edge ->
        Map.has_key?(algorithm_ids, edge.from) and edge.role == :input
      end)
      |> Enum.flat_map(fn edge ->
        Enum.map(Map.get(producer_by_parameter, edge.to, []), fn producer_id ->
          %{from: edge.from, to: producer_id, role: :algorithm_dependency, required: true}
        end)
      end)

    cycle_diagnostics(algorithm_ids, direct_algorithm_edges ++ derived_algorithm_edges) ++
      ambiguous_algorithm_producer_diagnostics(producer_by_parameter, declarations)
  end

  defp ambiguous_algorithm_producer_diagnostics(producer_by_parameter, declarations) do
    producer_by_parameter
    |> Enum.filter(fn {_parameter_id, producers} -> length(Enum.uniq(producers)) > 1 end)
    |> Enum.map(fn {parameter_id, producers} ->
      parameter = Map.get(declarations, parameter_id)

      Diagnostic.new(%{
        code: "MM_PARAMETER_ALGORITHM_PRODUCER_AMBIGUOUS",
        severity: :error,
        stage: :graph,
        semantic_id: parameter_id,
        message: "Parameter has more than one algorithm producer",
        provenance: parameter && parameter.provenance,
        metadata: %{producer_ids: Enum.uniq(producers) |> Enum.sort()}
      })
    end)
  end

  defp cycle_diagnostics(algorithm_ids, edges) do
    adjacency = Enum.group_by(edges, & &1.from, & &1.to)

    algorithm_ids
    |> Map.keys()
    |> Enum.reduce({MapSet.new(), []}, fn id, {visited, diagnostics} ->
      case find_cycle(id, adjacency, visited, []) do
        {:ok, next_visited} ->
          {next_visited, diagnostics}

        {:cycle, cycle, next_visited} ->
          diagnostic =
            Diagnostic.new(%{
              code: "MM_ALGORITHM_CYCLE",
              severity: :error,
              stage: :graph,
              semantic_id: id,
              message: "Algorithm dependency cycle detected",
              metadata: %{cycle: cycle}
            })

          {next_visited, [diagnostic | diagnostics]}
      end
    end)
    |> elem(1)
  end

  defp find_cycle(id, adjacency, visited, stack) do
    cond do
      id in stack -> {:cycle, Enum.reverse([id | stack]), MapSet.put(visited, id)}
      MapSet.member?(visited, id) -> {:ok, visited}
      true -> walk_neighbors(id, Map.get(adjacency, id, []), adjacency, visited, [id | stack])
    end
  end

  defp walk_neighbors(id, neighbors, adjacency, visited, stack) do
    Enum.reduce_while(neighbors, {:ok, MapSet.put(visited, id)}, fn neighbor, {:ok, acc} ->
      case find_cycle(neighbor, adjacency, acc, stack) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:cycle, cycle, next} -> {:halt, {:cycle, cycle, next}}
      end
    end)
  end

  defp unresolved_reference_diagnostic(declaration, reference, qualified_name, symbols) do
    wrong_kind? = Enum.any?(symbols, fn {{_kind, path}, _value} -> path == qualified_name end)

    Diagnostic.new(%{
      code: if(wrong_kind?, do: "MM_REFERENCE_WRONG_KIND", else: "MM_REFERENCE_DANGLING"),
      severity: if(reference.required, do: :error, else: :warning),
      stage: :reference_resolution,
      semantic_id: declaration.semantic_id,
      message:
        "Unable to resolve #{reference.expected_kind} reference #{reference.source_ref} from #{declaration.qualified_name}",
      provenance: reference.provenance || declaration.provenance,
      metadata: %{resolved_path: qualified_name, expected_kind: reference.expected_kind}
    })
  end

  defp duplicate_diagnostic(layer, declaration, existing) do
    conflict(layer, declaration, "MM_DUPLICATE_IDENTITY", "Duplicate semantic identity", %{
      existing_fingerprint: Declaration.fingerprint(existing)
    })
  end

  defp missing_override_diagnostic(layer, declaration),
    do:
      conflict(layer, declaration, "MM_OVERRIDE_TARGET_MISSING", "Override target does not exist")

  defp missing_fingerprint_diagnostic(layer, declaration),
    do:
      conflict(
        layer,
        declaration,
        "MM_OVERRIDE_FINGERPRINT_REQUIRED",
        "Override requires an expected fingerprint"
      )

  defp drift_diagnostic(layer, declaration),
    do:
      conflict(
        layer,
        declaration,
        "MM_OVERRIDE_REVISION_DRIFT",
        "Override target fingerprint has changed"
      )

  defp conflict(layer, declaration, code, message, metadata \\ %{}) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :composition,
      semantic_id: declaration.semantic_id,
      message: message,
      provenance: declaration.provenance,
      metadata: Map.put(metadata, :layer_id, layer.layer_id)
    })
  end

  defp merge_references(left, right) do
    (left ++ right)
    |> Enum.uniq_by(&{&1.expected_kind, &1.source_ref, &1.role})
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right),
    do: Map.merge(left, right, fn _key, l, r -> deep_merge(l, r) end)

  defp deep_merge(_left, right), do: right

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
