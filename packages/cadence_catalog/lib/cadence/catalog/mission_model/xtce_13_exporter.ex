defmodule Cadence.Catalog.MissionModel.Xtce13Exporter do
  @moduledoc "Deterministic XTCE 1.3 export for the supported Mission Model core."

  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.MissionModel.{Declaration, Reference, Revision}

  @namespace XTCE.namespace()

  @spec export(Revision.t(), keyword()) :: {:ok, binary(), [Diagnostic.t()]} | {:error, term()}
  def export(%Revision{} = revision, opts \\ []) do
    declarations = revision.declarations |> Map.values() |> Enum.sort_by(& &1.qualified_name)
    root_name = Keyword.get(opts, :root_name, inferred_root_name(declarations))

    if is_binary(root_name) and root_name != "" do
      root_path = "/" <> root_name

      xml =
        [
          ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
          ~s(<SpaceSystem xmlns="#{@namespace}" name="#{escape(root_name)}">),
          export_system_body(root_path, declarations, 1),
          "\n</SpaceSystem>\n"
        ]
        |> IO.iodata_to_binary()

      diagnostics = unsupported_diagnostics(declarations)
      {:ok, xml, diagnostics}
    else
      {:error, :xtce_export_root_space_system_required}
    end
  end

  defp export_system_body(system_path, declarations, depth) do
    local = declarations_for_system(declarations, system_path)
    telemetry = export_telemetry(local, depth)
    commands = export_commands(local, depth)

    children =
      declarations
      |> Enum.filter(
        &(&1.kind == :space_system and parent_path(&1.qualified_name) == system_path)
      )
      |> Enum.sort_by(& &1.qualified_name)
      |> Enum.map(fn child ->
        [
          newline(depth),
          ~s(<SpaceSystem name="#{escape(child.name)}">),
          export_system_body(child.qualified_name, declarations, depth + 1),
          newline(depth),
          "</SpaceSystem>"
        ]
      end)

    [telemetry, commands, children]
  end

  defp export_telemetry(declarations, depth) do
    types = filter_kind(declarations, :parameter_type)
    parameters = filter_kind(declarations, :parameter)
    containers = filter_kind(declarations, :container)
    algorithms = filter_kind(declarations, :algorithm)

    if types == [] and parameters == [] and containers == [] and algorithms == [] do
      []
    else
      [
        newline(depth),
        "<TelemetryMetaData>",
        export_parameter_types(types, depth + 1),
        export_parameters(parameters, depth + 1),
        export_containers(containers, depth + 1),
        export_algorithms(algorithms, depth + 1),
        newline(depth),
        "</TelemetryMetaData>"
      ]
    end
  end

  defp export_parameter_types([], _depth), do: []

  defp export_parameter_types(types, depth) do
    [
      newline(depth),
      "<ParameterTypeSet>",
      Enum.map(types, fn type ->
        element_name = parameter_type_element(value(type.definition, :base_type))
        encoding = value(type.definition, :encoding, %{})
        size = value(encoding, :size_bits)

        [
          newline(depth + 1),
          "<",
          element_name,
          ~s( name="#{escape(type.name)}">),
          encoding_element(value(type.definition, :base_type), size, depth + 2),
          newline(depth + 1),
          "</",
          element_name,
          ">"
        ]
      end),
      newline(depth),
      "</ParameterTypeSet>"
    ]
  end

  defp export_parameters([], _depth), do: []

  defp export_parameters(parameters, depth) do
    [
      newline(depth),
      "<ParameterSet>",
      Enum.map(parameters, fn parameter ->
        type_ref = reference(parameter, :type)

        [
          newline(depth + 1),
          ~s(<Parameter name="#{escape(parameter.name)}" parameterTypeRef="#{escape(xtce_ref(type_ref))}"/>)
        ]
      end),
      newline(depth),
      "</ParameterSet>"
    ]
  end

  defp export_containers([], _depth), do: []

  defp export_containers(containers, depth) do
    [
      newline(depth),
      "<ContainerSet>",
      Enum.map(containers, fn container ->
        entries = Enum.filter(container.references, &(&1.role == :entry))

        [
          newline(depth + 1),
          ~s(<SequenceContainer name="#{escape(container.name)}">),
          if(entries == [],
            do: [],
            else: [
              newline(depth + 2),
              "<EntryList>",
              Enum.map(entries, fn entry ->
                [
                  newline(depth + 3),
                  ~s(<ParameterRefEntry parameterRef="#{escape(xtce_ref(reference_target(entry)))}"/>)
                ]
              end),
              newline(depth + 2),
              "</EntryList>"
            ]
          ),
          newline(depth + 1),
          "</SequenceContainer>"
        ]
      end),
      newline(depth),
      "</ContainerSet>"
    ]
  end

  defp export_algorithms([], _depth), do: []

  defp export_algorithms(algorithms, depth) do
    [
      newline(depth),
      "<AlgorithmSet>",
      Enum.map(algorithms, fn algorithm ->
        inputs = Enum.filter(algorithm.references, &(&1.role == :input))
        outputs = Enum.filter(algorithm.references, &(&1.role == :output))

        [
          newline(depth + 1),
          ~s(<CustomAlgorithm name="#{escape(algorithm.name)}">),
          export_algorithm_refs("InputSet", "InputParameterInstanceRef", inputs, depth + 2),
          export_algorithm_refs("OutputSet", "OutputParameterRef", outputs, depth + 2),
          newline(depth + 1),
          "</CustomAlgorithm>"
        ]
      end),
      newline(depth),
      "</AlgorithmSet>"
    ]
  end

  defp export_algorithm_refs(_set, _element, [], _depth), do: []

  defp export_algorithm_refs(set, element, references, depth) do
    [
      newline(depth),
      "<",
      set,
      ">",
      Enum.map(references, fn ref ->
        [
          newline(depth + 1),
          "<",
          element,
          ~s( parameterRef="#{escape(xtce_ref(reference_target(ref)))}"/>)
        ]
      end),
      newline(depth),
      "</",
      set,
      ">"
    ]
  end

  defp export_commands(declarations, depth) do
    types = filter_kind(declarations, :command_argument_type)
    commands = filter_kind(declarations, :command)

    if types == [] and commands == [] do
      []
    else
      [
        newline(depth),
        "<CommandMetaData>",
        export_argument_types(types, depth + 1),
        export_meta_commands(commands, declarations, depth + 1),
        newline(depth),
        "</CommandMetaData>"
      ]
    end
  end

  defp export_argument_types([], _depth), do: []

  defp export_argument_types(types, depth) do
    [
      newline(depth),
      "<ArgumentTypeSet>",
      Enum.map(types, fn type ->
        element = argument_type_element(value(type.definition, :base_type))
        [newline(depth + 1), "<", element, ~s( name="#{escape(type.name)}"/>)]
      end),
      newline(depth),
      "</ArgumentTypeSet>"
    ]
  end

  defp export_meta_commands([], _declarations, _depth), do: []

  defp export_meta_commands(commands, declarations, depth) do
    [
      newline(depth),
      "<MetaCommandSet>",
      Enum.map(commands, fn command ->
        arguments =
          declarations
          |> Enum.filter(fn declaration ->
            declaration.kind == :command_argument and
              String.starts_with?(
                declaration.qualified_name,
                command.qualified_name <> "/arguments/"
              )
          end)
          |> Enum.sort_by(& &1.qualified_name)

        [
          newline(depth + 1),
          ~s(<MetaCommand name="#{escape(command.name)}">),
          if(arguments == [],
            do: [],
            else: [
              newline(depth + 2),
              "<ArgumentList>",
              Enum.map(arguments, fn argument ->
                [
                  newline(depth + 3),
                  ~s(<Argument name="#{escape(argument.name)}" argumentTypeRef="#{escape(xtce_ref(reference(argument, :type)))}"/>)
                ]
              end),
              newline(depth + 2),
              "</ArgumentList>"
            ]
          ),
          newline(depth + 1),
          "</MetaCommand>"
        ]
      end),
      newline(depth),
      "</MetaCommandSet>"
    ]
  end

  defp declarations_for_system(declarations, system_path) do
    Enum.filter(declarations, fn declaration -> owning_system(declaration) == system_path end)
  end

  defp owning_system(%Declaration{kind: :space_system, qualified_name: path}),
    do: parent_path(path)

  defp owning_system(%Declaration{qualified_name: path}) do
    path
    |> String.split("/", trim: true)
    |> Enum.take_while(&(&1 not in semantic_groups()))
    |> then(fn
      [] -> "/"
      parts -> "/" <> Enum.join(parts, "/")
    end)
  end

  defp semantic_groups do
    [
      "types",
      "parameters",
      "containers",
      "algorithms",
      "monitoring",
      "command_types",
      "commands"
    ]
  end

  defp inferred_root_name(declarations) do
    declarations
    |> Enum.filter(&(&1.kind == :space_system and parent_path(&1.qualified_name) == "/"))
    |> Enum.reject(&(&1.qualified_name == "/"))
    |> Enum.sort_by(& &1.qualified_name)
    |> List.first()
    |> case do
      nil -> nil
      declaration -> declaration.name
    end
  end

  defp unsupported_diagnostics(declarations) do
    declarations
    |> Enum.filter(&(&1.kind in [:monitoring_policy, :command_constraint, :command_verifier]))
    |> Enum.map(fn declaration ->
      Diagnostic.new(%{
        severity: :warning,
        code: "XTCE_EXPORT_SEMANTIC_EXTENSION_OMITTED",
        message:
          "#{declaration.kind} #{declaration.qualified_name} is retained in the Mission Model but omitted from core XTCE export",
        path: String.split(declaration.qualified_name, "/", trim: true),
        metadata: %{"semantic_id" => declaration.semantic_id}
      })
    end)
  end

  defp reference(declaration, role) do
    declaration.references
    |> Enum.find(&(&1.role == role))
    |> reference_target()
  end

  defp reference_target(nil), do: ""

  defp reference_target(%Reference{} = reference),
    do: reference.resolved_qualified_name || reference.source_ref

  defp xtce_ref(nil), do: ""

  defp xtce_ref(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.reject(&(&1 in semantic_groups()))
    |> then(&("/" <> Enum.join(&1, "/")))
  end

  defp filter_kind(declarations, kind),
    do: declarations |> Enum.filter(&(&1.kind == kind)) |> Enum.sort_by(& &1.qualified_name)

  defp parameter_type_element(type) do
    case type do
      value when value in [:float, "float"] -> "FloatParameterType"
      value when value in [:string, "string"] -> "StringParameterType"
      value when value in [:binary, "binary"] -> "BinaryParameterType"
      value when value in [:boolean, "boolean"] -> "BooleanParameterType"
      value when value in [:enumerated, "enumerated"] -> "EnumeratedParameterType"
      _other -> "IntegerParameterType"
    end
  end

  defp argument_type_element(type) do
    parameter_type_element(type) |> String.replace("Parameter", "Argument")
  end

  defp encoding_element(type, size, depth)
       when type in [:integer, "integer"] and is_integer(size) do
    [newline(depth), ~s(<IntegerDataEncoding sizeInBits="#{size}"/>)]
  end

  defp encoding_element(type, size, depth) when type in [:float, "float"] and is_integer(size) do
    [newline(depth), ~s(<FloatDataEncoding sizeInBits="#{size}"/>)]
  end

  defp encoding_element(_type, _size, _depth), do: []

  defp parent_path("/"), do: nil

  defp parent_path(path) do
    parts = String.split(path, "/", trim: true)

    case Enum.drop(parts, -1) do
      [] -> "/"
      parent -> "/" <> Enum.join(parent, "/")
    end
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape(value), do: value |> to_string() |> escape()

  defp newline(depth), do: ["\n", String.duplicate("  ", depth)]

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
