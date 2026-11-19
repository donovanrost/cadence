defmodule Cadence.Management.Comms.SourceEndpointReferences do
  @moduledoc """
  Narrow management contract for validating mission-owned source-endpoint
  references used by other bounded contexts.
  """

  alias Cadence.SourceEndpoints

  @doc "Which of `refs` exist as the mission's source endpoints, in one read."
  @spec existing(binary(), [binary()]) :: MapSet.t(binary())
  def existing(_mission_id, []), do: MapSet.new()

  def existing(mission_id, refs) when is_binary(mission_id) and is_list(refs),
    do: mission_id |> SourceEndpoints.existing_source_endpoint_ids(refs) |> MapSet.new()

  @spec ensure_exists(binary(), binary()) :: :ok | {:error, :source_endpoint_not_found}
  def ensure_exists(mission_id, source_endpoint_ref)
      when is_binary(mission_id) and is_binary(source_endpoint_ref) do
    case SourceEndpoints.fetch_source_endpoint(mission_id, source_endpoint_ref) do
      {:ok, _source_endpoint} -> :ok
      {:error, :source_endpoint_not_found} -> {:error, :source_endpoint_not_found}
    end
  end
end
