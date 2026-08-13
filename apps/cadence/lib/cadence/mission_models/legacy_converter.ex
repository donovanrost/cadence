defmodule Cadence.MissionModels.LegacyConverter do
  @moduledoc """
  One-time converter from the transitional Derived Telemetry and Limits
  definitions into an authored Mission Model layer.
  """

  alias Cadence.Catalog.MissionModel.{
    Canonical,
    Declaration,
    Diagnostic,
    Expression,
    Layer,
    Reference,
    Revision
  }

  alias Cadence.DerivedTelemetry.{Definition, ExpressionParser}
  alias Cadence.Limits.Definition, as: LimitDefinition

  @spec convert(Revision.t(), [Definition.t()], [LimitDefinition.t()], keyword()) ::
          {:ok, Layer.t(), [Diagnostic.t()]} | {:error, term()}
  def convert(%Revision{} = revision, derived_definitions, limit_definitions, opts \\ [])
      when is_list(derived_definitions) and is_list(limit_definitions) and is_list(opts) do
    base_lookup = declaration_lookup(revision.declarations)

    state = %{
      declarations: namespace_declarations(revision),
      diagnostics: [],
      lookup: base_lookup,
      revision: revision
    }

    state = Enum.reduce(derived_definitions, state, &convert_derived/2)
    state = Enum.reduce(limit_definitions, state, &convert_limit/2)

    layer =
      Layer.new(%{
        organization_id: revision.organization_id,
        mission_id: revision.mission_id,
        layer_kind: :authored,
        name: Keyword.get(opts, :name, "Legacy semantic definitions conversion"),
        source: %{
          converter: "cadence_legacy_semantics",
          converter_version: "1",
          base_revision_id: revision.revision_id
        },
        declarations: Enum.reverse(state.declarations),
        metadata: %{
          "converted_by" => Keyword.get(opts, :actor, %{}),
          "derived_definition_count" => length(derived_definitions),
          "limit_definition_count" => length(limit_definitions)
        }
      })

    {:ok, layer, Enum.reverse(state.diagnostics)}
  end

  defp convert_derived(%Definition{} = definition, state) do
    with {:ok, ast} <- ExpressionParser.parse(definition.expression),
         {:ok, expression, input_declarations} <- convert_expression(ast, state.lookup) do
      parameter_path =
        "/cadence/derived_parameters/" <>
          path_segment(definition.point_name || definition.point_id)

      algorithm_path =
        "/cadence/algorithms/" <> path_segment(definition.derived_definition_id)

      parameter =
        Declaration.new(%{
          kind: :parameter,
          qualified_name: parameter_path,
          aliases: Enum.uniq([definition.point_id, definition.point_name]),
          definition: %{
            source: :algorithm,
            legacy_definition_id: definition.derived_definition_id,
            legacy_version: definition.version
          },
          provenance: legacy_provenance(:derived_telemetry, definition.derived_definition_id)
        })

      references =
        Enum.map(input_declarations, fn input ->
          Reference.new(%{
            expected_kind: :parameter,
            source_ref: input.qualified_name,
            role: :input
          })
        end) ++
          [
            Reference.new(%{
              expected_kind: :parameter,
              source_ref: parameter.qualified_name,
              role: :output
            })
          ]

      algorithm =
        Declaration.new(%{
          kind: :algorithm,
          qualified_name: algorithm_path,
          definition: %{
            implementation: %{kind: :expression},
            outputs: [
              %{
                parameter_id: parameter.semantic_id,
                qualified_name: parameter.qualified_name,
                expression: Expression.new(%{node: expression, result_type: :any})
              }
            ],
            legacy_expression: definition.expression,
            legacy_definition_id: definition.derived_definition_id,
            legacy_version: definition.version
          },
          references: references,
          provenance: legacy_provenance(:derived_telemetry, definition.derived_definition_id)
        })

      %{
        state
        | declarations: [algorithm, parameter | state.declarations],
          lookup: put_lookup(state.lookup, parameter)
      }
    else
      {:error, reason} ->
        diagnostic =
          conversion_diagnostic(
            "MM_LEGACY_DERIVED_CONVERSION_FAILED",
            definition.derived_definition_id,
            reason
          )

        %{state | diagnostics: [diagnostic | state.diagnostics]}
    end
  end

  defp convert_limit(%LimitDefinition{} = definition, state) do
    case lookup_parameter(state.lookup, definition.point_id) do
      {:ok, parameter} ->
        rules = threshold_rules(definition.thresholds)

        policy =
          Declaration.new(%{
            kind: :monitoring_policy,
            qualified_name:
              "/cadence/monitoring/" <> path_segment(definition.limit_definition_id),
            definition: %{
              default_rules: rules,
              minimum_violations: metadata_integer(definition.metadata, :minimum_violations, 1),
              minimum_conformance: metadata_integer(definition.metadata, :minimum_conformance, 1),
              legacy_limit_set_name: definition.limit_set_name,
              legacy_version: definition.version
            },
            references: [
              Reference.new(%{
                expected_kind: :parameter,
                source_ref: parameter.qualified_name,
                role: :parameter
              })
            ],
            provenance: legacy_provenance(:limits, definition.limit_definition_id)
          })

        %{state | declarations: [policy | state.declarations]}

      {:error, reason} ->
        diagnostic =
          conversion_diagnostic(
            "MM_LEGACY_LIMIT_PARAMETER_UNRESOLVED",
            definition.limit_definition_id,
            reason
          )

        %{state | diagnostics: [diagnostic | state.diagnostics]}
    end
  end

  defp convert_expression({:number, value}, _lookup), do: {:ok, {:literal, value}, []}

  defp convert_expression({:variable, name}, lookup) do
    case lookup_parameter(lookup, name) do
      {:ok, parameter} -> {:ok, {:parameter, parameter.semantic_id}, [parameter]}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_expression({operation, left, right}, lookup)
       when operation in [:add, :subtract, :multiply, :divide] do
    with {:ok, converted_left, left_inputs} <- convert_expression(left, lookup),
         {:ok, converted_right, right_inputs} <- convert_expression(right, lookup) do
      {:ok, {binary_operator(operation), converted_left, converted_right},
       unique_inputs(left_inputs ++ right_inputs)}
    end
  end

  defp convert_expression({:comparison, operation, left, right}, lookup) do
    with {:ok, converted_left, left_inputs} <- convert_expression(left, lookup),
         {:ok, converted_right, right_inputs} <- convert_expression(right, lookup) do
      {:ok, {comparison_operator(operation), converted_left, converted_right},
       unique_inputs(left_inputs ++ right_inputs)}
    end
  end

  defp convert_expression({:negate, [inner]}, lookup) do
    with {:ok, converted, inputs} <- convert_expression(inner, lookup) do
      {:ok, {:-, {:literal, 0}, converted}, inputs}
    end
  end

  defp convert_expression({:conditional, {condition, on_true, on_false}}, lookup) do
    with {:ok, converted_condition, condition_inputs} <- convert_expression(condition, lookup),
         {:ok, converted_true, true_inputs} <- convert_expression(on_true, lookup),
         {:ok, converted_false, false_inputs} <- convert_expression(on_false, lookup) do
      {:ok, {:if, converted_condition, converted_true, converted_false},
       unique_inputs(condition_inputs ++ true_inputs ++ false_inputs)}
    end
  end

  defp convert_expression({:function, {name, arguments}}, lookup) do
    with {:ok, converted_arguments, inputs} <- convert_arguments(arguments, lookup) do
      convert_function(name, converted_arguments, inputs)
    end
  end

  defp convert_expression(ast, _lookup), do: {:error, {:unsupported_legacy_ast, ast}}

  defp convert_arguments(arguments, lookup) do
    Enum.reduce_while(arguments, {:ok, [], []}, fn argument, {:ok, converted, inputs} ->
      case convert_expression(argument, lookup) do
        {:ok, converted_argument, argument_inputs} ->
          {:cont,
           {:ok, converted ++ [converted_argument], unique_inputs(inputs ++ argument_inputs)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp convert_function(name, arguments, inputs)
       when name in ["abs", "sqrt", "pow", "round", "floor", "ceil", "min", "max", "clamp"] do
    {:ok, {:call, String.to_existing_atom(name), arguments}, inputs}
  end

  defp convert_function(name, [argument | rest], inputs)
       when name in ["delta", "rate", "rolling_avg", "rolling_min", "rolling_max"] do
    function = String.to_existing_atom(name)
    settings = window_settings(rest)
    key = Canonical.sha256({name, argument, settings})
    {:ok, {:stateful, function, key, argument, settings}, inputs}
  end

  defp convert_function(name, _arguments, _inputs),
    do: {:error, {:unsupported_legacy_function, name}}

  defp window_settings([{:literal, size} | _rest]) when is_integer(size) and size > 0,
    do: %{size: size}

  defp window_settings(_arguments), do: %{}

  defp threshold_rules(thresholds) do
    [
      threshold_rule(thresholds, "red_low", :<, :critical),
      threshold_rule(thresholds, "yellow_low", :<, :warning),
      threshold_rule(thresholds, "yellow_high", :>, :warning),
      threshold_rule(thresholds, "red_high", :>, :critical)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp threshold_rule(thresholds, key, operator, severity) do
    case Map.get(thresholds, key, Map.get(thresholds, threshold_atom(key))) do
      nil -> nil
      value -> %{kind: :comparison, operator: operator, value: value, severity: severity}
    end
  end

  defp namespace_declarations(revision) do
    ["/cadence", "/cadence/derived_parameters", "/cadence/algorithms", "/cadence/monitoring"]
    |> Enum.reject(fn path ->
      Enum.any?(revision.declarations, fn {_id, declaration} ->
        declaration.kind == :space_system and declaration.qualified_name == path
      end)
    end)
    |> Enum.map(&Declaration.new(%{kind: :space_system, qualified_name: &1}))
  end

  defp declaration_lookup(declarations) do
    declarations
    |> Map.values()
    |> Enum.filter(&(&1.kind == :parameter))
    |> Enum.reduce(%{}, &put_lookup(&2, &1))
  end

  defp put_lookup(lookup, declaration) do
    keys =
      [declaration.semantic_id, declaration.qualified_name, declaration.name] ++
        declaration.aliases ++
        [
          value(declaration.definition, :point_id),
          value(declaration.definition, :legacy_point_id)
        ]

    keys
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.reduce(lookup, fn key, acc ->
      Map.update(acc, key, [declaration], &[declaration | &1])
    end)
  end

  defp lookup_parameter(lookup, key) do
    case lookup |> Map.get(key, []) |> Enum.uniq_by(& &1.semantic_id) do
      [parameter] ->
        {:ok, parameter}

      [] ->
        {:error, {:legacy_parameter_not_found, key}}

      parameters ->
        {:error, {:legacy_parameter_ambiguous, key, Enum.map(parameters, & &1.semantic_id)}}
    end
  end

  defp unique_inputs(inputs), do: Enum.uniq_by(inputs, & &1.semantic_id)

  defp legacy_provenance(family, definition_id) do
    %{
      importer_key: "cadence_legacy_semantics",
      importer_version: "1",
      source_path: [Atom.to_string(family), definition_id],
      transformations: [%{kind: "one_time_conversion"}]
    }
  end

  defp conversion_diagnostic(code, definition_id, reason) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :normalization,
      semantic_id: definition_id,
      support: :invalid,
      message: "legacy conversion failed: #{inspect(reason)}"
    })
  end

  defp binary_operator(:add), do: :+
  defp binary_operator(:subtract), do: :-
  defp binary_operator(:multiply), do: :*
  defp binary_operator(:divide), do: :/

  defp comparison_operator(:lt), do: :<
  defp comparison_operator(:lte), do: :<=
  defp comparison_operator(:gt), do: :>
  defp comparison_operator(:gte), do: :>=
  defp comparison_operator(:eq), do: :==
  defp comparison_operator(:neq), do: :!=

  defp threshold_atom("red_low"), do: :red_low
  defp threshold_atom("yellow_low"), do: :yellow_low
  defp threshold_atom("yellow_high"), do: :yellow_high
  defp threshold_atom("red_high"), do: :red_high

  defp metadata_integer(metadata, key, default) do
    case value(metadata, key, default) do
      integer when is_integer(integer) and integer > 0 -> integer
      _other -> default
    end
  end

  defp path_segment(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/[^A-Za-z0-9_.-]+/u, "_")
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
