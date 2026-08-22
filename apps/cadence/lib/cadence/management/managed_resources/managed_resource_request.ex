defmodule Cadence.Management.ManagedResources.ManagedResourceRequest do
  @moduledoc "Immutable Management fact requesting one managed-resource lifecycle action."

  alias Cadence.DataSources.DataSource
  alias Cadence.Platform.ContentHash

  @type operation :: :provision | :deprovision
  @type t :: %__MODULE__{
          request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          resource_type: :tsdb_backend,
          resource_id: binary(),
          operation: operation(),
          content_sha256: binary(),
          requested_at: DateTime.t(),
          data_source: DataSource.t()
        }

  @enforce_keys [
    :request_id,
    :organization_id,
    :mission_id,
    :resource_type,
    :resource_id,
    :operation,
    :content_sha256,
    :requested_at,
    :data_source
  ]
  defstruct @enforce_keys

  @spec new(DataSource.t(), operation(), DateTime.t(), binary() | nil) :: t()
  def new(%DataSource{} = source, operation, %DateTime{} = requested_at, request_id \\ nil)
      when operation in [:provision, :deprovision] do
    requested_at = DateTime.truncate(requested_at, :microsecond)

    basis = %{
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      resource_type: :tsdb_backend,
      resource_id: source.data_source_id,
      operation: operation,
      requested_at: requested_at,
      source_status: source.status,
      source_metadata: source.metadata
    }

    hash = ContentHash.term_sha256(basis)

    %__MODULE__{
      request_id: request_id || "managed_resource:#{operation}:#{source.data_source_id}:#{hash}",
      organization_id: source.organization_id,
      mission_id: source.mission_id,
      resource_type: :tsdb_backend,
      resource_id: source.data_source_id,
      operation: operation,
      content_sha256: hash,
      requested_at: requested_at,
      data_source: source
    }
  end
end
