# XTCE's tree shape necessarily nests optional metadata sections while translating them.
# credo:disable-for-this-file Credo.Check.Refactor.Nesting
defmodule Cadence.Catalog.Importers.Xtce13.Translator do
  @moduledoc "Translates the XTCE 1.3 source tree into a canonical declaration layer."

  alias Cadence.Catalog.Diagnostic

  alias Cadence.Catalog.Importers.Xtce13.Element
  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Layer, Path, Reference}
  alias Cadence.Catalog.Source

  @command_verifier_names [
    "TransferredToRangeVerifier",
    "SentFromRangeVerifier",
    "ReceivedVerifier",
    "AcceptedVerifier",
    "QueuedVerifier",
    "ExecutionVerifier",
    "CompleteVerifier",
    "FailedVerifier"
  ]

  @type state :: %{
          declarations: [Declaration.t()],
          diagnostics: [Diagnostic.t()],
          alarm_rules: %{binary() => map()},
          units: MapSet.t(binary()),
          source: Source.t(),
          import_run_id: binary()
        }

  @spec translate(Element.t(), Source.t(), binary()) ::
          {:ok, Layer.t(), [Diagnostic.t()]} | {:error, term()}
  def translate(%Element{name: "SpaceSystem"} = root, %Source{} = source, import_run_id) do
    root_name = Element.attr(root, "name")

    if is_binary(root_name) and root_name != "" do
      state = %{
        declarations: [declaration(:space_system, "/", %{}, root, source, import_run_id)],
        diagnostics: [],
        alarm_rules: %{},
        units: MapSet.new(),
        source: source,
        import_run_id: import_run_id
      }

      final_state = translate_system(root, Path.join("/", root_name), state)
      source_diagnostics = Enum.reverse(final_state.diagnostics)

      layer =
        Layer.new(%{
          organization_id: source.organization_id,
          mission_id: source.mission_id,
          name: source.artifact_name <> " XTCE 1.3",
          source: %{
            artifact_id: source.artifact_id,
            import_run_id: import_run_id,
            importer_key: "xtce_1_3",
            namespace: root.namespace,
            format_version: source.format_version
          },
          declarations: Enum.reverse(final_state.declarations),
          metadata: %{
            "source_format" => source.format_key,
            "xtce_namespace" => root.namespace,
            "source_diagnostics" => Enum.map(source_diagnostics, &Map.from_struct/1)
          }
        })

      {:ok, layer, source_diagnostics}
    else
      {:error, :xtce_space_system_name_required}
    end
  end

  def translate(%Element{}, %Source{}, _import_run_id),
    do: {:error, :xtce_space_system_root_required}

  defp translate_system(element, system_path, state) do
    state = put_declaration(state, declaration(:space_system, system_path, %{}, element, state))
    state = translate_parameter_types(element, system_path, state)
    state = translate_parameters(element, system_path, state)
    state = translate_containers(element, system_path, state)
    state = translate_algorithms(element, system_path, state)
    state = translate_command_argument_types(element, system_path, state)
    state = translate_commands(element, system_path, state)
    state = preserve_unsupported_executable_sections(element, system_path, state)

    Enum.reduce(child_systems(element), state, fn child, acc ->
      case Element.attr(child, "name") do
        name when is_binary(name) and name != "" ->
          translate_system(child, Path.join(system_path, name), acc)

        _other ->
          put_diagnostic(
            acc,
            diagnostic(
              :error,
              "XTCE_SPACE_SYSTEM_NAME_REQUIRED",
              "nested SpaceSystem is missing its name",
              child
            )
          )
      end
    end)
  end

  defp translate_parameter_types(system, system_path, state) do
    system
    |> section_children("TelemetryMetaData", "ParameterTypeSet")
    |> Enum.filter(&String.ends_with?(&1.name, "ParameterType"))
    |> Enum.reduce(state, fn element, acc ->
      name = Element.attr(element, "name")

      if non_empty?(name) do
        qualified_name = declaration_path(system_path, "types", name)
        alarm = alarm_definition(element)
        {acc, unit_refs} = put_units(acc, system_path, element)

        definition = %{
          base_type: parameter_base_type(element.name),
          encoding: type_encoding(element),
          alarm_rules: alarm.rules,
          xtce_type: element.name
        }

        references =
          Enum.map(unit_refs, fn unit_path ->
            Reference.new(%{expected_kind: :unit, source_ref: unit_path, role: :unit})
          end)

        acc
        |> put_declaration(
          declaration(:parameter_type, qualified_name, definition, element, acc,
            references: references
          )
        )
        |> put_alarm_rules(qualified_name, alarm)
      else
        put_diagnostic(
          acc,
          diagnostic(
            :error,
            "XTCE_PARAMETER_TYPE_NAME_REQUIRED",
            "parameter type has no name",
            element
          )
        )
      end
    end)
  end

  defp translate_parameters(system, system_path, state) do
    system
    |> section_children("TelemetryMetaData", "ParameterSet")
    |> Enum.filter(&(&1.name in ["Parameter", "ParameterRef"]))
    |> Enum.reduce(state, fn element, acc ->
      name = Element.attr(element, "name")
      type_ref = Element.attr(element, "parameterTypeRef")

      if non_empty?(name) and non_empty?(type_ref) do
        qualified_name = declaration_path(system_path, "parameters", name)
        type_path = reference_path(system_path, "types", type_ref)

        parameter =
          declaration(:parameter, qualified_name, parameter_definition(element), element, acc,
            references: [
              Reference.new(%{
                expected_kind: :parameter_type,
                source_ref: type_path,
                role: :type
              })
            ]
          )

        acc = put_declaration(acc, parameter)

        case Map.get(acc.alarm_rules, type_path, %{rules: []}) do
          %{rules: []} -> acc
          alarm -> put_declaration(acc, monitoring_policy(qualified_name, alarm, element, acc))
        end
      else
        put_diagnostic(
          acc,
          diagnostic(
            :error,
            "XTCE_PARAMETER_INVALID",
            "parameter requires name and parameterTypeRef",
            element
          )
        )
      end
    end)
  end

  defp translate_containers(system, system_path, state) do
    system
    |> section_children("TelemetryMetaData", "ContainerSet")
    |> Enum.filter(&(&1.name == "SequenceContainer"))
    |> Enum.reduce(state, fn element, acc ->
      name = Element.attr(element, "name")

      if non_empty?(name) do
        qualified_name = declaration_path(system_path, "containers", name)
        entries = container_entries(element, system_path)

        references =
          Enum.map(entries, fn entry ->
            Reference.new(%{
              expected_kind: :parameter,
              source_ref: entry.parameter_ref,
              role: :entry
            })
          end) ++ base_container_reference(element, system_path)

        definition = %{
          abstract: boolean_attr(element, "abstract", false),
          entries: entries,
          restriction_criteria: restriction_criteria(element, system_path)
        }

        put_declaration(
          acc,
          declaration(:container, qualified_name, definition, element, acc,
            references: references
          )
        )
      else
        put_diagnostic(
          acc,
          diagnostic(:error, "XTCE_CONTAINER_NAME_REQUIRED", "container has no name", element)
        )
      end
    end)
  end

  defp translate_algorithms(system, system_path, state) do
    system
    |> section_children("TelemetryMetaData", "AlgorithmSet")
    |> Enum.filter(&String.ends_with?(&1.name, "Algorithm"))
    |> Enum.reduce(state, fn element, acc ->
      name = Element.attr(element, "name")

      if non_empty?(name) do
        qualified_name = declaration_path(system_path, "algorithms", name)

        inputs =
          element
          |> Element.descendants(fn child ->
            child.name in ["InputParameterInstanceRef", "InputParameterRef"]
          end)
          |> Enum.map(&Element.attr(&1, "parameterRef"))
          |> Enum.filter(&non_empty?/1)

        outputs =
          element
          |> Element.descendants(fn child ->
            child.name in ["OutputParameterRef", "OutputParameterInstanceRef"]
          end)
          |> Enum.map(&Element.attr(&1, "parameterRef"))
          |> Enum.filter(&non_empty?/1)

        references =
          Enum.map(inputs, fn parameter_ref ->
            Reference.new(%{
              expected_kind: :parameter,
              source_ref: reference_path(system_path, "parameters", parameter_ref),
              role: :input
            })
          end) ++
            Enum.map(outputs, fn parameter_ref ->
              Reference.new(%{
                expected_kind: :parameter,
                source_ref: reference_path(system_path, "parameters", parameter_ref),
                role: :output
              })
            end)

        output_definitions =
          Enum.map(outputs, fn parameter_ref ->
            parameter_path = reference_path(system_path, "parameters", parameter_ref)

            %{
              parameter_id: Canonical.semantic_id(:parameter, parameter_path),
              qualified_name: parameter_path,
              expression: %{node: {:literal, nil}, result_type: :any}
            }
          end)

        definition = %{
          implementation: %{
            kind: :registered,
            key: "xtce.algorithm." <> String.trim_leading(qualified_name, "/"),
            version: "1"
          },
          outputs: output_definitions,
          xtce_algorithm_type: element.name,
          source_text: algorithm_text(element)
        }

        acc
        |> put_declaration(
          declaration(:algorithm, qualified_name, definition, element, acc,
            references: references
          )
        )
        |> put_diagnostic(
          diagnostic(
            :warning,
            "XTCE_ALGORITHM_REQUIRES_REGISTERED_IMPLEMENTATION",
            "XTCE algorithm #{qualified_name} is preserved and requires an allowlisted implementation",
            element
          )
        )
      else
        put_diagnostic(
          acc,
          diagnostic(:error, "XTCE_ALGORITHM_NAME_REQUIRED", "algorithm has no name", element)
        )
      end
    end)
  end

  defp translate_commands(system, system_path, state) do
    system
    |> section_children("CommandMetaData", "MetaCommandSet")
    |> Enum.filter(&(&1.name == "MetaCommand"))
    |> Enum.reduce(state, fn element, acc -> translate_command(element, system_path, acc) end)
  end

  defp translate_command_argument_types(system, system_path, state) do
    system
    |> section_children("CommandMetaData", "ArgumentTypeSet")
    |> Enum.filter(&String.ends_with?(&1.name, "ArgumentType"))
    |> Enum.reduce(state, fn element, acc ->
      name = Element.attr(element, "name")

      if non_empty?(name) do
        qualified_name = declaration_path(system_path, "command_types", name)

        definition = %{
          base_type: argument_base_type(element.name),
          encoding: type_encoding(element),
          valid_range: valid_range(element),
          xtce_type: element.name
        }

        put_declaration(
          acc,
          declaration(:command_argument_type, qualified_name, definition, element, acc)
        )
      else
        put_diagnostic(
          acc,
          diagnostic(
            :error,
            "XTCE_ARGUMENT_TYPE_NAME_REQUIRED",
            "command argument type has no name",
            element
          )
        )
      end
    end)
  end

  defp translate_command(element, system_path, state) do
    name = Element.attr(element, "name")

    if non_empty?(name) do
      command_path = declaration_path(system_path, "commands", name)

      {state, argument_refs} =
        translate_command_arguments(element, system_path, command_path, state)

      base_refs =
        case Element.child(element, "BaseMetaCommand") do
          %Element{} = base ->
            case Element.attr(base, "metaCommandRef") do
              ref when is_binary(ref) and ref != "" ->
                [
                  Reference.new(%{
                    expected_kind: :command,
                    source_ref: reference_path(system_path, "commands", ref),
                    role: :base
                  })
                ]

              _other ->
                []
            end

          nil ->
            []
        end

      parameter_refs = command_parameter_references(element, system_path)

      command =
        declaration(
          :command,
          command_path,
          %{
            abstract: boolean_attr(element, "abstract", false),
            argument_count: length(argument_refs),
            transmission_constraint_count:
              length(Element.descendants(element, "TransmissionConstraint")),
            verifier_count: command_verifier_count(element)
          },
          element,
          state,
          references: base_refs ++ argument_refs ++ parameter_refs
        )

      state
      |> put_declaration(command)
      |> translate_command_constraints(element, system_path, command_path)
      |> translate_command_verifiers(element, system_path, command_path)
    else
      put_diagnostic(
        state,
        diagnostic(:error, "XTCE_COMMAND_NAME_REQUIRED", "MetaCommand has no name", element)
      )
    end
  end

  defp translate_command_arguments(element, system_path, command_path, state) do
    arguments =
      element
      |> Element.child("ArgumentList")
      |> case do
        nil -> []
        list -> Element.children(list, "Argument")
      end

    arguments
    |> Enum.with_index()
    |> Enum.reduce({state, []}, fn {argument, index}, {acc, refs} ->
      name = Element.attr(argument, "name")
      type_ref = Element.attr(argument, "argumentTypeRef")

      if non_empty?(name) and non_empty?(type_ref) do
        type_path = reference_path(system_path, "command_types", type_ref)
        argument_path = command_path <> "/arguments/" <> name

        declaration =
          declaration(
            :command_argument,
            argument_path,
            %{
              required: is_nil(Element.attr(argument, "initialValue")),
              default_value: Element.attr(argument, "initialValue"),
              display_order: index
            },
            argument,
            acc,
            references: [
              Reference.new(%{
                expected_kind: :command_argument_type,
                source_ref: type_path,
                role: :type
              })
            ]
          )

        command_ref =
          Reference.new(%{
            expected_kind: :command_argument,
            source_ref: argument_path,
            role: :argument
          })

        {put_declaration(acc, declaration), refs ++ [command_ref]}
      else
        {put_diagnostic(
           acc,
           diagnostic(
             :error,
             "XTCE_COMMAND_ARGUMENT_INVALID",
             "command argument requires name and argumentTypeRef",
             argument
           )
         ), refs}
      end
    end)
  end

  defp translate_command_constraints(state, element, system_path, command_path) do
    element
    |> Element.descendants("TransmissionConstraint")
    |> Enum.with_index()
    |> Enum.reduce(state, fn {constraint, index}, acc ->
      references = command_parameter_references(constraint, system_path)

      put_declaration(
        acc,
        declaration(
          :command_constraint,
          command_path <> "/constraints/" <> Integer.to_string(index),
          %{
            timeout_ms: duration_ms(Element.attr(constraint, "timeOut")),
            criteria: criteria_document(constraint, system_path)
          },
          constraint,
          acc,
          references: references
        )
      )
    end)
  end

  defp translate_command_verifiers(state, element, system_path, command_path) do
    element
    |> Element.descendants(&(&1.name in @command_verifier_names))
    |> Enum.with_index()
    |> Enum.reduce(state, fn {verifier, index}, acc ->
      criteria = criteria_document(verifier, system_path)
      check_window = Element.child(verifier, "CheckWindow")

      put_declaration(
        acc,
        declaration(
          :command_verifier,
          command_path <> "/verifiers/" <> Integer.to_string(index),
          %{
            phase: verifier_phase(verifier.name),
            success_criteria: if(verifier.name == "FailedVerifier", do: nil, else: criteria),
            failure_criteria: if(verifier.name == "FailedVerifier", do: criteria, else: nil),
            timeout_ms: duration_ms(Element.attr(check_window, "timeToStopChecking")),
            delay_ms: duration_ms(Element.attr(check_window, "timeToStartChecking")),
            severity: if(verifier.name == "FailedVerifier", do: :critical),
            metadata: %{
              xtce_verifier_kind: verifier.name,
              time_window_is_relative_to:
                Element.attr(check_window, "timeWindowIsRelativeTo", "timeLastVerifierPassed")
            }
          },
          verifier,
          acc,
          references: command_parameter_references(verifier, system_path)
        )
      )
    end)
  end

  defp put_units(state, system_path, type_element) do
    type_element
    |> Element.descendants("Unit")
    |> Enum.map(fn unit -> Element.attr(unit, "symbol") || Element.text(unit) end)
    |> Enum.filter(&non_empty?/1)
    |> Enum.uniq()
    |> Enum.reduce({state, []}, fn symbol, {acc, refs} ->
      unit_path = declaration_path(system_path, "units", path_segment(symbol))

      if MapSet.member?(acc.units, unit_path) do
        {acc, refs ++ [unit_path]}
      else
        declaration =
          declaration(:unit, unit_path, %{symbol: symbol}, type_element, acc)

        {%{put_declaration(acc, declaration) | units: MapSet.put(acc.units, unit_path)},
         refs ++ [unit_path]}
      end
    end)
  end

  defp monitoring_policy(parameter_path, alarm, element, state) do
    policy_path = String.replace(parameter_path, "/parameters/", "/monitoring/")

    declaration(
      :monitoring_policy,
      policy_path,
      %{
        default_rules: alarm.rules,
        minimum_violations: alarm.minimum_violations,
        minimum_conformance: alarm.minimum_conformance
      },
      element,
      state,
      references: [
        Reference.new(%{
          expected_kind: :parameter,
          source_ref: parameter_path,
          role: :parameter
        })
      ]
    )
  end

  defp alarm_rules(type_element) do
    numeric =
      type_element
      |> Element.descendants(fn element -> String.ends_with?(element.name, "Range") end)
      |> Enum.flat_map(&numeric_alarm_rule/1)

    enumerated =
      type_element
      |> Element.descendants("EnumerationAlarm")
      |> Enum.map(fn alarm ->
        %{
          kind: :enumerated,
          values: [Element.attr(alarm, "enumerationLabel")],
          severity: alarm_severity(Element.attr(alarm, "alarmLevel"), :warning)
        }
      end)

    numeric ++ enumerated
  end

  defp alarm_definition(type_element) do
    alarm = Element.descendants(type_element, "DefaultAlarm") |> List.first()

    %{
      rules: alarm_rules(type_element),
      minimum_violations: alarm_count(alarm, "minViolations", 1),
      minimum_conformance:
        alarm_count(
          alarm,
          "minConsecutiveValuesToLeaveAlarm",
          alarm_count(alarm, "minViolations", 1)
        )
    }
  end

  defp numeric_alarm_rule(element) do
    severity = severity_from_range_name(element.name)

    if severity do
      [
        %{
          kind: :range,
          lower:
            numeric(
              Element.attr(element, "minInclusive") || Element.attr(element, "minExclusive")
            ),
          upper:
            numeric(
              Element.attr(element, "maxInclusive") || Element.attr(element, "maxExclusive")
            ),
          lower_closed: not is_nil(Element.attr(element, "minInclusive")),
          upper_closed: not is_nil(Element.attr(element, "maxInclusive")),
          severity: severity
        }
      ]
    else
      []
    end
  end

  defp severity_from_range_name(name) do
    cond do
      String.contains?(name, "Watch") -> :watch
      String.contains?(name, "Warning") -> :warning
      String.contains?(name, "Distress") -> :distress
      String.contains?(name, "Critical") -> :critical
      String.contains?(name, "Severe") -> :severe
      true -> nil
    end
  end

  defp container_entries(element, system_path) do
    element
    |> Element.descendants("ParameterRefEntry")
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      location = Element.child(entry, "LocationInContainerInBits")
      fixed_location = location && Element.child(location, "FixedValue")

      %{
        parameter_ref:
          reference_path(system_path, "parameters", Element.attr(entry, "parameterRef")),
        bit_offset:
          location &&
            integer(
              Element.attr(location, "value") || (fixed_location && Element.text(fixed_location))
            ),
        bit_offset_from:
          location && Element.attr(location, "referenceLocation", "containerStart"),
        display_order: index,
        include_condition:
          criteria_document(Element.child(entry, "IncludeCondition"), system_path)
      }
    end)
  end

  defp base_container_reference(element, system_path) do
    case Element.child(element, "BaseContainer") do
      %Element{} = base ->
        case Element.attr(base, "containerRef") do
          ref when is_binary(ref) and ref != "" ->
            [
              Reference.new(%{
                expected_kind: :container,
                source_ref: reference_path(system_path, "containers", ref),
                role: :base
              })
            ]

          _other ->
            []
        end

      nil ->
        []
    end
  end

  defp restriction_criteria(element, system_path) do
    case Element.child(element, "BaseContainer") do
      nil -> nil
      base -> criteria_document(Element.child(base, "RestrictionCriteria"), system_path)
    end
  end

  defp command_parameter_references(element, system_path) do
    element
    |> Element.descendants(fn child -> non_empty?(Element.attr(child, "parameterRef")) end)
    |> Enum.map(&Element.attr(&1, "parameterRef"))
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      Reference.new(%{
        expected_kind: :parameter,
        source_ref: reference_path(system_path, "parameters", ref),
        role: :condition
      })
    end)
  end

  defp criteria_document(nil, _system_path), do: nil

  defp criteria_document(element, system_path) do
    comparisons =
      element
      |> Element.descendants(fn child ->
        child.name in ["Comparison", "Condition"] and
          non_empty?(Element.attr(child, "parameterRef"))
      end)
      |> Enum.map(fn comparison ->
        %{
          parameter_ref:
            reference_path(system_path, "parameters", Element.attr(comparison, "parameterRef")),
          operator: Element.attr(comparison, "comparisonOperator", "=="),
          value: Element.attr(comparison, "value")
        }
      end)

    %{comparisons: comparisons, source_element: element.name}
  end

  defp type_encoding(element) do
    encoding =
      Element.descendants(element, fn child -> String.ends_with?(child.name, "DataEncoding") end)
      |> List.first()

    if encoding do
      %{
        kind: encoding.name,
        size_bits: integer(Element.attr(encoding, "sizeInBits")),
        encoding: Element.attr(encoding, "encoding"),
        byte_order: Element.attr(encoding, "byteOrder")
      }
    else
      %{}
    end
  end

  defp parameter_definition(element) do
    %{
      parameter_source: Element.attr(element, "parameterSource", "telemetered"),
      persistence: integer(Element.attr(element, "persistence")),
      initial_value: Element.attr(element, "initialValue")
    }
  end

  defp valid_range(element) do
    case Element.descendants(element, "ValidRange") |> List.first() do
      nil ->
        nil

      range ->
        %{
          minimum: numeric(Element.attr(range, "minInclusive")),
          maximum: numeric(Element.attr(range, "maxInclusive"))
        }
    end
  end

  defp algorithm_text(element) do
    element
    |> Element.descendants(fn child -> child.name in ["AlgorithmText", "MathOperation"] end)
    |> Enum.map(&Element.text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp section_children(system, metadata_name, set_name) do
    with %Element{} = metadata <- Element.child(system, metadata_name),
         %Element{} = set <- Element.child(metadata, set_name) do
      set.children
    else
      _other -> []
    end
  end

  defp preserve_unsupported_executable_sections(system, system_path, state) do
    telemetry =
      unsupported_sections(
        Element.child(system, "TelemetryMetaData"),
        ["ParameterTypeSet", "ParameterSet", "ContainerSet", "AlgorithmSet"],
        [
          {"ParameterTypeSet", &String.ends_with?(&1.name, "ParameterType")},
          {"ParameterSet", &(&1.name in ["Parameter", "ParameterRef"])},
          {"ContainerSet", &(&1.name == "SequenceContainer")},
          {"AlgorithmSet", &String.ends_with?(&1.name, "Algorithm")}
        ],
        :telemetry
      )

    command =
      unsupported_sections(
        Element.child(system, "CommandMetaData"),
        ["ArgumentTypeSet", "MetaCommandSet"],
        [
          {"ArgumentTypeSet", &String.ends_with?(&1.name, "ArgumentType")},
          {"MetaCommandSet", &(&1.name == "MetaCommand")}
        ],
        :command
      )

    (telemetry ++ command)
    |> Enum.with_index()
    |> Enum.reduce(state, fn {{element, target}, index}, acc ->
      path =
        declaration_path(
          system_path,
          "extensions",
          "unsupported_#{target}_#{index}_#{path_segment(element.name)}"
        )

      acc
      |> put_declaration(
        declaration(
          :extension,
          path,
          %{
            required: true,
            applies_to: [target],
            source_element: Element.to_map(element)
          },
          element,
          acc
        )
      )
      |> put_diagnostic(
        diagnostic(
          :warning,
          "XTCE_CONSTRUCT_PRESERVED_NOT_EXECUTABLE",
          "XTCE #{element.name} is preserved but is not executable by the #{target} target",
          element
        )
      )
    end)
  end

  defp unsupported_sections(nil, _supported_sections, _supported_members, _target), do: []

  defp unsupported_sections(metadata, supported_sections, supported_members, target) do
    unsupported_direct =
      metadata.children
      |> Enum.reject(&(&1.name in supported_sections))
      |> Enum.map(&{&1, target})

    unsupported_members =
      Enum.flat_map(supported_members, fn {set_name, supported?} ->
        case Element.child(metadata, set_name) do
          nil -> []
          set -> set.children |> Enum.reject(supported?) |> Enum.map(&{&1, target})
        end
      end)

    unsupported_direct ++ unsupported_members
  end

  defp child_systems(element) do
    direct = Element.children(element, "SpaceSystem")

    wrapped =
      element
      |> Element.child("SpaceSystemSet")
      |> case do
        nil -> []
        set -> Element.children(set, "SpaceSystem")
      end

    direct ++ wrapped
  end

  defp reference_path(system_path, group, source_ref) when is_binary(source_ref) do
    ref = String.trim(source_ref)
    parts = String.split(ref, "/", trim: true)

    case parts do
      [name] ->
        declaration_path(system_path, group, name)

      [] ->
        declaration_path(system_path, group, "__missing_reference__")

      parts ->
        name = List.last(parts)
        owner_parts = Enum.drop(parts, -1)
        owner = if String.starts_with?(ref, "/"), do: "/", else: system_path

        resolved_owner =
          Enum.reduce(owner_parts, owner, fn
            ".", acc -> acc
            "..", acc -> Path.parent(acc) || "/"
            segment, acc -> Path.join(acc, segment)
          end)

        declaration_path(resolved_owner, group, name)
    end
  end

  defp reference_path(system_path, group, _source_ref),
    do: declaration_path(system_path, group, "__missing_reference__")

  defp declaration_path(system_path, group, name),
    do: system_path |> Path.join(group) |> Path.join(path_segment(name))

  defp declaration(kind, qualified_name, definition, element, %{source: _source} = state) do
    declaration(kind, qualified_name, definition, element, state, [])
  end

  defp declaration(kind, qualified_name, definition, element, %{source: source} = state, opts) do
    declaration(
      kind,
      qualified_name,
      definition,
      element,
      source,
      state.import_run_id,
      opts
    )
  end

  defp declaration(kind, qualified_name, definition, element, %Source{} = source, import_run_id) do
    declaration(kind, qualified_name, definition, element, source, import_run_id, [])
  end

  defp declaration(
         kind,
         qualified_name,
         definition,
         element,
         %Source{} = source,
         import_run_id,
         opts
       ) do
    Declaration.new(%{
      kind: kind,
      qualified_name: qualified_name,
      definition: definition,
      references: Keyword.get(opts, :references, []),
      provenance: %{
        artifact_id: source.artifact_id,
        importer_key: "xtce_1_3",
        importer_version: "1",
        source_path: [element.name, Element.attr(element, "name") || qualified_name],
        source_location: %{line: element.line},
        metadata: %{import_run_id: import_run_id}
      },
      extensions: %{
        "xtce" => %{
          "element" => element.name,
          "attributes" => element.attributes,
          "namespace" => element.namespace,
          "source_element" => Element.to_map(element)
        }
      }
    })
  end

  defp put_declaration(state, declaration),
    do: %{state | declarations: [declaration | state.declarations]}

  defp put_diagnostic(state, diagnostic),
    do: %{state | diagnostics: [diagnostic | state.diagnostics]}

  defp put_alarm_rules(state, _type_path, %{rules: []}), do: state

  defp put_alarm_rules(state, type_path, rules),
    do: %{state | alarm_rules: Map.put(state.alarm_rules, type_path, rules)}

  defp diagnostic(severity, code, message, element) do
    Diagnostic.new(%{
      severity: severity,
      code: code,
      message: message,
      path: [element.name, Element.attr(element, "name") || ""],
      metadata: %{"line" => element.line}
    })
  end

  defp parameter_base_type("IntegerParameterType"), do: :integer
  defp parameter_base_type("FloatParameterType"), do: :float
  defp parameter_base_type("StringParameterType"), do: :string
  defp parameter_base_type("BinaryParameterType"), do: :binary
  defp parameter_base_type("BooleanParameterType"), do: :boolean
  defp parameter_base_type("EnumeratedParameterType"), do: :enumerated
  defp parameter_base_type("AggregateParameterType"), do: :aggregate
  defp parameter_base_type("ArrayParameterType"), do: :array
  defp parameter_base_type("AbsoluteTimeParameterType"), do: :absolute_time
  defp parameter_base_type("RelativeTimeParameterType"), do: :relative_time
  defp parameter_base_type(_name), do: :unknown

  defp argument_base_type("IntegerArgumentType"), do: :integer
  defp argument_base_type("FloatArgumentType"), do: :float
  defp argument_base_type("StringArgumentType"), do: :string
  defp argument_base_type("BinaryArgumentType"), do: :binary
  defp argument_base_type("BooleanArgumentType"), do: :boolean
  defp argument_base_type("EnumeratedArgumentType"), do: :enumerated
  defp argument_base_type("AggregateArgumentType"), do: :aggregate
  defp argument_base_type("ArrayArgumentType"), do: :array
  defp argument_base_type("AbsoluteTimeArgumentType"), do: :absolute_time
  defp argument_base_type("RelativeTimeArgumentType"), do: :relative_time
  defp argument_base_type(_name), do: :unknown

  defp alarm_severity(value, default) do
    case String.downcase(value || "") do
      "watch" -> :watch
      "warning" -> :warning
      "distress" -> :distress
      "critical" -> :critical
      "severe" -> :severe
      _other -> default
    end
  end

  defp verifier_phase(name)
       when name in [
              "TransferredToRangeVerifier",
              "SentFromRangeVerifier",
              "ReceivedVerifier",
              "AcceptedVerifier",
              "QueuedVerifier"
            ],
       do: :acceptance

  defp verifier_phase("ExecutionVerifier"), do: :start
  defp verifier_phase("CompleteVerifier"), do: :completion
  defp verifier_phase("FailedVerifier"), do: :completion
  defp verifier_phase(_name), do: :custom

  defp command_verifier_count(element) do
    length(Element.descendants(element, &(&1.name in @command_verifier_names)))
  end

  defp alarm_count(nil, _name, default), do: default
  defp alarm_count(element, name, default), do: integer(Element.attr(element, name)) || default

  defp boolean_attr(element, name, default) do
    case Element.attr(element, name) do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      _other -> default
    end
  end

  defp duration_ms(nil), do: nil

  defp duration_ms("PT" <> value) do
    case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)S$/, value) do
      [_, seconds] ->
        {number, ""} = Float.parse(seconds)
        round(number * 1_000)

      _other ->
        nil
    end
  end

  defp duration_ms(_value), do: nil

  defp numeric(nil), do: nil

  defp numeric(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp integer(nil), do: nil

  defp integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp path_segment(value) do
    value
    |> String.trim()
    |> String.replace("/", "_")
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""
end
