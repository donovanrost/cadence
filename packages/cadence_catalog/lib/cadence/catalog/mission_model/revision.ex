defmodule Cadence.Catalog.MissionModel.Revision do
  @moduledoc "Resolved immutable Mission Model semantic graph."

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration, Diagnostic, SpaceSystem}

  @type status :: :candidate | :approved | :rejected | :retired

  @type t :: %__MODULE__{
          revision_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          status: status(),
          compiler_version: binary(),
          layer_ids: [binary()],
          declarations: %{binary() => struct()},
          space_systems: %{binary() => struct()},
          edges: [map()],
          diagnostics: [Diagnostic.t()],
          content_sha256: binary(),
          metadata: map()
        }

  @enforce_keys [
    :revision_id,
    :mission_id,
    :status,
    :compiler_version,
    :layer_ids,
    :content_sha256
  ]
  defstruct @enforce_keys ++
              [
                :organization_id,
                declarations: %{},
                space_systems: %{},
                edges: [],
                diagnostics: [],
                metadata: %{}
              ]

  @spec build(map()) :: t()
  def build(attrs) when is_map(attrs) do
    basis = %{
      mission_id: Map.fetch!(attrs, :mission_id),
      compiler_version: Map.fetch!(attrs, :compiler_version),
      layer_ids: Map.fetch!(attrs, :layer_ids),
      declarations: Map.fetch!(attrs, :declarations),
      space_systems: Map.fetch!(attrs, :space_systems),
      edges: Map.fetch!(attrs, :edges)
    }

    %__MODULE__{
      revision_id:
        Map.get(attrs, :revision_id, Canonical.content_id("mission_model_revision", basis)),
      organization_id: Map.get(attrs, :organization_id),
      mission_id: basis.mission_id,
      status: Map.get(attrs, :status, :candidate),
      compiler_version: basis.compiler_version,
      layer_ids: basis.layer_ids,
      declarations: basis.declarations,
      space_systems: basis.space_systems,
      edges: basis.edges,
      diagnostics: Map.get(attrs, :diagnostics, []),
      content_sha256: Map.get(attrs, :content_sha256, Canonical.sha256(basis)),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    declarations =
      attrs
      |> value(:declarations, %{})
      |> Map.new(fn {id, declaration} -> {id, build_declaration(declaration)} end)

    space_systems =
      attrs
      |> value(:space_systems, %{})
      |> Map.new(fn {id, system} -> {id, build_space_system(system)} end)

    %__MODULE__{
      revision_id: value(attrs, :revision_id),
      organization_id: value(attrs, :organization_id),
      mission_id: value(attrs, :mission_id),
      status: attrs |> value(:status) |> normalize_atom(),
      compiler_version: value(attrs, :compiler_version),
      layer_ids: value(attrs, :layer_ids, []),
      declarations: declarations,
      space_systems: space_systems,
      edges: value(attrs, :edges, []) |> Enum.map(&atomize_edge/1),
      diagnostics: value(attrs, :diagnostics, []) |> Enum.map(&Diagnostic.new/1),
      content_sha256: value(attrs, :content_sha256),
      metadata: value(attrs, :metadata, %{})
    }
  end

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{diagnostics: diagnostics}) do
    not Enum.any?(diagnostics, &Diagnostic.blocking?/1)
  end

  defp build_declaration(%Declaration{} = declaration), do: declaration

  defp build_declaration(attrs), do: Declaration.new(attrs)

  defp build_space_system(%SpaceSystem{} = system), do: system
  defp build_space_system(attrs), do: SpaceSystem.new(attrs)

  defp atomize_edge(edge) do
    %{
      from: value(edge, :from),
      to: value(edge, :to),
      role: edge |> value(:role) |> normalize_optional_atom(),
      required: value(edge, :required, true)
    }
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp normalize_optional_atom(nil), do: nil
  defp normalize_optional_atom(value), do: normalize_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
