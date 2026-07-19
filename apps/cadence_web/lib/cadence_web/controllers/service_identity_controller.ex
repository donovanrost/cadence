defmodule CadenceWeb.ServiceIdentityController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Auth.ServiceIdentity
  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON, ControlPlaneParams}

  def index(conn, %{"organization_id" => organization_id} = params) do
    with {:ok, _organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :manage_service_identities
           ) do
      service_identities =
        organization_id
        |> Cadence.Auth.list_service_identities(mission_id: Map.get(params, "mission_id"))
        |> Enum.map(&ControlPlaneJSON.service_identity/1)

      json(conn, %{data: service_identities})
    end
  end

  def create(conn, %{
        "organization_id" => organization_id,
        "service_identity" => service_identity_params
      }) do
    with {:ok, _organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :manage_service_identities
           ),
         {:ok, %ServiceIdentity{} = service_identity} <-
           ControlPlaneParams.service_identity(organization_id, service_identity_params),
         {:ok, %{service_identity: issued_service_identity, api_token: api_token}} <-
           Cadence.Auth.issue_service_identity(service_identity) do
      conn
      |> put_status(:created)
      |> json(%{
        data:
          ControlPlaneJSON.issued_service_identity(%{
            service_identity: issued_service_identity,
            api_token: api_token
          })
      })
    end
  end
end
