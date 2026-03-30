defmodule CadenceWeb.BootstrapAdminSessionController do
  use CadenceWeb, :controller

  action_fallback CadenceWeb.FallbackController

  alias CadenceWeb.{ControlPlaneJSON, ControlPlaneParams}

  def create(conn, %{"bootstrap_admin_session" => session_params}) do
    with {:ok, {email, password}} <- ControlPlaneParams.bootstrap_admin_session(session_params),
         {:ok, issued_session} <- Cadence.login_bootstrap_admin(email, password) do
      conn
      |> put_status(:created)
      |> json(%{data: ControlPlaneJSON.bootstrap_admin_session(issued_session)})
    end
  end
end
