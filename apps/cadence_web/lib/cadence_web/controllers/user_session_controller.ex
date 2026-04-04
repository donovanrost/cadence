defmodule CadenceWeb.UserSessionController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def new(conn, _params) do
    render_sign_in(conn, sign_in_form(), nil)
  end

  def create(conn, params) do
    case session_params(params) do
      {:ok, session_params} ->
        form = sign_in_form(session_params)

        with {:ok, {email, password}} <-
               ControlPlaneParams.setup_access_session(session_params),
             {:ok, issued_session} <- Cadence.login_bootstrap_admin(email, password) do
          conn
          |> renew_browser_session()
          |> put_session(:user_session_token, issued_session.session_token)
          |> put_flash(:info, "Setup access session established.")
          |> redirect(to: redirect_target(conn, issued_session.user))
        else
          {:error, reason} ->
            conn
            |> put_status(error_status(reason))
            |> render_sign_in(form, error_message(reason))
        end

      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> render_sign_in(sign_in_form(), error_message(reason))
    end
  end

  def delete(conn, _params) do
    revoke_session_token(conn)

    conn
    |> renew_browser_session()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: "/sign-in")
  end

  defp render_sign_in(conn, form, error_message) do
    render(conn, :new,
      form: form,
      error_message: error_message,
      setup_access_enabled?: Cadence.bootstrap_admin_enabled?()
    )
  end

  defp sign_in_form(params \\ %{}) do
    to_form(params, as: :setup_access_session)
  end

  defp session_params(params) do
    case Map.get(params, "setup_access_session", Map.get(params, "bootstrap_admin_session", %{})) do
      nil -> {:ok, %{}}
      session_params when is_map(session_params) -> {:ok, session_params}
      _other -> {:error, :invalid_sign_in_payload}
    end
  end

  defp redirect_target(conn, user) do
    conn
    |> get_session(:user_return_to)
    |> AuthenticatedEntry.redirect_path(user)
  end

  defp error_status(:bootstrap_admin_disabled), do: :forbidden
  defp error_status(_reason), do: :unprocessable_entity

  defp error_message(:invalid_sign_in_payload) do
    "Submit a valid setup access sign-in form."
  end

  defp error_message(:bootstrap_admin_disabled) do
    "Temporary setup access is disabled for this deployment."
  end

  defp error_message(:invalid_credentials) do
    "The supplied email or password was rejected."
  end

  defp error_message({:invalid_param, _field, _reason}) do
    "Enter both email and password."
  end

  defp error_message(_reason) do
    "Cadence could not establish a browser session."
  end

  defp revoke_session_token(conn) do
    case get_session(conn, :user_session_token) do
      session_token when is_binary(session_token) ->
        Cadence.revoke_bootstrap_admin_session(session_token)

      _other ->
        :ok
    end
  end

  defp renew_browser_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
