defmodule Cadence.Reads.ApplicationSurfaces.Comms do
  @moduledoc "Legacy federation query identity adapter for Communications page reads."
  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{Comms, HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Comms.Pages

  @impl true
  def application_key, do: "comms"

  @impl true
  def load(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: "comms",
          application_version: 1,
          surface_id: surface_id,
          surface_version: 1,
          query_id: query_id,
          query_version: 1,
          params: params
        }
      ) do
    case Comms.query_id(surface_id) do
      {:ok, ^query_id} -> Pages.load(scope, mission_id, surface_id, params)
      _invalid -> {:error, :unsupported_application_surface_query}
    end
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defdelegate overview(scope, mission_id), to: Pages
  defdelegate overview_presentation(scope, mission), to: Pages
  defdelegate validation(scope, mission_id), to: Pages
  defdelegate finding_groups(findings), to: Pages
  defdelegate finding_label(severity), to: Pages
  defdelegate validate_bounded_payload(value), to: Pages
end
