defmodule Cadence.Catalog.MissionModel.Validator do
  @moduledoc "Performs semantic validation after defaults, resolution, and inheritance."

  alias Cadence.Catalog.MissionModel.{Declaration, Diagnostic, Expression}

  @base_types [
    :integer,
    :float,
    :string,
    :binary,
    :boolean,
    :enumerated,
    :aggregate,
    :array,
    :absolute_time,
    :relative_time
  ]
  @timer_trigger_kinds [:periodic, "periodic", :timer, "timer"]

  @spec validate(%{binary() => Declaration.t()}) :: [Diagnostic.t()]
  def validate(declarations) when is_map(declarations) do
    duplicate_qualified_names(declarations) ++
      Enum.flat_map(Map.values(declarations), &validate_declaration/1)
  end

  defp duplicate_qualified_names(declarations) do
    declarations
    |> Map.values()
    |> Enum.group_by(&{&1.kind, &1.qualified_name})
    |> Enum.filter(fn {_identity, grouped} -> length(grouped) > 1 end)
    |> Enum.map(fn {{kind, qualified_name}, grouped} ->
      first = hd(grouped)

      diagnostic(
        first,
        "MM_DUPLICATE_QUALIFIED_NAME",
        "More than one #{kind} declaration has qualified name #{qualified_name}",
        %{semantic_ids: Enum.map(grouped, & &1.semantic_id) |> Enum.sort()},
        :composition
      )
    end)
  end

  defp validate_declaration(%Declaration{kind: kind} = declaration)
       when kind in [:parameter_type, :command_argument_type] do
    case value(declaration.definition, :base_type) do
      nil -> []
      base_type when base_type in @base_types -> []
      base_type when is_binary(base_type) -> validate_binary_base_type(declaration, base_type)
      _other -> [invalid_type(declaration)]
    end
  end

  defp validate_declaration(%Declaration{kind: :algorithm} = declaration) do
    outputs = value(declaration.definition, :outputs, [])
    triggers = value(declaration.definition, :triggers, [])

    validate_algorithm_outputs(declaration, outputs) ++
      validate_algorithm_triggers(declaration, triggers)
  end

  defp validate_declaration(%Declaration{kind: :monitoring_policy} = declaration) do
    parameter? =
      Enum.any?(declaration.references, fn reference ->
        reference.role == :parameter and is_binary(reference.resolved_id)
      end)

    counts_valid? =
      positive_integer?(value(declaration.definition, :minimum_violations, 1)) and
        positive_integer?(value(declaration.definition, :minimum_conformance, 1))

    []
    |> maybe_add(
      not parameter?,
      diagnostic(
        declaration,
        "MM_MONITORING_PARAMETER_REQUIRED",
        "Monitoring policies require one resolved parameter reference"
      )
    )
    |> maybe_add(
      not counts_valid?,
      diagnostic(
        declaration,
        "MM_MONITORING_PERSISTENCE_INVALID",
        "Monitoring persistence counts must be positive integers"
      )
    )
  end

  defp validate_declaration(%Declaration{kind: :command_constraint} = declaration) do
    criteria = value(declaration.definition, :criteria)

    if valid_criteria?(criteria) do
      []
    else
      [
        diagnostic(
          declaration,
          "MM_COMMAND_CRITERIA_REQUIRED",
          "Command constraints and verifiers require executable criteria"
        )
      ]
    end
  end

  defp validate_declaration(%Declaration{kind: :command_verifier} = declaration) do
    success = value(declaration.definition, :success_criteria)
    failure = value(declaration.definition, :failure_criteria)

    if valid_criteria?(success) or valid_criteria?(failure) do
      []
    else
      [
        diagnostic(
          declaration,
          "MM_COMMAND_CRITERIA_REQUIRED",
          "Command constraints and verifiers require executable criteria"
        )
      ]
    end
  end

  defp validate_declaration(%Declaration{}), do: []

  defp validate_algorithm_outputs(declaration, outputs) when is_list(outputs) do
    output_ids =
      declaration.references
      |> Enum.filter(&(&1.role == :output and is_binary(&1.resolved_id)))
      |> MapSet.new(& &1.resolved_id)

    cond do
      outputs == [] and MapSet.size(output_ids) > 0 ->
        [
          diagnostic(
            declaration,
            "MM_ALGORITHM_OUTPUT_DEFINITION_REQUIRED",
            "Algorithm output references require matching output definitions"
          )
        ]

      Enum.all?(outputs, &valid_output?(&1, output_ids)) ->
        []

      true ->
        [
          diagnostic(
            declaration,
            "MM_ALGORITHM_OUTPUT_INVALID",
            "Algorithm outputs must identify a resolved output parameter and a typed expression"
          )
        ]
    end
  end

  defp validate_algorithm_outputs(declaration, _outputs) do
    [diagnostic(declaration, "MM_ALGORITHM_OUTPUT_INVALID", "Algorithm outputs must be a list")]
  end

  defp valid_output?(output, output_ids) when is_map(output) do
    parameter_id = value(output, :parameter_id)
    expression = value(output, :expression)

    is_binary(parameter_id) and MapSet.member?(output_ids, parameter_id) and
      match?(%Expression{}, build_expression(expression))
  rescue
    _error -> false
  end

  defp valid_output?(_output, _output_ids), do: false

  defp build_expression(%Expression{} = expression), do: expression
  defp build_expression(expression) when is_map(expression), do: Expression.new(expression)
  defp build_expression(_expression), do: nil

  defp validate_algorithm_triggers(declaration, triggers) when is_list(triggers) do
    if Enum.all?(triggers, &valid_trigger?/1) do
      []
    else
      [
        diagnostic(
          declaration,
          "MM_ALGORITHM_TRIGGER_INVALID",
          "Periodic algorithm triggers require a positive interval_ms"
        )
      ]
    end
  end

  defp validate_algorithm_triggers(declaration, _triggers) do
    [diagnostic(declaration, "MM_ALGORITHM_TRIGGER_INVALID", "Algorithm triggers must be a list")]
  end

  defp valid_trigger?(trigger) when is_map(trigger) do
    case value(trigger, :kind) do
      kind when kind in @timer_trigger_kinds -> positive_integer?(value(trigger, :interval_ms))
      _kind -> true
    end
  end

  defp valid_trigger?(_trigger), do: false

  defp valid_criteria?(%{__struct__: _module}), do: true

  defp valid_criteria?(criteria) when is_map(criteria) do
    comparisons = value(criteria, :comparisons)

    cond do
      is_list(comparisons) -> comparisons != []
      not is_nil(value(criteria, :node)) -> true
      not is_nil(value(criteria, :conditions)) -> true
      true -> false
    end
  end

  defp valid_criteria?(_criteria), do: false

  defp validate_binary_base_type(declaration, base_type) do
    if base_type in Enum.map(@base_types, &Atom.to_string/1),
      do: [],
      else: [invalid_type(declaration)]
  end

  defp invalid_type(declaration) do
    diagnostic(
      declaration,
      "MM_TYPE_BASE_UNSUPPORTED",
      "Type declaration has an unsupported base type"
    )
  end

  defp maybe_add(diagnostics, true, diagnostic), do: diagnostics ++ [diagnostic]
  defp maybe_add(diagnostics, false, _diagnostic), do: diagnostics

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp diagnostic(declaration, code, message, metadata \\ %{}, stage \\ :semantic_validation) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: stage,
      semantic_id: declaration.semantic_id,
      message: message,
      provenance: declaration.provenance,
      metadata: metadata
    })
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
