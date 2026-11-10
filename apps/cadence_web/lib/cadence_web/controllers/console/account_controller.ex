defmodule CadenceWeb.Console.AccountController do
  @moduledoc """
  The signed-in user's own password and sessions under `/api/console/v1/account`.
  Contract: docs/apogee/api/session.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Accounts.AccountSecurity
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def change_password(conn, params) do
    case AccountSecurity.change_password(user(conn), token(conn), params) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, {:invalid, details}} ->
        Problem.respond(conn, :invalid_params, details)

      {:error, :invalid_credentials} ->
        Problem.respond(conn, :current_password_incorrect)

      {:error, :password_managed_externally} ->
        Problem.respond(conn, :password_managed_externally)

      {:error, _reason} ->
        Problem.respond(conn, :invalid_params)
    end
  end

  def sessions(conn, _params) do
    sessions = AccountSecurity.list_sessions(user(conn).user_id, token(conn))
    json(conn, %{data: ConfigJSON.encode(%{sessions: sessions})})
  end

  def revoke_others(conn, _params) do
    count = AccountSecurity.revoke_others(user(conn).user_id, token(conn))
    json(conn, %{data: %{revoked: count}})
  end

  def revoke_session(conn, %{"session_id" => session_id}) do
    current? =
      Enum.any?(
        AccountSecurity.list_sessions(user(conn).user_id, token(conn)),
        &(&1.id == session_id and &1.current)
      )

    case AccountSecurity.revoke_session(user(conn).user_id, session_id) do
      # Revoking the session you're using signs you out here too.
      :ok when current? -> conn |> configure_session(drop: true) |> send_resp(:no_content, "")
      :ok -> send_resp(conn, :no_content, "")
      {:error, :session_not_found} -> Problem.respond(conn, :session_not_found)
    end
  end

  defp user(conn), do: conn.assigns.current_scope.user
  defp token(conn), do: conn.assigns.console_credentials.session_token
end
