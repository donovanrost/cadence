defmodule CadenceWeb.AdminModeController do
  use CadenceWeb, :controller

  import Phoenix.LiveView.Controller, only: [live_render: 3]

  alias Cadence.Auth.Scope
  alias CadenceWeb.AdminMode
  alias CadenceWeb.AdminModeLive.Presentation

  def new(conn, _params) do
    if Scope.platform_admin_eligible?(conn.assigns.current_scope) do
      conn
      |> put_layout(html: {CadenceWeb.Layouts, :auth})
      |> live_render(CadenceWeb.AdminModeLive,
        session: live_session(conn, Presentation.build()),
        container: {:div, class: "contents"}
      )
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

  defp live_session(conn, presentation) do
    %{
      "admin_mode_expires_at" => get_session(conn, :admin_mode_expires_at),
      "current_organization_id" => get_session(conn, :current_organization_id),
      "user_session_token" => get_session(conn, :user_session_token),
      "presentation" => presentation
    }
  end
end
