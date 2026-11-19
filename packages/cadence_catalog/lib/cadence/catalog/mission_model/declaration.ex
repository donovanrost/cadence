defmodule Cadence.Catalog.MissionModel.Declaration do
  @moduledoc "Typed declaration contributed by a Mission Model layer."

  alias Cadence.Catalog.MissionModel.{Canonical, Expression, Path, Provenance, Reference}

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
    Canonical.sha256(%{
      semantic_id: declaration.semantic_id,
      kind: declaration.kind,
      qualified_name: declaration.qualified_name,
      aliases: declaration.aliases,
      definition: declaration.definition,
      references: declaration.references,
      extensions: declaration.extensions
    })
  end

  @doc """
  The versioned hash basis (#166) that layer and revision ids hash: every field, references and
  provenance through their own bases. Not `fingerprint/1`, which authored overrides store.
  """
  @spec hash_basis(t()) :: Canonical.basis()
  def hash_basis(%__MODULE__{} = declaration) do
    {:mission_model_declaration, 1,
     %{
       semantic_id: declaration.semantic_id,
       kind: declaration.kind,
       name: declaration.name,
       qualified_name: declaration.qualified_name,
       space_system_path: declaration.space_system_path,
       operation: declaration.operation,
       expected_fingerprint: declaration.expected_fingerprint,
       aliases: declaration.aliases,
       definition: plain(declaration.definition),
       references: Enum.map(declaration.references, &Reference.hash_basis/1),
       provenance: Provenance.hash_basis(declaration.provenance),
       extensions: plain(declaration.extensions)
     }}
  end

  # `definition` and `extensions` are free-form; validated expressions are `Expression` structs whose
  # nodes hold AST tuples
  # (`{:literal, nil}`, `{:parameter, id}`). A basis allows no tuple, so each becomes a nested
  # `{:tuple, 1, %{items: [...]}}` basis, which never encodes like a map or a list. Anything else
  # the basis refuses still raises.
  defp plain(%Expression{} = expression),
    do:
      {:mission_model_expression, 1,
       %{node: plain(expression.node), result_type: expression.result_type}}

  defp plain(value) when is_tuple(value),
    do: {:tuple, 1, %{items: value |> Tuple.to_list() |> Enum.map(&plain/1)}}

  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)

  defp plain(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, item} -> {key, plain(item)} end)

  defp plain(value), do: value

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
