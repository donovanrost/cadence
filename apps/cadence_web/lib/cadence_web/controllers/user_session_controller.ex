defmodule CadenceWeb.UserSessionController do
  use CadenceWeb, :controller

  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def create(conn, %{"user" => credentials}) when is_map(credentials) do
    with {:ok, {email, password}} <- ControlPlaneParams.durable_session(credentials),
         {:ok, issued_session} <- Cadence.sign_in(email, password) do
      finalize_sign_in(conn, issued_session)
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, human_message(reason))
        |> redirect(to: ~p"/sign-in")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Submit a valid sign-in form.")
    |> redirect(to: ~p"/sign-in")
  end

  def delete(conn, _params) do
    revoke_session_token(conn)

    conn
    |> renew_browser_session()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: ~p"/sign-in")
  end

  defp finalize_sign_in(conn, issued_session) do
    conn
    |> renew_browser_session()
    |> put_session(:user_session_token, issued_session.session_token)
    |> maybe_put_current_organization(issued_session.current_organization_id)
    |> put_flash(:info, "Signed in.")
    |> redirect(to: redirect_target(conn, issued_session))
  end

  defp redirect_target(conn, issued_session) do
    current_scope =
      case Cadence.authenticate_api_token(issued_session.session_token,
             current_organization_id: issued_session.current_organization_id
           ) do
        {:ok, %Scope{} = scope} -> scope
        {:error, _reason} -> issued_session.user
      end

    conn
    |> get_session(:user_return_to)
    |> AuthenticatedEntry.redirect_path(current_scope)
  end

  defp maybe_put_current_organization(conn, organization_id) when is_binary(organization_id) do
    put_session(conn, :current_organization_id, organization_id)
  end

  defp maybe_put_current_organization(conn, _other) do
    delete_session(conn, :current_organization_id)
  end

  defp revoke_session_token(conn) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        Cadence.revoke_user_session(session_token)

      _other ->
        :ok
    end
  end

  defp renew_browser_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp human_message(:invalid_credentials), do: "The supplied email or password was rejected."

  defp human_message({:invalid_param, _field, :required}),
    do: "Enter both email and password."

  defp human_message(_reason), do: "Cadence could not establish a browser session."
end
