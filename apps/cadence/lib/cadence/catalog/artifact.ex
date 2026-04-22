defmodule Cadence.Catalog.Artifact do
  @moduledoc """
  Preserved source artifact for one catalog import input.
  """

  alias Cadence.Ids
  alias Cadence.Persistence.JsonDocument

  @type catalog_family :: :telemetry | :command | :combined

  @type t :: %__MODULE__{
          artifact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          catalog_database_id: binary() | nil,
          catalog_family: catalog_family(),
          artifact_name: binary(),
          format_key: binary(),
          format_version: binary() | nil,
          media_type: binary() | nil,
          source_artifact: term(),
          content_sha256: binary(),
          uploaded_by: map(),
          uploaded_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :artifact_id,
    :organization_id,
    :mission_id,
    :catalog_database_id,
    :catalog_family,
    :artifact_name,
    :format_key,
    :format_version,
    :media_type,
    :source_artifact,
    :content_sha256,
    :uploaded_at,
    uploaded_by: %{},
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    source_artifact = Map.fetch!(attrs, :source_artifact)

    %__MODULE__{
      artifact_id: Map.get(attrs, :artifact_id, Ids.new("catalog_artifact")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      catalog_database_id:
        Map.get(attrs, :catalog_database_id, Map.get(attrs, "catalog_database_id")),
      catalog_family: Map.fetch!(attrs, :catalog_family),
      artifact_name: Map.fetch!(attrs, :artifact_name),
      format_key: Map.fetch!(attrs, :format_key),
      format_version: Map.get(attrs, :format_version),
      media_type: Map.get(attrs, :media_type),
      source_artifact: source_artifact,
      content_sha256: Map.get(attrs, :content_sha256, content_sha256(source_artifact)),
      uploaded_by: Map.get(attrs, :uploaded_by, %{}),
      uploaded_at: Map.get(attrs, :uploaded_at, DateTime.utc_now()),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp content_sha256(source_artifact) do
    source_artifact
    |> JsonDocument.encode()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  alias Cadence.Catalog.ImporterDescriptor

  @type upload :: %{
          required(:filename) => binary(),
          required(:bytes) => binary(),
          optional(:client_type) => binary() | nil
        }

  @doc """
  Builds an `Artifact` struct from a LiveView upload entry plus the detected
  importer descriptor.

  The `source_artifact` field is set to the raw uploaded bytes; importers
  that need a structured shape can unpack the binary themselves. The
  `media_type` is taken from the client-supplied `:client_type` when present,
  falling back to the first entry in the descriptor's `media_types`.
  """
  @spec build_from_upload(binary(), ImporterDescriptor.t(), upload(), keyword()) :: t()
  def build_from_upload(mission_id, %ImporterDescriptor{} = descriptor, upload, opts \\ [])
      when is_binary(mission_id) and is_map(upload) and is_list(opts) do
    filename = Map.fetch!(upload, :filename)
    bytes = Map.fetch!(upload, :bytes)
    client_type = Map.get(upload, :client_type)

    new(%{
      mission_id: mission_id,
      catalog_family: descriptor.catalog_family,
      catalog_database_id: Keyword.get(opts, :catalog_database_id),
      artifact_name: filename,
      format_key: descriptor.importer_key,
      media_type: resolve_media_type(descriptor, client_type),
      source_artifact: bytes,
      uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @doc """
  Returns `{payload_bytes, content_type}` for serving the artifact to a
  browser download. Accepts the several `source_artifact` shapes that
  first-party importers use (raw binary, `%{"yaml" => bytes}`, etc.) and
  falls back to a JSON encoding for anything else.
  """
  @spec download_payload(t()) :: {binary(), binary()}
  def download_payload(%__MODULE__{source_artifact: bytes} = artifact) when is_binary(bytes) do
    {bytes, artifact.media_type || "application/octet-stream"}
  end

  def download_payload(%__MODULE__{source_artifact: %{"yaml" => bytes}} = artifact)
      when is_binary(bytes) do
    {bytes, artifact.media_type || "application/yaml"}
  end

  def download_payload(%__MODULE__{source_artifact: %{yaml: bytes}} = artifact)
      when is_binary(bytes) do
    {bytes, artifact.media_type || "application/yaml"}
  end

  def download_payload(%__MODULE__{source_artifact: source} = artifact) do
    payload = source |> JsonDocument.encode() |> Jason.encode!()
    {payload, artifact.media_type || "application/json"}
  end

  defp resolve_media_type(%ImporterDescriptor{}, client_type) when is_binary(client_type),
    do: client_type

  defp resolve_media_type(%ImporterDescriptor{media_types: [head | _]}, _), do: head
  defp resolve_media_type(%ImporterDescriptor{media_types: []}, nil), do: nil
end
