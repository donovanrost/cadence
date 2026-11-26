defmodule CadenceWeb.API.CommsParams do
  @moduledoc "Source endpoint request parsing boundary."

  import CadenceWeb.API.ParamParser

  alias Cadence.SourceEndpoints.SourceEndpoint

  @spec source_endpoint(binary(), binary(), map()) :: {:ok, SourceEndpoint.t()} | {:error, term()}
  def source_endpoint(organization_id, mission_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    source_endpoint(organization_id, mission_id, nil, params)
  end

  @spec source_endpoint(binary(), binary(), binary() | nil, map()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def source_endpoint(organization_id, mission_id, scoped_spacecraft_id, params)
      when is_binary(organization_id) and is_binary(mission_id) and is_map(params) do
    with {:ok, scid} <- optional_integer(params, "scid"),
         {:ok, spacecraft_id} <- resolve_spacecraft_id(params, scoped_spacecraft_id) do
      {:ok,
       SourceEndpoint.new(%{
         source_endpoint_id: string_value(params, "source_endpoint_id"),
         organization_id: organization_id,
         mission_id: mission_id,
         spacecraft_id: spacecraft_id,
         source_ref: string_value(params, "source_ref"),
         scid: scid,
         display_name: string_value(params, "display_name"),
         metadata: map_value(params, "metadata")
       })}
    end
  end
end
