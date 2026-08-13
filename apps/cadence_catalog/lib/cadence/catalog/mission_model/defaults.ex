defmodule Cadence.Catalog.MissionModel.Defaults do
  @moduledoc "Applies explicit, observable defaults to composed Mission Model declarations."

  alias Cadence.Catalog.MissionModel.{Declaration, Reference}

  @defaults %{
    container: [abstract: false],
    algorithm: [
      triggers: [],
      missing_input: :skip,
      quality_propagation: :worst,
      time_basis: :receipt
    ],
    monitoring_policy: [
      contexts: [],
      minimum_violations: 1,
      minimum_conformance: 1,
      invalid_state: :unknown,
      disabled: false
    ],
    command: [abstract: false],
    command_constraint: [blocking: true]
  }

  @spec apply(%{binary() => Declaration.t()}) :: %{binary() => Declaration.t()}
  def apply(declarations) when is_map(declarations) do
    Map.new(declarations, fn {id, declaration} -> {id, apply_declaration(declaration)} end)
  end

  defp apply_declaration(%Declaration{} = declaration) do
    {definition, applied} =
      @defaults
      |> Map.get(declaration.kind, [])
      |> Enum.reduce({declaration.definition, []}, fn {key, default}, {definition, applied} ->
        if has_key?(definition, key) do
          {definition, applied}
        else
          {Map.put(definition, key, default), [Atom.to_string(key) | applied]}
        end
      end)

    extensions = record_defaults(declaration.extensions, Enum.sort(applied))

    %Declaration{declaration | definition: definition, extensions: extensions}
    |> normalize_algorithm_output_references()
  end

  defp normalize_algorithm_output_references(%Declaration{kind: :algorithm} = declaration) do
    output_references =
      declaration.definition
      |> value(:outputs, [])
      |> Enum.flat_map(fn output ->
        case value(output, :qualified_name) do
          qualified_name when is_binary(qualified_name) and qualified_name != "" ->
            [
              Reference.new(%{
                expected_kind: :parameter,
                source_ref: qualified_name,
                role: :output,
                provenance: declaration.provenance
              })
            ]

          _other ->
            []
        end
      end)

    references =
      (declaration.references ++ output_references)
      |> Enum.uniq_by(&{&1.expected_kind, &1.source_ref, &1.role})

    %Declaration{declaration | references: references}
  end

  defp normalize_algorithm_output_references(%Declaration{} = declaration), do: declaration

  defp has_key?(map, key),
    do: Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))

  defp record_defaults(extensions, []), do: extensions

  defp record_defaults(extensions, applied) do
    compiler = Map.get(extensions, "cadence_compiler", %{})
    Map.put(extensions, "cadence_compiler", Map.put(compiler, "defaults_applied", applied))
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
