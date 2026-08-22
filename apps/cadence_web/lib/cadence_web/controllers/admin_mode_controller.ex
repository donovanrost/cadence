defmodule CadenceWeb.AdminModeController do
  use CadenceWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Auth.Scope
  alias CadenceWeb.AdminMode

  def new(conn, _params) do
    if Scope.platform_admin_eligible?(conn.assigns.current_scope) do
      conn
      |> put_layout(html: {CadenceWeb.Layouts, :auth})
      |> assign(:form, to_form(%{"password" => ""}, as: :admin_mode))
      |> render(:new)
    else
      conn
      |> put_flash(:error, "Your account is not eligible for platform administration.")
      |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"admin_mode" => %{"password" => password}})
      when is_binary(password) do
    current_scope = conn.assigns.current_scope

    with true <- Scope.platform_admin_eligible?(current_scope),
         :ok <- Cadence.Auth.verify_user_password(current_scope.user, password) do
      conn
      |> put_session(:admin_mode_expires_at, AdminMode.expires_at())
      |> put_flash(:info, "Admin mode enabled.")
      |> redirect(to: ~p"/admin")
    else
      false ->
        conn
        |> put_flash(:error, "Your account is not eligible for platform administration.")
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "The supplied password was rejected.")
        |> redirect(to: ~p"/admin-mode")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Enter your password to enable admin mode.")
    |> redirect(to: ~p"/admin-mode")
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:admin_mode_expires_at)
    |> put_flash(:info, "Admin mode disabled.")
    |> redirect(to: ~p"/")
  end
end
