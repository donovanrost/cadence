defmodule CadenceWeb.API.CommsJSON do
  @moduledoc "Spacecraft and source endpoint response serialization boundary."

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  @spec source_endpoint(SourceEndpoint.t()) :: map()
  def source_endpoint(%SourceEndpoint{} = source_endpoint) do
    %{
      source_endpoint_id: source_endpoint.source_endpoint_id,
      organization_id: source_endpoint.organization_id,
      mission_id: source_endpoint.mission_id,
      spacecraft_id: source_endpoint.spacecraft_id,
      source_ref: source_endpoint.source_ref,
      scid: source_endpoint.scid,
      display_name: source_endpoint.display_name,
      metadata: source_endpoint.metadata
    }
  end

  def spacecraft(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      scid: spacecraft.scid,
      metadata: spacecraft.metadata
    }
  end
end
