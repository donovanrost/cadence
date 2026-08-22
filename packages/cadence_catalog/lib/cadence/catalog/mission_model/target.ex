defmodule Cadence.Catalog.MissionModel.Target do
  @moduledoc "Versioned target legalization and lowering for Mission Model revisions."

  alias Cadence.Catalog.MissionModel.{
    Declaration,
    Diagnostic,
    Revision,
    RuntimePlan,
    TargetLowering
  }

  @contracts %{telemetry: "2", algorithm: "1", monitoring: "1", command: "2"}

  @target_kinds %{
    telemetry: [
      :space_system,
      :unit,
      :parameter_type,
      :parameter,
      :container,
      :calibrator,
      :stream,
      :service,
      :extension
    ],
    algorithm: [:space_system, :parameter_type, :parameter, :algorithm, :extension],
    monitoring: [
      :space_system,
      :parameter_type,
      :parameter,
      :monitoring_policy,
      :extension
    ],
    command: [
      :space_system,
      :parameter,
      :command_argument_type,
      :command_argument,
      :command_encoding,
      :command,
      :command_constraint,
      :command_verifier,
      :stream,
      :service,
      :extension
    ]
  }

  @spec compile(Revision.t(), atom()) :: RuntimePlan.t()
  def compile(%Revision{} = revision, target) when is_map_key(@contracts, target) do
    declarations =
      revision.declarations
      |> Map.values()
      |> Enum.filter(&(&1.kind in Map.fetch!(@target_kinds, target)))
      |> Enum.sort_by(&{&1.qualified_name, &1.kind})

    legalization_diagnostics =
      revision.diagnostics ++ Enum.flat_map(declarations, &legalize(&1, target))

    {plan, lowering_diagnostics} = lower_plan(target, revision, declarations, revision.edges)
    diagnostics = legalization_diagnostics ++ lowering_diagnostics

    RuntimePlan.new(revision, target, Map.fetch!(@contracts, target), plan, diagnostics)
  end

  @spec contracts() :: %{atom() => binary()}
  def contracts, do: @contracts

  defp legalize(%Declaration{kind: :algorithm} = declaration, :algorithm) do
    implementation = value(declaration.definition, :implementation, %{})

    case value(implementation, :kind, :expression) do
      kind when kind in [:expression, "expression"] ->
        []

      kind when kind in [:registered, "registered"] ->
        if non_empty_binary?(value(implementation, :key)) and
             non_empty_binary?(value(implementation, :version)) and
             non_empty_binary?(value(implementation, :artifact_sha256)) do
          []
        else
          [
            Diagnostic.new(%{
              code: "MM_REGISTERED_IMPLEMENTATION_IDENTITY_REQUIRED",
              severity: :error,
              stage: :legalization,
              target: :algorithm,
              semantic_id: declaration.semantic_id,
              support: :invalid,
              message:
                "registered algorithms require an allowlist key, version, and approved artifact hash",
              provenance: declaration.provenance
            })
          ]
        end

      _other ->
        [unsupported(declaration, :algorithm, "MM_ALGORITHM_IMPLEMENTATION_UNSUPPORTED")]
    end
  end

  defp legalize(%Declaration{kind: :calibrator} = declaration, :telemetry) do
    case value(declaration.definition, :algorithm_type) do
      kind when kind in [:polynomial, :table, :state_map, "polynomial", "table", "state_map"] ->
        [unsupported(declaration, :telemetry, "MM_CALIBRATOR_RUNTIME_UNSUPPORTED")]

      _other ->
        [unsupported(declaration, :telemetry, "MM_CALIBRATOR_UNSUPPORTED")]
    end
  end

  defp legalize(%Declaration{kind: :container} = declaration, :telemetry) do
    if is_integer(value(declaration.definition, :apid)) and
         is_list(value(declaration.definition, :entries)) do
      []
    else
      [unsupported_required(declaration, :telemetry, "MM_TELEMETRY_CONTAINER_NOT_LOWERABLE")]
    end
  end

  defp legalize(%Declaration{kind: :command} = declaration, :command) do
    if Enum.any?(declaration.references, &(&1.role == :encoding and is_binary(&1.resolved_id))) do
      []
    else
      [unsupported_required(declaration, :command, "MM_COMMAND_DEFINITION_NOT_LOWERABLE")]
    end
  end

  defp legalize(%Declaration{kind: kind} = declaration, target)
       when kind in [:stream, :service, :extension] do
    if target_applies?(declaration, target) do
      [unsupported(declaration, target, "MM_DECLARATION_PRESERVED")]
    else
      []
    end
  end

  defp legalize(%Declaration{}, _target), do: []

  defp lower_plan(:algorithm, _revision, declarations, edges) do
    {%{
       "target" => "algorithm",
       "algorithms" =>
         declarations
         |> Enum.filter(&(&1.kind == :algorithm))
         |> order_algorithms(edges)
         |> Enum.map(&lower_algorithm/1),
       "edges" => edges
     }, []}
  end

  defp lower_plan(:monitoring, _revision, declarations, edges) do
    {%{
       "target" => "monitoring",
       "policies" =>
         declarations
         |> Enum.filter(&(&1.kind == :monitoring_policy))
         |> Enum.map(&lower_monitoring/1),
       "edges" => edges
     }, []}
  end

  defp lower_plan(:telemetry, revision, declarations, _edges),
    do: TargetLowering.telemetry(revision, declarations)

  defp lower_plan(:command, revision, declarations, _edges),
    do: TargetLowering.command(revision, declarations)

  defp lower_algorithm(declaration) do
    inputs =
      declaration.references
      |> Enum.filter(&(&1.role == :input and is_binary(&1.resolved_id)))
      |> Enum.map(& &1.resolved_id)

    declaration.definition
    |> stringify_keys()
    |> Map.put("algorithm_id", declaration.semantic_id)
    |> Map.put("input_parameter_ids", inputs)
  end

  defp order_algorithms(algorithms, edges) do
    algorithm_ids = MapSet.new(algorithms, & &1.semantic_id)

    producer_by_parameter =
      edges
      |> Enum.filter(&(&1.role == :output and MapSet.member?(algorithm_ids, &1.from)))
      |> Enum.group_by(& &1.to, & &1.from)

    dependencies =
      Map.new(algorithms, fn algorithm ->
        dependency_ids =
          edges
          |> Enum.filter(&(&1.from == algorithm.semantic_id and &1.role == :input))
          |> Enum.flat_map(&Map.get(producer_by_parameter, &1.to, []))
          |> Enum.filter(&(&1 != algorithm.semantic_id))
          |> MapSet.new()

        {algorithm.semantic_id, dependency_ids}
      end)

    by_id = Map.new(algorithms, &{&1.semantic_id, &1})
    topological_algorithms(dependencies, by_id, [])
  end

  defp topological_algorithms(dependencies, _by_id, ordered) when map_size(dependencies) == 0,
    do: Enum.reverse(ordered)

  defp topological_algorithms(dependencies, by_id, ordered) do
    ready =
      dependencies
      |> Enum.filter(fn {_id, requirements} -> MapSet.size(requirements) == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&Map.fetch!(by_id, &1).qualified_name)

    case ready do
      [] ->
        by_id |> Map.values() |> Enum.sort_by(& &1.qualified_name)

      _ready ->
        next_dependencies =
          dependencies
          |> Map.drop(ready)
          |> Map.new(fn {id, requirements} ->
            {id, Enum.reduce(ready, requirements, &MapSet.delete(&2, &1))}
          end)

        next_ordered = Enum.reduce(ready, ordered, &[Map.fetch!(by_id, &1) | &2])
        topological_algorithms(next_dependencies, by_id, next_ordered)
    end
  end

  defp lower_monitoring(declaration) do
    parameter_id =
      declaration.references
      |> Enum.find(&(&1.role == :parameter and is_binary(&1.resolved_id)))
      |> case do
        nil -> nil
        reference -> reference.resolved_id
      end

    declaration.definition
    |> stringify_keys()
    |> Map.put("policy_id", declaration.semantic_id)
    |> Map.put("parameter_id", parameter_id)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp unsupported(declaration, target, code) do
    required = value(declaration.definition, :required, false)

    Diagnostic.new(%{
      code: code,
      severity: if(required, do: :error, else: :warning),
      stage: :legalization,
      target: target,
      semantic_id: declaration.semantic_id,
      support: :preserved,
      message: "#{declaration.kind} is preserved but is not executable by #{target} target v1",
      provenance: declaration.provenance
    })
  end

  defp unsupported_required(declaration, target, code) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :legalization,
      target: target,
      semantic_id: declaration.semantic_id,
      support: :preserved,
      message: "#{declaration.kind} is preserved but cannot be lowered to #{target} target v1",
      provenance: declaration.provenance
    })
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp non_empty_binary?(value), do: is_binary(value) and value != ""

  defp target_applies?(declaration, target) do
    case value(declaration.definition, :applies_to) do
      nil -> true
      targets when is_list(targets) -> target in targets or Atom.to_string(target) in targets
      declared -> declared in [target, Atom.to_string(target)]
    end
  end
end
