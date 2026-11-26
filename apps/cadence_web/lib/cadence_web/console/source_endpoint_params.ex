defmodule CadenceWeb.Console.SourceEndpointParams do
  @moduledoc "Source endpoint request parsing boundary."

  import CadenceWeb.API.ParamParser

  @spec attributes(binary() | nil, map()) :: {:ok, map()} | {:error, term()}
  def attributes(scoped_spacecraft_id, params) when is_map(params) do
    with {:ok, scid} <- optional_integer(params, "scid"),
         {:ok, spacecraft_id} <- resolve_spacecraft_id(params, scoped_spacecraft_id) do
      {:ok,
       %{
         spacecraft_id: spacecraft_id,
         source_ref: string_value(params, "source_ref"),
         scid: scid,
         display_name: string_value(params, "display_name"),
         metadata: map_value(params, "metadata")
       }}
    end
  end
end
