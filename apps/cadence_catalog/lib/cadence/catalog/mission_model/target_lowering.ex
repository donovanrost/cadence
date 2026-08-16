defmodule Cadence.Catalog.MissionModel.TargetLowering do
  @moduledoc "Lowers resolved Mission Model declarations directly into runtime-plan documents."

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Diagnostic, Reference, Revision}

  @telemetry_runtime_contract "mission_model_telemetry_v1"
  @command_runtime_contract "mission_model_command_v1"

  @spec telemetry(Revision.t(), [Declaration.t()]) :: {map(), [Diagnostic.t()]}
  def telemetry(%Revision{} = revision, declarations) do
    index = Map.new(declarations, &{&1.semantic_id, &1})

    {packet_definitions, diagnostics} =
      declarations
      |> declarations_of(:container)
      |> Enum.reject(&value(&1.definition, :abstract, false))
      |> Enum.map_reduce([], fn declaration, diagnostics ->
        case lower_container(declaration, revision, index) do
          {:ok, document} -> {document, diagnostics}
          {:error, errors} -> {nil, diagnostics ++ errors}
        end
      end)

    {%{
       "target" => "telemetry",
       "runtime_contract" => @telemetry_runtime_contract,
       "packet_definitions" => Enum.reject(packet_definitions, &is_nil/1)
     }, diagnostics}
  end

  @spec command(Revision.t(), [Declaration.t()]) :: {map(), [Diagnostic.t()]}
  def command(%Revision{} = revision, declarations) do
    index = Map.new(declarations, &{&1.semantic_id, &1})

    {artifacts, diagnostics} =
      declarations
      |> declarations_of(:command)
      |> Enum.reject(&value(&1.definition, :abstract, false))
      |> Enum.map_reduce([], fn declaration, diagnostics ->
        case lower_command(declaration, revision, declarations, index) do
          {:ok, artifacts} -> {artifacts, diagnostics}
          {:error, errors} -> {nil, diagnostics ++ errors}
        end
      end)

    artifacts = Enum.reject(artifacts, &is_nil/1)

    {%{
       "target" => "command",
       "runtime_contract" => @command_runtime_contract,
       "runtime_definitions" => Enum.map(artifacts, & &1.runtime_definition),
       "constraint_plans" => Enum.flat_map(artifacts, & &1.constraint_plans),
       "verifier_plans" => Enum.flat_map(artifacts, & &1.verifier_plans),
       "operational_bindings" => Enum.map(artifacts, & &1.operational_binding)
     }, diagnostics}
  end

  defp lower_container(container, revision, index) do
    entries = value(container.definition, :entries, [])

    cond do
      not is_integer(value(container.definition, :apid)) ->
        {:error,
         [
           lowering_error(
             container,
             :telemetry,
             "MM_TELEMETRY_APID_REQUIRED",
             "concrete telemetry containers require an APID"
           )
         ]}

      not is_list(entries) ->
        {:error,
         [
           lowering_error(
             container,
             :telemetry,
             "MM_TELEMETRY_ENTRIES_INVALID",
             "telemetry container entries must be a list"
           )
         ]}

      true ->
        case lower_fields(container, entries, index) do
          {:ok, fields} ->
            {:ok,
             document(%{
               packet_definition_id: container.semantic_id,
               organization_id: revision.organization_id,
               mission_id: revision.mission_id,
               packet_name: container.name,
               apid: value(container.definition, :apid),
               version: value(container.definition, :version, 1),
               fields: Enum.sort_by(fields, &{&1.offset_bits, &1.field_id}),
               provenance: container.provenance
             })}

          {:error, diagnostics} ->
            {:error, diagnostics}
        end
    end
  end

  defp lower_fields(container, entries, index) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, position}, {:ok, fields} ->
      with {:ok, parameter} <- referenced_declaration(container, entry, position, :entry, index),
           {:ok, type} <- referenced_declaration(parameter, nil, 0, :type, index),
           {:ok, size_bits} <-
             positive_integer(
               value(entry, :size_bits) || get_in_value(type.definition, [:encoding, :size_bits])
             ),
           {:ok, data_type} <- telemetry_data_type(type),
           :ok <- supported_telemetry_encoding(type, size_bits) do
        field = %{
          field_id:
            value(
              entry,
              :entry_id,
              Canonical.content_id("mission_model_field", {container.semantic_id, position})
            ),
          parameter_id: parameter.semantic_id,
          qualified_name: parameter.qualified_name,
          name: parameter.name,
          offset_bits: value(entry, :bit_offset, 0),
          size_bits: size_bits,
          data_type: data_type,
          byte_order: telemetry_byte_order(type),
          engineering_unit: engineering_unit(parameter, index)
        }

        {:cont, {:ok, [field | fields]}}
      else
        {:error, reason} ->
          {:halt,
           {:error,
            [
              lowering_error(
                container,
                :telemetry,
                "MM_TELEMETRY_ENTRY_NOT_LOWERABLE",
                "telemetry entry #{position} cannot be lowered: #{inspect(reason)}"
              )
            ]}}
      end
    end)
    |> case do
      {:ok, fields} -> {:ok, Enum.reverse(fields)}
      error -> error
    end
  end

  defp lower_command(command, revision, declarations, index) do
    with {:ok, encoding} <- referenced_declaration(command, nil, 0, :encoding, index),
         {:ok, arguments} <- command_arguments(command, index),
         {:ok, argument_specs} <- lower_argument_specs(arguments, index),
         {:ok, encoding_steps} <- lower_encoding_steps(encoding, index) do
      operational = value(command.definition, :operational_metadata, %{})

      runtime_definition =
        document(%{
          command_id: command.semantic_id,
          mission_model_revision_id: revision.revision_id,
          name: command.name,
          display_name: value(command.definition, :display_name, command.name),
          description: value(command.definition, :description),
          layout_id: encoding.semantic_id,
          layout_kind: value(encoding.definition, :layout_kind, :space_packet),
          byte_order: value(encoding.definition, :byte_order, :big_endian),
          apid: value(encoding.definition, :apid),
          service_type: value(encoding.definition, :service_type),
          service_subtype: value(encoding.definition, :service_subtype),
          opcode: value(encoding.definition, :opcode),
          opcode_size_bits: value(encoding.definition, :opcode_size_bits),
          size_bits: value(encoding.definition, :size_bits),
          max_size_bits: value(encoding.definition, :max_size_bits),
          argument_specs: argument_specs,
          encoding_steps: encoding_steps,
          default_argument_values: value(command.definition, :default_argument_values, %{}),
          fixed_argument_values: value(command.definition, :fixed_argument_values, %{}),
          state_effects: lower_state_effects(command, index),
          metadata: %{"mission_model_revision_id" => revision.revision_id}
        })

      {:ok,
       %{
         runtime_definition: runtime_definition,
         constraint_plans: lower_constraints(command, declarations),
         verifier_plans: lower_verifiers(command, declarations),
         operational_binding:
           document(%{
             command_id: command.semantic_id,
             name: command.name,
             display_name: value(command.definition, :display_name, command.name),
             significance: value(operational, :significance),
             critical: value(operational, :critical, false),
             hazardous: value(operational, :hazardous, false),
             subsystem: value(operational, :subsystem),
             group_name: value(operational, :group_name),
             preferred_uplink_service: value(operational, :preferred_uplink_service),
             release_policy_hint: value(operational, :release_policy_hint),
             apid: value(encoding.definition, :apid),
             service_type: value(encoding.definition, :service_type),
             service_subtype: value(encoding.definition, :service_subtype),
             opcode: value(encoding.definition, :opcode),
             metadata: value(operational, :metadata, %{})
           })
       }}
    else
      {:error, reason} ->
        {:error,
         [
           lowering_error(
             command,
             :command,
             "MM_COMMAND_DEFINITION_NOT_LOWERABLE",
             "command cannot be lowered: #{inspect(reason)}"
           )
         ]}
    end
  end

  defp command_arguments(command, index) do
    command.references
    |> Enum.filter(&(&1.role == :argument))
    |> Enum.reduce_while({:ok, []}, fn reference, {:ok, arguments} ->
      case resolved(index, reference) do
        {:ok, declaration} -> {:cont, {:ok, arguments ++ [declaration]}}
        error -> {:halt, error}
      end
    end)
  end

  defp lower_argument_specs(arguments, index) do
    arguments
    |> Enum.reduce_while({:ok, []}, fn argument, {:ok, specs} ->
      with {:ok, type} <- referenced_declaration(argument, nil, 0, :type, index),
           {:ok, _size_bits} <-
             positive_integer(get_in_value(type.definition, [:encoding, :size_bits])) do
        spec = %{
          argument_id: argument.semantic_id,
          name: argument.name,
          description: value(argument.definition, :description),
          base_type: value(type.definition, :base_type),
          required: value(argument.definition, :required, true),
          encoding: value(type.definition, :encoding, %{}),
          default_value: value(argument.definition, :default_value),
          fixed_value: value(argument.definition, :fixed_value),
          hazardous_values: value(argument.definition, :hazardous_values, []),
          metadata: %{"display_unit" => value(type.definition, :display_unit)}
        }

        {:cont, {:ok, specs ++ [spec]}}
      else
        {:error, reason} ->
          {:halt, {:error, {:argument_not_lowerable, argument.semantic_id, reason}}}
      end
    end)
  end

  defp lower_encoding_steps(encoding, index) do
    encoding.definition
    |> value(:entries, [])
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, position}, {:ok, steps} ->
      kind = value(entry, :entry_kind, :argument_ref)

      case lower_encoding_step(kind, encoding, entry, position, index) do
        {:ok, step} -> {:cont, {:ok, steps ++ [step]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp lower_encoding_step(kind, encoding, entry, position, index)
       when kind in [:argument_ref, "argument_ref"] do
    with {:ok, argument} <- referenced_declaration(encoding, entry, position, :entry, index),
         {:ok, type} <- referenced_declaration(argument, nil, 0, :type, index),
         {:ok, size_bits} <-
           positive_integer(get_in_value(type.definition, [:encoding, :size_bits])),
         {:ok, bit_offset} <- non_negative_integer(value(entry, :bit_offset)) do
      {:ok,
       %{
         step_kind: :argument_ref,
         argument_id: argument.semantic_id,
         bit_offset: bit_offset,
         bit_offset_from: :layout_start,
         size_bits: size_bits,
         display_order: value(entry, :display_order, position),
         metadata: %{"argument_name" => argument.name}
       }}
    else
      {:error, reason} -> {:error, {:encoding_entry_not_lowerable, position, reason}}
    end
  end

  defp lower_encoding_step(kind, _encoding, entry, position, _index)
       when kind in [:fixed_value, "fixed_value"] do
    with {:ok, bit_offset} <- non_negative_integer(value(entry, :bit_offset)),
         {:ok, size_bits} <- positive_integer(value(entry, :fixed_value_size_bits)) do
      {:ok,
       %{
         step_kind: :fixed_value,
         bit_offset: bit_offset,
         bit_offset_from: :layout_start,
         size_bits: size_bits,
         fixed_value: value(entry, :fixed_value),
         display_order: value(entry, :display_order, position)
       }}
    else
      {:error, reason} -> {:error, {:fixed_encoding_not_lowerable, position, reason}}
    end
  end

  defp lower_encoding_step(kind, _encoding, _entry, position, _index),
    do: {:error, {:unsupported_encoding_entry, position, kind}}

  defp lower_state_effects(command, index) do
    command.definition
    |> value(:state_effects, [])
    |> Enum.with_index()
    |> Enum.map(fn {effect, position} ->
      target = resolve_source(command.references, value(effect, :target_ref), :effect, index)

      argument =
        resolve_source(command.references, value(effect, :argument_ref), :argument, index)

      %{
        effect_id:
          value(
            effect,
            :effect_id,
            Canonical.content_id("mission_model_effect", {command.semantic_id, position})
          ),
        target_ref: target,
        operation: value(effect, :operation, :set),
        argument_id: argument,
        value: value(effect, :value),
        metadata: value(effect, :metadata, %{})
      }
    end)
  end

  defp lower_constraints(command, declarations) do
    declarations
    |> owned_declarations(command, :command_constraint)
    |> Enum.map(fn declaration ->
      document(%{
        command_id: command.semantic_id,
        constraint_id: declaration.semantic_id,
        name: declaration.name,
        description: value(declaration.definition, :description),
        constraint_type: value(declaration.definition, :constraint_type, :precondition),
        criteria:
          resolve_criteria(value(declaration.definition, :criteria), declaration.references),
        timeout_ms: value(declaration.definition, :timeout_ms),
        blocking: value(declaration.definition, :blocking, true),
        metadata: value(declaration.definition, :metadata, %{})
      })
    end)
  end

  defp lower_verifiers(command, declarations) do
    declarations
    |> owned_declarations(command, :command_verifier)
    |> Enum.map(fn declaration ->
      document(%{
        command_id: command.semantic_id,
        verifier_id: declaration.semantic_id,
        name: declaration.name,
        description: value(declaration.definition, :description),
        phase: value(declaration.definition, :phase, :completion),
        success_criteria:
          resolve_criteria(
            value(declaration.definition, :success_criteria),
            declaration.references
          ),
        failure_criteria:
          resolve_criteria(
            value(declaration.definition, :failure_criteria),
            declaration.references
          ),
        timeout_ms: value(declaration.definition, :timeout_ms),
        delay_ms: value(declaration.definition, :delay_ms),
        severity: value(declaration.definition, :severity),
        metadata: value(declaration.definition, :metadata, %{})
      })
    end)
  end

  defp owned_declarations(declarations, command, kind) do
    prefix =
      command.qualified_name <>
        "/" <> if(kind == :command_constraint, do: "constraints/", else: "verifiers/")

    Enum.filter(declarations, fn declaration ->
      declaration.kind == kind and String.starts_with?(declaration.qualified_name, prefix)
    end)
  end

  defp resolve_criteria(nil, _references), do: nil

  defp resolve_criteria(criteria, references) when is_map(criteria) do
    criteria
    |> Map.new(fn {key, value} ->
      resolved =
        cond do
          key in [:subject_ref, "subject_ref", :parameter_ref, "parameter_ref"] ->
            resolve_source(references, value, [:criteria, :condition], nil)

          is_map(value) ->
            resolve_criteria(value, references)

          is_list(value) ->
            Enum.map(value, &resolve_criteria_item(&1, references))

          true ->
            value
        end

      {if(key in [:parameter_ref, "parameter_ref"], do: "subject_ref", else: key), resolved}
    end)
    |> normalize_criteria_document()
  end

  defp resolve_criteria_item(value, references) when is_map(value),
    do: resolve_criteria(value, references)

  defp resolve_criteria_item(value, _references), do: value

  defp normalize_criteria_document(%{"comparisons" => [comparison]}),
    do: normalize_comparison(comparison)

  defp normalize_criteria_document(%{comparisons: [comparison]}),
    do: normalize_comparison(comparison)

  defp normalize_criteria_document(criteria), do: criteria

  defp normalize_comparison(comparison) do
    %{
      "criteria_type" => "comparison",
      "subject_ref" => value(comparison, :subject_ref),
      "comparison" => comparison_operator(value(comparison, :operator)),
      "value" => value(comparison, :value),
      "use_calibrated" => true,
      "conditions" => []
    }
  end

  defp comparison_operator(operator) when operator in ["==", "equal", :equal], do: "equal"

  defp comparison_operator(operator) when operator in ["!=", "not_equal", :not_equal],
    do: "not_equal"

  defp comparison_operator(operator) when operator in [">", "greater", :greater], do: "greater"
  defp comparison_operator(operator) when operator in ["<", "less", :less], do: "less"

  defp comparison_operator(operator) when operator in [">=", "greater_equal", :greater_equal],
    do: "greater_equal"

  defp comparison_operator(operator) when operator in ["<=", "less_equal", :less_equal],
    do: "less_equal"

  defp comparison_operator(operator), do: operator

  defp referenced_declaration(owner, entry, position, role, index) do
    source_ref = entry && (value(entry, :parameter_ref) || value(entry, :argument_ref))

    references = Enum.filter(owner.references, &(&1.role == role))

    reference =
      Enum.find(references, fn reference ->
        is_binary(source_ref) and reference.source_ref == source_ref
      end) || Enum.at(references, position)

    resolved(index, reference)
  end

  defp resolved(_index, nil), do: {:error, :reference_missing}

  defp resolved(index, %Reference{resolved_id: resolved_id}) when is_binary(resolved_id) do
    case Map.fetch(index, resolved_id) do
      {:ok, declaration} -> {:ok, declaration}
      :error -> {:error, {:resolved_declaration_missing, resolved_id}}
    end
  end

  defp resolved(_index, %Reference{} = reference),
    do: {:error, {:reference_unresolved, reference.source_ref}}

  defp resolve_source(%Declaration{} = owner, source_ref, role, index),
    do: resolve_source(owner.references, source_ref, role, index)

  defp resolve_source(references, source_ref, roles, _index) do
    roles = List.wrap(roles)

    Enum.find_value(references, source_ref, fn reference ->
      if reference.role in roles and reference.source_ref == source_ref and
           is_binary(reference.resolved_id),
         do: reference.resolved_id
    end)
  end

  defp engineering_unit(parameter, index) do
    with %Reference{} = reference <- Enum.find(parameter.references, &(&1.role == :unit)),
         {:ok, unit} <- resolved(index, reference) do
      value(unit.definition, :symbol, unit.name)
    else
      _other -> nil
    end
  end

  defp telemetry_data_type(type) do
    encoding = value(type.definition, :encoding, %{})

    case value(type.definition, :base_type) do
      kind when kind in [:integer, :enumerated, "integer", "enumerated"] ->
        if value(encoding, :signed, false) or
             value(encoding, :integer_encoding) in [:twos_complement, "twos_complement"],
           do: {:ok, :int},
           else: {:ok, :uint}

      kind when kind in [:float, "float"] ->
        {:ok, :float}

      kind when kind in [:boolean, "boolean"] ->
        {:ok, :bool}

      kind when kind in [:binary, "binary"] ->
        {:ok, :binary}

      kind when kind in [:string, "string"] ->
        {:ok, :string}

      kind ->
        {:error, {:unsupported_parameter_type, kind}}
    end
  end

  defp supported_telemetry_encoding(type, size_bits) do
    case value(type.definition, :base_type) do
      kind when kind in [:float, "float"] and size_bits not in [32, 64] ->
        {:error, {:unsupported_float_size, size_bits}}

      kind when kind in [:boolean, "boolean"] and size_bits != 1 ->
        {:error, {:unsupported_boolean_size, size_bits}}

      _other ->
        :ok
    end
  end

  defp telemetry_byte_order(type) do
    type.definition
    |> value(:encoding, %{})
    |> value(:byte_order, :big_endian)
    |> case do
      order when order in [:little_endian, "little_endian", "leastSignificantByteFirst"] ->
        :little_endian

      _other ->
        :big_endian
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(value), do: {:error, {:positive_integer_required, value}}

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp non_negative_integer(value), do: {:error, {:non_negative_integer_required, value}}

  defp lowering_error(declaration, target, code, message) do
    Diagnostic.new(%{
      code: code,
      severity: :error,
      stage: :target_lowering,
      target: target,
      semantic_id: declaration.semantic_id,
      support: :invalid,
      message: message,
      provenance: declaration.provenance
    })
  end

  defp declarations_of(declarations, kind), do: Enum.filter(declarations, &(&1.kind == kind))

  defp get_in_value(map, [key | rest]) do
    case value(map, key) do
      nil -> nil
      nested when rest == [] -> nested
      nested when is_map(nested) -> get_in_value(nested, rest)
      _other -> nil
    end
  end

  defp document(%_{} = struct), do: struct |> Map.from_struct() |> document()

  defp document(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), document(value)} end)

  defp document(list) when is_list(list), do: Enum.map(list, &document/1)
  defp document(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&document/1)
  defp document(value), do: value

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
