defmodule CadenceWeb.OrganizationController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneAccess, ControlPlaneJSON}

  def show(conn, %{"organization_id" => organization_id}) do
    with {:ok, organization} <-
           ControlPlaneAccess.authorize_organization(
             conn.assigns.current_scope,
             organization_id,
             :read_organization
           ) do
      json(conn, %{data: ControlPlaneJSON.organization(organization)})
    end
  end
end
