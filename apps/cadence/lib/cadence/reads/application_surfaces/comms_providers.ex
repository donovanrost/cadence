defmodule Cadence.Reads.ApplicationSurfaces.CommsProviders do
  @moduledoc "Frozen federation query adapter for Communications-owned provider reads."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider
  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Comms.MissionProviders

  @impl true
  def application_key, do: "comms"

  @impl true
  def load(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: "comms",
          application_version: 1,
          surface_id: page,
          surface_version: 1,
          query_id: query,
          query_version: 1,
          params: params
        }
      )
      when page in ~w(provider_list provider_new provider_show) do
    if query == "cadence.comms." <> page,
      do: MissionProviders.load(scope, mission_id, page, params),
      else: {:error, :unsupported_application_surface_query}
  end

  def load(_scope, _host, _request), do: {:error, :unsupported_application_surface_query}
end
