defmodule Cadence.Catalog.Command.Compiler do
  @moduledoc """
  Compiles canonical command catalog snapshots into narrower runtime-facing
  command artifacts.

  This compiler intentionally targets the initial command runtime slice Cadence
  is expected to grow into:

  - compiled command definitions for validation and encoding
  - compiled transmission-constraint plans
  - compiled verifier plans
  - compiled operational bindings for approval/release/uplink workflows

  It does not attempt to preserve every canonical command feature in this first
  runtime boundary. Unsupported features produce diagnostics rather than
  silently disappearing.
  """

  alias Cadence.Catalog.Diagnostic

  alias Cadence.Catalog.Command.Compiler.{
    ArgumentSpec,
    ConstraintPlan,
    EncodingStep,
    OperationalBinding,
    Result,
    RuntimeDefinition,
    VerifierPlan
  }

  alias Cadence.Catalog.Command.{
    Argument,
    ArgumentType,
    Definition,
    EncodingEntry,
    EncodingLayout,
    OperationalMetadata,
    Snapshot,
    TransmissionConstraint,
    Verifier
  }

  @type compile_opt :: {:compiler_version, pos_integer()}

  @spec compile(Snapshot.t(), [compile_opt()]) :: Result.t()
  def compile(%Snapshot{} = snapshot, opts \\ []) when is_list(opts) do
    context = build_context(snapshot, opts)

    {runtime_definitions, constraint_plans, verifier_plans, operational_bindings, diagnostics} =
      Enum.reduce(
        snapshot.command_definitions,
        {[], [], [], [], []},
        fn %Definition{} = definition, acc ->
          compile_definition(definition, context, acc)
        end
      )

    Result.new(%{
      runtime_definitions: Enum.reverse(runtime_definitions),
      constraint_plans: Enum.reverse(constraint_plans),
      verifier_plans: Enum.reverse(verifier_plans),
      operational_bindings: Enum.reverse(operational_bindings),
      diagnostics: Enum.reverse(diagnostics)
    })
  end

  defp compile_definition(
         %Definition{} = definition,
         context,
         {runtime_defs, constraint_plans, verifier_plans, bindings, diagnostics}
       ) do
    definition_diagnostics = definition_runtime_diagnostics(definition)

    if definition.abstract do
      {runtime_defs, constraint_plans, verifier_plans, bindings,
       Enum.reverse(definition_diagnostics, diagnostics)}
    else
      case compile_runtime_definition(definition, context) do
        {:ok, %RuntimeDefinition{} = runtime_definition, compile_diagnostics} ->
          operational_binding = compile_operational_binding(definition, runtime_definition)
          compiled_constraint_plans = compile_constraint_plans(definition)
          compiled_verifier_plans = compile_verifier_plans(definition)

          {[
             runtime_definition | runtime_defs
           ], Enum.reverse(compiled_constraint_plans, constraint_plans),
           Enum.reverse(compiled_verifier_plans, verifier_plans),
           [operational_binding | bindings],
           Enum.reverse(compile_diagnostics, Enum.reverse(definition_diagnostics, diagnostics))}

        {:skip, compile_diagnostics} ->
          {runtime_defs, constraint_plans, verifier_plans, bindings,
           Enum.reverse(compile_diagnostics, Enum.reverse(definition_diagnostics, diagnostics))}
      end
    end
  end

  defp compile_runtime_definition(%Definition{} = definition, context) do
    with {:ok, %EncodingLayout{} = layout} <- fetch_layout(definition, context),
         {:ok, argument_specs_by_id} <- compile_argument_specs(definition, context, layout),
         {:ok, encoding_steps} <- compile_encoding_steps(definition, layout, argument_specs_by_id) do
      runtime_definition =
        RuntimeDefinition.new(%{
          command_id: definition.command_id,
          snapshot_id: definition.snapshot_id,
          name: definition.name,
          display_name: definition.display_name,
          description: definition.description,
          layout_id: layout.layout_id,
          layout_kind: layout.layout_kind,
          byte_order: layout.byte_order,
          apid: layout.apid,
          service_type: layout.service_type,
          service_subtype: layout.service_subtype,
          opcode: layout.opcode,
          opcode_size_bits: layout.opcode_size_bits,
          size_bits: layout.size_bits,
          max_size_bits: layout.max_size_bits,
          argument_specs:
            definition.argument_ids
            |> Enum.map(&Map.fetch!(argument_specs_by_id, &1)),
          encoding_steps: encoding_steps,
          default_argument_values: definition.default_argument_values,
          fixed_argument_values: definition.fixed_argument_values,
          metadata: %{"compiler_version" => context.compiler_version}
        })

      {:ok, runtime_definition, []}
    else
      {:error, compile_diagnostics} when is_list(compile_diagnostics) ->
        {:skip, compile_diagnostics}
    end
  end

  defp fetch_layout(%Definition{} = definition, context) do
    case Map.fetch(context.layout_by_id, definition.encoding_layout_id) do
      {:ok, %EncodingLayout{} = layout} ->
        {:ok, layout}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.encoding_layout_not_found",
             "Command definition references an encoding layout that is not present in the snapshot",
             definition,
             definition,
             %{"layout_id" => definition.encoding_layout_id}
           )
         ]}
    end
  end

  defp compile_argument_specs(%Definition{} = definition, context, %EncodingLayout{} = layout) do
    referenced_argument_ids =
      layout.entries
      |> Enum.flat_map(fn
        %EncodingEntry{entry_kind: :argument_ref, argument_id: argument_id}
        when is_binary(argument_id) ->
          [argument_id]

        _entry ->
          []
      end)
      |> Enum.uniq()

    referenced_argument_ids
    |> Enum.reduce_while({:ok, %{}}, fn argument_id, {:ok, acc} ->
      with {:ok, %Argument{} = argument} <- fetch_argument(definition, argument_id, context),
           {:ok, %ArgumentType{} = argument_type} <-
             fetch_argument_type(definition, argument, context),
           {:ok, %ArgumentSpec{} = argument_spec} <-
             compile_argument_spec(definition, argument, argument_type) do
        {:cont, {:ok, Map.put(acc, argument_id, argument_spec)}}
      else
        {:error, compile_diagnostics} ->
          {:halt, {:error, compile_diagnostics}}
      end
    end)
  end

  defp fetch_argument(%Definition{} = definition, argument_id, context) do
    case Map.fetch(context.argument_by_id, argument_id) do
      {:ok, %Argument{} = argument} ->
        {:ok, argument}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.argument_not_found",
             "Command definition or layout references an argument that is not present in the snapshot",
             definition,
             definition,
             %{"argument_id" => argument_id}
           )
         ]}
    end
  end

  defp fetch_argument_type(%Definition{} = definition, %Argument{} = argument, context) do
    case Map.fetch(context.argument_type_by_id, argument.argument_type_id) do
      {:ok, %ArgumentType{} = argument_type} ->
        {:ok, argument_type}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.argument_type_not_found",
             "Command argument references an argument type that is not present in the snapshot",
             definition,
             argument,
             %{
               "argument_id" => argument.argument_id,
               "argument_type_id" => argument.argument_type_id
             }
           )
         ]}
    end
  end

  defp compile_argument_spec(
         %Definition{} = definition,
         %Argument{} = argument,
         %ArgumentType{} = argument_type
       ) do
    with :ok <- validate_argument_type(definition, argument, argument_type) do
      {:ok,
       ArgumentSpec.new(%{
         argument_id: argument.argument_id,
         name: argument.name,
         description: argument.description,
         base_type: argument_type.base_type,
         required: argument.required,
         encoding: argument_type.encoding,
         default_value: argument.default_value,
         fixed_value: argument.fixed_value,
         hazardous_values: argument.hazardous_values,
         metadata: %{"display_unit" => argument_type.display_unit}
       })}
    else
      {:error, compile_diagnostics} ->
        {:error, compile_diagnostics}
    end
  end

  defp validate_argument_type(
         %Definition{} = definition,
         %Argument{} = argument,
         %ArgumentType{} = argument_type
       ) do
    cond do
      is_nil(argument_type.encoding) ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.argument_encoding_missing",
             "Command argument type is missing fixed encoding information required by the current runtime compiler",
             definition,
             argument,
             %{
               "argument_id" => argument.argument_id,
               "argument_type_id" => argument.argument_type_id
             }
           )
         ]}

      not supported_argument_base_type?(argument_type.base_type) ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.argument_type_unsupported",
             "Command argument type is not supported by the current runtime command compiler",
             definition,
             argument,
             %{
               "argument_id" => argument.argument_id,
               "argument_type_id" => argument.argument_type_id,
               "base_type" => Atom.to_string(argument_type.base_type)
             }
           )
         ]}

      not fixed_size_encoding?(argument_type.encoding) ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.fixed_size_encoding_required",
             "Current runtime command compilation requires fixed-size argument encodings",
             definition,
             argument,
             %{
               "argument_id" => argument.argument_id,
               "argument_type_id" => argument.argument_type_id
             }
           )
         ]}

      true ->
        :ok
    end
  end

  defp compile_encoding_steps(
         %Definition{} = definition,
         %EncodingLayout{} = layout,
         argument_specs_by_id
       ) do
    layout.entries
    |> Enum.reduce_while({:ok, []}, fn %EncodingEntry{} = entry, {:ok, acc} ->
      case compile_encoding_step(definition, layout, entry, argument_specs_by_id) do
        {:ok, %EncodingStep{} = encoding_step} ->
          {:cont, {:ok, acc ++ [encoding_step]}}

        {:error, compile_diagnostics} ->
          {:halt, {:error, compile_diagnostics}}
      end
    end)
  end

  defp compile_encoding_step(
         %Definition{} = definition,
         %EncodingLayout{} = layout,
         %EncodingEntry{} = entry,
         argument_specs_by_id
       ) do
    cond do
      not is_integer(entry.bit_offset) ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.absolute_bit_offset_required",
             "Command encoding entries must have an absolute bit offset for the current runtime compiler",
             definition,
             entry
           )
         ]}

      entry.bit_offset_from != :layout_start ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.relative_offsets_unsupported",
             "Relative command encoding entry offsets are not supported by the current runtime compiler",
             definition,
             entry
           )
         ]}

      entry.include_condition != nil ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.conditional_entries_unsupported",
             "Conditional command encoding entries are not supported by the current runtime compiler",
             definition,
             entry
           )
         ]}

      entry.entry_kind == :nested_layout_ref ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.nested_layout_unsupported",
             "Nested command encoding layouts are not supported by the current runtime compiler",
             definition,
             entry
           )
         ]}

      entry.entry_kind == :argument_ref ->
        compile_argument_step(definition, layout, entry, argument_specs_by_id)

      entry.entry_kind == :fixed_value ->
        compile_fixed_value_step(definition, entry)

      true ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.entry_kind_unsupported",
             "Command encoding entry kind is not supported by the current runtime compiler",
             definition,
             entry,
             %{"entry_kind" => Atom.to_string(entry.entry_kind)}
           )
         ]}
    end
  end

  defp compile_argument_step(
         %Definition{} = definition,
         %EncodingLayout{} = _layout,
         %EncodingEntry{} = entry,
         argument_specs_by_id
       ) do
    case Map.fetch(argument_specs_by_id, entry.argument_id) do
      {:ok, %ArgumentSpec{} = argument_spec} ->
        {:ok,
         EncodingStep.new(%{
           step_kind: :argument_ref,
           argument_id: argument_spec.argument_id,
           bit_offset: entry.bit_offset,
           size_bits: argument_spec.encoding.size_bits,
           display_order: entry.display_order,
           metadata: %{"argument_name" => argument_spec.name}
         })}

      :error ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.argument_spec_missing",
             "Command encoding entry references an argument that did not compile into a runtime argument specification",
             definition,
             entry,
             %{"argument_id" => entry.argument_id}
           )
         ]}
    end
  end

  defp compile_fixed_value_step(%Definition{} = definition, %EncodingEntry{} = entry) do
    case entry.fixed_value_size_bits do
      size_bits when is_integer(size_bits) and size_bits > 0 ->
        {:ok,
         EncodingStep.new(%{
           step_kind: :fixed_value,
           bit_offset: entry.bit_offset,
           size_bits: size_bits,
           fixed_value: entry.fixed_value,
           display_order: entry.display_order
         })}

      _other ->
        {:error,
         [
           diagnostic(
             :error,
             "command_compiler.fixed_value_size_missing",
             "Fixed-value command encoding entries require an explicit encoded size in the current runtime compiler",
             definition,
             entry
           )
         ]}
    end
  end

  defp compile_constraint_plans(%Definition{} = definition) do
    Enum.map(definition.transmission_constraints, fn %TransmissionConstraint{} = constraint ->
      ConstraintPlan.new(%{
        command_id: definition.command_id,
        constraint_id: constraint.constraint_id,
        name: constraint.name,
        description: constraint.description,
        constraint_type: constraint.constraint_type,
        criteria: constraint.criteria,
        timeout_ms: constraint.timeout_ms,
        blocking: constraint.blocking,
        metadata: constraint.metadata
      })
    end)
  end

  defp compile_verifier_plans(%Definition{} = definition) do
    Enum.map(definition.verifiers, fn %Verifier{} = verifier ->
      VerifierPlan.new(%{
        command_id: definition.command_id,
        verifier_id: verifier.verifier_id,
        name: verifier.name,
        description: verifier.description,
        phase: verifier.phase,
        success_criteria: verifier.success_criteria,
        failure_criteria: verifier.failure_criteria,
        timeout_ms: verifier.timeout_ms,
        delay_ms: verifier.delay_ms,
        severity: verifier.severity,
        metadata: verifier.metadata
      })
    end)
  end

  defp compile_operational_binding(
         %Definition{} = definition,
         %RuntimeDefinition{} = runtime_definition
       ) do
    operational_metadata = definition.operational_metadata || %OperationalMetadata{}

    OperationalBinding.new(%{
      command_id: definition.command_id,
      name: definition.name,
      display_name: definition.display_name,
      significance: operational_metadata.significance,
      critical: operational_metadata.critical,
      hazardous: operational_metadata.hazardous,
      subsystem: operational_metadata.subsystem,
      group_name: operational_metadata.group_name,
      preferred_uplink_service: operational_metadata.preferred_uplink_service,
      release_policy_hint: operational_metadata.release_policy_hint,
      apid: runtime_definition.apid,
      service_type: runtime_definition.service_type,
      service_subtype: runtime_definition.service_subtype,
      opcode: runtime_definition.opcode,
      metadata: operational_metadata.metadata
    })
  end

  defp supported_argument_base_type?(base_type)
       when base_type in [:integer, :float, :string, :binary, :boolean, :enumerated],
       do: true

  defp supported_argument_base_type?(_base_type), do: false

  defp fixed_size_encoding?(%{size_bits: size_bits, dynamic_size_ref: nil})
       when is_integer(size_bits) and size_bits > 0,
       do: true

  defp fixed_size_encoding?(_encoding), do: false

  defp definition_runtime_diagnostics(%Definition{} = definition) do
    []
    |> maybe_add_abstract_definition_diagnostic(definition)
    |> maybe_add_missing_layout_diagnostic(definition)
  end

  defp maybe_add_abstract_definition_diagnostic(
         diagnostics,
         %Definition{abstract: true} = definition
       ) do
    [
      diagnostic(
        :warning,
        "command_compiler.abstract_command_skipped",
        "Abstract command definitions are not compiled into current runtime command definitions",
        definition,
        definition
      )
      | diagnostics
    ]
  end

  defp maybe_add_abstract_definition_diagnostic(diagnostics, %Definition{}), do: diagnostics

  defp maybe_add_missing_layout_diagnostic(
         diagnostics,
         %Definition{encoding_layout_id: layout_id} = definition
       )
       when not is_binary(layout_id) or layout_id == "" do
    [
      diagnostic(
        :error,
        "command_compiler.encoding_layout_required",
        "Current runtime command compilation requires each concrete command definition to reference an encoding layout",
        definition,
        definition
      )
      | diagnostics
    ]
  end

  defp maybe_add_missing_layout_diagnostic(diagnostics, %Definition{}), do: diagnostics

  defp build_context(%Snapshot{} = snapshot, opts) do
    %{
      snapshot: snapshot,
      compiler_version: Keyword.get(opts, :compiler_version, 1),
      layout_by_id: Map.new(snapshot.encoding_layouts, &{&1.layout_id, &1}),
      argument_by_id: Map.new(snapshot.arguments, &{&1.argument_id, &1}),
      argument_type_by_id: Map.new(snapshot.argument_types, &{&1.argument_type_id, &1})
    }
  end

  defp diagnostic(severity, code, message, %Definition{} = definition, source, metadata \\ %{}) do
    {source_id, source_kind, path} =
      case source do
        %Definition{command_id: command_id} ->
          {command_id, "command_definition", ["command_definitions", definition.command_id]}

        %EncodingLayout{layout_id: layout_id} ->
          {layout_id, "encoding_layout",
           ["command_definitions", definition.command_id, "encoding_layouts", layout_id]}

        %EncodingEntry{layout_entry_id: layout_entry_id} ->
          {layout_entry_id, "encoding_entry",
           ["command_definitions", definition.command_id, "encoding_entries", layout_entry_id]}

        %Argument{argument_id: argument_id} ->
          {argument_id, "argument",
           ["command_definitions", definition.command_id, "arguments", argument_id]}

        %ArgumentType{argument_type_id: argument_type_id} ->
          {argument_type_id, "argument_type",
           ["command_definitions", definition.command_id, "argument_types", argument_type_id]}
      end

    Diagnostic.new(%{
      severity: severity,
      code: code,
      message: message,
      path: path,
      metadata:
        Map.merge(
          %{
            "command_id" => definition.command_id,
            "source_kind" => source_kind,
            "source_id" => source_id
          },
          metadata
        )
    })
  end
end
