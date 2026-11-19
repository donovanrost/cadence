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

  # The layer id and content hash basis (#166). Bump on any change to what it hashes.
  # `content_sha256` stays bare hex, not #166's "v<n>:" form: it is copied out as an identity into
  # activation manifests, runtime plans and command requests, whose readers check 64-hex. The
  # version is inside the hash, so no two bases can compare equal (#166 rule 4 as amended by domain 11-19).
  @basis_version 1

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    declarations = attrs |> value(:declarations, []) |> Enum.map(&build_declaration/1)
    layer_kind = attrs |> value(:layer_kind, :imported) |> normalize_layer_kind()
    mission_id = value(attrs, :mission_id)
    version = value(attrs, :version, 1)
    name = value(attrs, :name, "Mission Model layer")
    source = value(attrs, :source, %{})
    metadata = value(attrs, :metadata, %{})

    organization_id = value(attrs, :organization_id)

    basis =
      {:mission_model_layer, @basis_version,
       %{
         organization_id: organization_id,
         mission_id: mission_id,
         layer_kind: layer_kind,
         version: version,
         source: content_source(source),
         declarations: Enum.map(declarations, &Declaration.hash_basis/1),
         metadata: metadata
       }}

    %__MODULE__{
      layer_id: value(attrs, :layer_id, Canonical.basis_content_id("mission_model_layer", basis)),
      organization_id: organization_id,
      mission_id: mission_id,
      layer_kind: layer_kind,
      status: attrs |> value(:status, :candidate) |> normalize_status(),
      version: version,
      name: name,
      source: source,
      declarations: declarations,
      content_sha256: value(attrs, :content_sha256, Canonical.basis_sha256(basis)),
      metadata: metadata
    }
  end

  # The source keys that describe the content (#119). The rest, the artifact and the import run,
  # are per-import facts kept on the layer as provenance, never hashed; so is the layer's `name`
  # (the uploaded file's name). Missing keys hash as nil.
  @content_source_keys ~w(format_key importer_key importer_version namespace format_version)a

  defp content_source(source) do
    Map.new(@content_source_keys, &{&1, value(source, &1)})
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
