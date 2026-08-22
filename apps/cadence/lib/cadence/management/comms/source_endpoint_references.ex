defmodule Cadence.Management.Comms.SourceEndpointReferences do
  @moduledoc """
  Narrow management contract for validating mission-owned source-endpoint
  references used by other bounded contexts.
  """

  alias Cadence.SourceEndpoints

  @spec ensure_exists(binary(), binary()) :: :ok | {:error, :source_endpoint_not_found}
  def ensure_exists(mission_id, source_endpoint_ref)
      when is_binary(mission_id) and is_binary(source_endpoint_ref) do
    case SourceEndpoints.fetch_source_endpoint(mission_id, source_endpoint_ref) do
      {:ok, _source_endpoint} -> :ok
      {:error, :source_endpoint_not_found} -> {:error, :source_endpoint_not_found}
    end
  end
end
