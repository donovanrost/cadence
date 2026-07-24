defmodule CadenceWeb.OrganizationController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.API.IdentityJSON, as: IdentityJSON

  alias CadenceWeb.ControlPlaneAccess

  def show(conn, %{"organization_id" => organization_id}) do
    with {:ok, organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :read_organization
           ) do
      json(conn, %{data: IdentityJSON.organization(organization)})
    end
  end
end
