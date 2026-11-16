defmodule Cadence.Catalog.MissionModel.Target do
  @moduledoc "Versioned target legalization and lowering for Mission Model revisions."

  alias Cadence.Catalog.MissionModel.{
    Declaration,
    Diagnostic,
    Revision,
    RuntimePlan,
    TargetLowering
  }

  # Telemetry contract 3 (#92 (c)): fields carry their calibrator and enumerations, so decom
  # computes engineering values. It's OFF unless the server's configuration turns it on
  # (`calibration?/1`); off, every target compiles exactly as before calibration (contract 2).
  @contracts %{telemetry: "2", algorithm: "1", monitoring: "1", command: "2"}
  @calibrated_telemetry_contract "3"

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

  @doc """
  Compiles `revision` for `target`. `opts[:telemetry_calibration]` overrides the server's
  calibration setting (`calibration?/1`).
  """
  @spec compile(Revision.t(), atom(), keyword()) :: RuntimePlan.t()
  def compile(%Revision{} = revision, target, opts \\ []) when is_map_key(@contracts, target) do
    calibration? = calibration?(opts)

    declarations =
      revision.declarations
      |> Map.values()
      |> Enum.filter(&(&1.kind in Map.fetch!(@target_kinds, target)))
      |> Enum.sort_by(&{&1.qualified_name, &1.kind})

    legalization_diagnostics =
      revision.diagnostics ++
        Enum.flat_map(declarations, &legalize(&1, target, calibration?))

    {plan, lowering_diagnostics} =
      lower_plan(target, revision, declarations, revision.edges, calibration?)

    diagnostics = legalization_diagnostics ++ lowering_diagnostics

    RuntimePlan.new(revision, target, Map.fetch!(contracts(opts), target), plan, diagnostics)
  end

  @doc "Each target's contract version: telemetry is 3 only with calibration on."
  @spec contracts(keyword()) :: %{atom() => binary()}
  def contracts(opts \\ []) do
    if calibration?(opts),
      do: %{@contracts | telemetry: @calibrated_telemetry_contract},
      else: @contracts
  end

  @doc """
  Whether compiles lower calibration (telemetry contract 3, #92 (c)). Server configuration only,
  default off: `config :cadence_catalog, telemetry_calibration: true` turns it on, and that's the
  user's call (DECISIONS); the console can't set it. `opts[:telemetry_calibration]` overrides it.
  """
  @spec calibration?(keyword()) :: boolean()
  def calibration?(opts \\ []) do
    Keyword.get_lazy(opts, :telemetry_calibration, fn ->
      Application.get_env(:cadence_catalog, :telemetry_calibration, false)
    end) == true
  end

  # With calibration on, a polynomial calibrator lowers and states are checked; anything else
  # legalizes as it does with it off.
  defp legalize(%Declaration{kind: kind} = declaration, :telemetry, true)
       when kind in [:calibrator, :parameter_type],
       do: legalize_calibrated(declaration)

  defp legalize(declaration, target, _calibration?), do: legalize(declaration, target)

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

  # Calibration off (contract 2): no calibrator executes, so each is reported as before.
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

  # Calibration on (contract 3): polynomial calibrators execute at decom; state maps arrive as the
  # parameter type's enumerations; tables and splines aren't executable yet and say so.
  defp legalize_calibrated(%Declaration{kind: :calibrator} = declaration) do
    case value(declaration.definition, :algorithm_type) do
      kind when kind in [:polynomial, "polynomial"] ->
        []

      # XTCE adds math operations and context calibrators (#92 (c), part A).
      kind
      when kind in [
             :table,
             :state_map,
             :spline,
             :math_operation,
             :context,
             "table",
             "state_map",
             "spline",
             "math_operation",
             "context"
           ] ->
        [unsupported(declaration, :telemetry, "MM_CALIBRATOR_RUNTIME_UNSUPPORTED")]

      _other ->
        [unsupported(declaration, :telemetry, "MM_CALIBRATOR_UNSUPPORTED")]
    end
  end

  # A state whose value isn't an integer, or two states for one value, would make decom read the
  # raw value as an undefined state with nothing at compile time saying why (api-ops, 11-15).
  defp legalize_calibrated(%Declaration{kind: :parameter_type} = declaration) do
    states = List.wrap(value(declaration.definition, :enumerations))
    values = for state <- states, do: value(state, :value)

    invalid =
      for state <- states, not is_integer(value(state, :value)), do: value(state, :label)

    duplicated =
      values
      |> Enum.filter(&is_integer/1)
      |> Enum.frequencies()
      |> Enum.filter(&(elem(&1, 1) > 1))

    Enum.map(invalid, fn label ->
      enumeration_warning(
        declaration,
        "MM_ENUMERATION_VALUE_INVALID",
        "state #{inspect(label)} of #{declaration.name} has no integer value, so it never matches"
      )
    end) ++
      Enum.map(duplicated, fn {state_value, _count} ->
        enumeration_warning(
          declaration,
          "MM_ENUMERATION_VALUE_DUPLICATE",
          "#{declaration.name} names value #{state_value} more than once; the first label wins"
        )
      end)
  end

  defp lower_plan(:algorithm, _revision, declarations, edges, _calibration?) do
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

  defp lower_plan(:monitoring, _revision, declarations, edges, _calibration?) do
    {%{
       "target" => "monitoring",
       "policies" =>
         declarations
         |> Enum.filter(&(&1.kind == :monitoring_policy))
         |> Enum.map(&lower_monitoring/1),
       "edges" => edges
     }, []}
  end

  defp lower_plan(:telemetry, revision, declarations, _edges, calibration?),
    do: TargetLowering.telemetry(revision, declarations, calibration?)

  defp lower_plan(:command, revision, declarations, _edges, calibration?),
    do: TargetLowering.command(revision, declarations, calibration?)

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

  defp enumeration_warning(declaration, code, message) do
    Diagnostic.new(%{
      code: code,
      severity: :warning,
      stage: :legalization,
      target: :telemetry,
      semantic_id: declaration.semantic_id,
      support: :lossy,
      message: message,
      provenance: declaration.provenance
    })
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
