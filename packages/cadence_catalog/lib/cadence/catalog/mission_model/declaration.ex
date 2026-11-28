defmodule Cadence.Catalog.MissionModel.Declaration do
  @moduledoc "Typed declaration contributed by a Mission Model layer."

  alias Cadence.Catalog.MissionModel.{Canonical, Path, Provenance, Reference}
  alias Cadence.Platform.ContentBasis

  @basis_version 1
  @basis_fields %{
    __MODULE__ => [
      :semantic_id,
      :kind,
      :qualified_name,
      :aliases,
      :definition,
      :references,
      :extensions
    ],
    Reference => [
      :expected_kind,
      :source_ref,
      :role,
      :resolved_id,
      :resolved_qualified_name,
      :required,
      :provenance
    ],
    Provenance => [
      :artifact_id,
      :importer_key,
      :importer_version,
      :source_path,
      :source_location,
      :transformations,
      :metadata
    ]
  }

  @kinds [
    :space_system,
    :unit,
    :parameter_type,
    :parameter,
    :container,
    :calibrator,
    :algorithm,
    :monitoring_policy,
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

  @operations [:add, :extend, :replace, :remove]

  @type kind :: unquote(Enum.reduce(@kinds, &{:|, [], [&1, &2]}))
  @type operation :: :add | :extend | :replace | :remove

  @type t :: %__MODULE__{
          semantic_id: binary(),
          kind: kind(),
          name: binary(),
          qualified_name: binary(),
          space_system_path: binary(),
          operation: operation(),
          expected_fingerprint: binary() | nil,
          aliases: [binary()],
          definition: map(),
          references: [Reference.t()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  @enforce_keys [:semantic_id, :kind, :name, :qualified_name, :space_system_path]
  defstruct @enforce_keys ++
              [
                :expected_fingerprint,
                aliases: [],
                operation: :add,
                definition: %{},
                references: [],
                provenance: nil,
                extensions: %{}
              ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    kind = attrs |> value(:kind) |> normalize_kind()
    qualified_name = attrs |> value(:qualified_name) |> Path.normalize()
    name = value(attrs, :name, qualified_name |> String.split("/", trim: true) |> List.last())

    %__MODULE__{
      semantic_id: value(attrs, :semantic_id, Canonical.semantic_id(kind, qualified_name)),
      kind: kind,
      name: name || "/",
      qualified_name: qualified_name,
      space_system_path: value(attrs, :space_system_path, Path.parent(qualified_name) || "/"),
      operation: attrs |> value(:operation, :add) |> normalize_operation(),
      expected_fingerprint: value(attrs, :expected_fingerprint),
      aliases: value(attrs, :aliases, []),
      definition: value(attrs, :definition, %{}),
      references: attrs |> value(:references, []) |> Enum.map(&build_reference/1),
      provenance: attrs |> value(:provenance) |> Provenance.new(),
      extensions: value(attrs, :extensions, %{})
    }
  end

  @spec fingerprint(t()) :: binary()
  def fingerprint(%__MODULE__{} = declaration) do
    declaration
    |> basis_value()
    |> Map.to_list()
    |> then(&ContentBasis.digest("override_fingerprint", @basis_version, &1))
  end

  @doc false
  def basis_struct_fields, do: @basis_fields

  defp basis_value(%module{} = value) do
    fields = Map.fetch!(@basis_fields, module)
    value |> ContentBasis.project(fields) |> basis_value()
  end

  defp basis_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, basis_value(value)} end)

  defp basis_value(list) when is_list(list), do: Enum.map(list, &basis_value/1)
  defp basis_value(other), do: other

  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  defp build_reference(%Reference{} = reference), do: reference
  defp build_reference(attrs), do: Reference.new(attrs)

  defp normalize_kind(kind) when kind in @kinds, do: kind

  defp normalize_kind(kind) when is_binary(kind),
    do: normalize_kind(String.to_existing_atom(kind))

  defp normalize_operation(operation) when operation in @operations, do: operation

  defp normalize_operation(operation) when is_binary(operation),
    do: normalize_operation(String.to_existing_atom(operation))

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
