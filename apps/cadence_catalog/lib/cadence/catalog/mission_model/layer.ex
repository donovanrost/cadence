defmodule Cadence.Catalog.MissionModel.Layer do
  @moduledoc "Immutable imported or authored Mission Model declaration layer."

  alias Cadence.Catalog.MissionModel.{Canonical, Declaration}

  @type layer_kind :: :imported | :authored
  @type status :: :candidate | :approved | :retired

  @type t :: %__MODULE__{
          layer_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          layer_kind: layer_kind(),
          status: status(),
          version: pos_integer(),
          name: binary(),
          source: map(),
          declarations: [Declaration.t()],
          content_sha256: binary(),
          metadata: map()
        }

  @enforce_keys [
    :layer_id,
    :mission_id,
    :layer_kind,
    :status,
    :version,
    :name,
    :content_sha256
  ]
  defstruct @enforce_keys ++ [:organization_id, source: %{}, declarations: [], metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    declarations = attrs |> value(:declarations, []) |> Enum.map(&build_declaration/1)
    layer_kind = attrs |> value(:layer_kind, :imported) |> normalize_layer_kind()
    mission_id = value(attrs, :mission_id)
    version = value(attrs, :version, 1)
    name = value(attrs, :name, "Mission Model layer")
    source = value(attrs, :source, %{})
    metadata = value(attrs, :metadata, %{})

    basis = %{
      mission_id: mission_id,
      layer_kind: layer_kind,
      version: version,
      name: name,
      source: source,
      declarations: declarations,
      metadata: metadata
    }

    %__MODULE__{
      layer_id: value(attrs, :layer_id, Canonical.content_id("mission_model_layer", basis)),
      organization_id: value(attrs, :organization_id),
      mission_id: mission_id,
      layer_kind: layer_kind,
      status: attrs |> value(:status, :candidate) |> normalize_status(),
      version: version,
      name: name,
      source: source,
      declarations: declarations,
      content_sha256: value(attrs, :content_sha256, Canonical.sha256(basis)),
      metadata: metadata
    }
  end

  defp build_declaration(%Declaration{} = declaration), do: declaration
  defp build_declaration(attrs), do: Declaration.new(attrs)

  defp normalize_layer_kind(value) when value in [:imported, :authored], do: value

  defp normalize_layer_kind(value) when is_binary(value),
    do: normalize_layer_kind(String.to_existing_atom(value))

  defp normalize_status(value) when value in [:candidate, :approved, :retired], do: value

  defp normalize_status(value) when is_binary(value),
    do: normalize_status(String.to_existing_atom(value))

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
