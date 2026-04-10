defmodule CadenceWeb.UserSessionController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry
  alias CadenceWeb.ControlPlaneParams

  def new(conn, _params) do
    render_sign_in(conn, durable_form(), setup_access_form(), nil, nil)
  end

  def create(conn, params) do
    cond do
      Map.has_key?(params, "durable_session") ->
        create_durable_session(conn, Map.get(params, "durable_session"))

      Map.has_key?(params, "setup_access_session") or
          Map.has_key?(params, "bootstrap_admin_session") ->
        create_setup_access_session(
          conn,
          Map.get(params, "setup_access_session", Map.get(params, "bootstrap_admin_session"))
        )

      true ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_sign_in(
          durable_form(),
          setup_access_form(),
          "Submit a valid sign-in form.",
          nil
        )
    end
  end

  def delete(conn, _params) do
    revoke_session_token(conn)

    conn
    |> renew_browser_session()
    |> put_flash(:info, "Session closed.")
    |> redirect(to: "/sign-in")
  end

  defp create_durable_session(conn, session_params) when is_map(session_params) do
    form = durable_form(session_params)

    with {:ok, {email, password}} <- ControlPlaneParams.durable_session(session_params),
         {:ok, issued_session} <- Cadence.login_user(email, password) do
      finalize_sign_in(conn, issued_session, "Signed in.")
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> render_sign_in(form, setup_access_form(), error_message(reason), nil)
    end
  end

  defp create_durable_session(conn, _invalid_params) do
    conn
    |> put_status(:unprocessable_entity)
    |> render_sign_in(
      durable_form(),
      setup_access_form(),
      "Submit a valid operator sign-in form.",
      nil
    )
  end

  defp create_setup_access_session(conn, session_params) when is_map(session_params) do
    form = setup_access_form(session_params)

    with {:ok, {email, password}} <- ControlPlaneParams.setup_access_session(session_params),
         {:ok, issued_session} <- Cadence.login_bootstrap_admin(email, password) do
      finalize_sign_in(conn, issued_session, "Setup access session established.")
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> render_sign_in(durable_form(), form, nil, error_message(reason))
    end
  end

  defp create_setup_access_session(conn, _invalid_params) do
    conn
    |> put_status(:unprocessable_entity)
    |> render_sign_in(
      durable_form(),
      setup_access_form(),
      nil,
      "Submit a valid setup access sign-in form."
    )
  end

  defp finalize_sign_in(conn, issued_session, flash_message) do
    conn
    |> renew_browser_session()
    |> put_session(:user_session_token, issued_session.session_token)
    |> maybe_put_current_organization(issued_session.current_organization_id)
    |> put_flash(:info, flash_message)
    |> redirect(to: redirect_target(conn, issued_session))
  end

  defp render_sign_in(
         conn,
         durable_form,
         setup_access_form,
         durable_error_message,
         setup_access_error_message
       ) do
    render(conn, :new,
      durable_form: durable_form,
      durable_error_message: durable_error_message,
      setup_access_form: setup_access_form,
      setup_access_error_message: setup_access_error_message,
      setup_access_available?: setup_access_available?()
    )
  end

  defp durable_form(params \\ %{}) do
    to_form(params, as: :durable_session)
  end

  defp setup_access_form(params \\ %{}) do
    to_form(params, as: :setup_access_session)
  end

  defp setup_access_available? do
    Cadence.initial_setup_pending?() and Cadence.bootstrap_admin_enabled?()
  end

  defp redirect_target(conn, issued_session) do
    current_scope =
      case Cadence.authenticate_api_token(issued_session.session_token,
             current_organization_id: issued_session.current_organization_id
           ) do
        {:ok, %Scope{} = current_scope} -> current_scope
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

  defp error_status(:bootstrap_admin_disabled), do: :forbidden
  defp error_status(_reason), do: :unprocessable_entity

  defp error_message(:bootstrap_admin_disabled) do
    "Temporary setup access is disabled for this deployment."
  end

  defp error_message(:invalid_credentials) do
    "The supplied email or password was rejected."
  end

  defp error_message({:invalid_param, _field, :required}) do
    "Enter both email and password."
  end

  defp error_message(_reason) do
    "Cadence could not establish a browser session."
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
end
