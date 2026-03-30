defmodule CadenceWeb.BootstrapController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Organizations.Organization
  alias Cadence.Auth.Policy
  alias CadenceWeb.{ControlPlaneJSON, ControlPlaneParams}

  def create(conn, %{"bootstrap" => bootstrap_params}) do
    with :ok <- Policy.authorize(conn.assigns.current_scope, :bootstrap_platform, %{}),
         {:ok, %Organization{} = organization} <-
           ControlPlaneParams.organization(Map.get(bootstrap_params, "organization", %{})),
         {:ok, %ServiceIdentity{} = service_identity} <-
           ControlPlaneParams.bootstrap_service_identity(
             organization.organization_id,
             bootstrap_params
           ),
         {:ok, mission} <-
           ControlPlaneParams.bootstrap_mission(organization.organization_id, bootstrap_params),
         {:ok, result} <- Cadence.bootstrap_organization(organization, service_identity, mission) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.bootstrap(result)})
    end
  end
end
