defmodule CadenceWeb.BootstrapAdminSessionController do
  use CadenceWeb, :controller

  alias CadenceWeb.API.IdentityJSON, as: IdentityJSON

  alias CadenceWeb.API.IdentityParams, as: IdentityParams

  action_fallback CadenceWeb.FallbackController

  def create(conn, %{"bootstrap_admin_session" => session_params}) do
    with {:ok, {email, password}} <-
           IdentityParams.bootstrap_admin_session(session_params),
         {:ok, issued_session} <- Cadence.Auth.login_bootstrap_admin(email, password) do
      conn
      |> put_status(:created)
      |> json(%{data: IdentityJSON.bootstrap_admin_session(issued_session)})
    end
  end
end
