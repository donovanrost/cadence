defmodule CadenceWeb.SourceEndpointController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.CommsJSON, as: CommsJSON

  alias CadenceWeb.API.CommsParams, as: CommsParams

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.ControlPlaneAccess

  def index(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "spacecraft_id" => spacecraft_id
      }) do
    with {:ok, _spacecraft} <-
           ControlPlaneAccess.authorize_spacecraft(
             conn.assigns.current_scope,
             organization_id,
             mission_id,
             spacecraft_id
           ) do
      source_endpoints =
        Cadence.SourceEndpoints.list_source_endpoints(
          organization_id,
          mission_id,
          spacecraft_id: spacecraft_id
        )
        |> Enum.map(&CommsJSON.source_endpoint/1)

      json(conn, %{data: source_endpoints})
    end
  end

  def index(conn, %{"organization_id" => organization_id, "mission_id" => mission_id}) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ) do
      source_endpoints =
        Cadence.SourceEndpoints.list_source_endpoints(organization_id, mission_id)
        |> Enum.map(&CommsJSON.source_endpoint/1)

      json(conn, %{data: source_endpoints})
    end
  end

  def show(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "source_endpoint_id" => source_endpoint_id
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %SourceEndpoint{} = source_endpoint} <-
           Cadence.SourceEndpoints.fetch_source_endpoint(
             organization_id,
             mission_id,
             source_endpoint_id
           ) do
      json(conn, %{data: CommsJSON.source_endpoint(source_endpoint)})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "spacecraft_id" => spacecraft_id,
        "source_endpoint" => source_endpoint_params
      }) do
    with {:ok, _spacecraft} <-
           ControlPlaneAccess.authorize_spacecraft(
             conn.assigns.current_scope,
             organization_id,
             mission_id,
             spacecraft_id
           ),
         {:ok, %SourceEndpoint{} = source_endpoint} <-
           CommsParams.source_endpoint(
             organization_id,
             mission_id,
             spacecraft_id,
             scoped_source_endpoint_params(source_endpoint_params, spacecraft_id)
           ),
         {:ok, %SourceEndpoint{} = persisted_source_endpoint} <-
           Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint) do
      conn
      |> put_status(:created)
      |> json(%{data: CommsJSON.source_endpoint(persisted_source_endpoint)})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "mission_id" => mission_id,
        "source_endpoint" => source_endpoint_params
      }) do
    with {:ok, _mission} <-
           ControlPlaneAccess.authorize_mission(
             conn.assigns.current_scope,
             organization_id,
             mission_id
           ),
         {:ok, %SourceEndpoint{} = source_endpoint} <-
           CommsParams.source_endpoint(
             organization_id,
             mission_id,
             source_endpoint_params
           ),
         {:ok, %SourceEndpoint{} = persisted_source_endpoint} <-
           Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint) do
      conn
      |> put_status(:created)
      |> json(%{data: CommsJSON.source_endpoint(persisted_source_endpoint)})
    end
  end

  defp scoped_source_endpoint_params(source_endpoint_params, spacecraft_id)
       when is_map(source_endpoint_params) and is_binary(spacecraft_id) do
    Map.put_new(source_endpoint_params, "spacecraft_id", spacecraft_id)
  end
end
