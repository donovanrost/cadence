defmodule CadenceWeb.Console.SignInController do
  @moduledoc """
  L5 JSON sign-in for the console (`POST /api/console/v1/auth/sign-in`). The single login path
  (`/console/sign-in`): email and password, throttled by the attempt limit, one answer for any
  wrong pair. Contract: docs/apogee/api/session.md §Sign-in and invitation links.
  """

  use CadenceWeb, :controller

  alias CadenceWeb.AdminMode
  alias CadenceWeb.Console.Problem

  @default_target "/console"

  def create(conn, %{"email" => email, "password" => password} = params)
      when is_binary(email) and is_binary(password) do
    case Cadence.Auth.sign_in(email, password, ip: conn.remote_ip) do
      {:ok, issued} ->
        target = return_target(params["return_to"], get_session(conn, :user_return_to))

        conn
        |> start_session(issued)
        |> json(%{data: %{redirect_to: target}})

      {:error, {:too_many_attempts, retry_after}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> Problem.respond(:too_many_attempts, %{retry_after: retry_after})

      {:error, _wrong_pair_unknown_or_disabled} ->
        Problem.respond(conn, :credentials_incorrect)
    end
  end

  def create(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{email: "is required", password: "is required"})

  @doc """
  A fresh session (against fixation) holding the issued token, its organization and, for the
  environment admin, admin mode. The CSRF token changes with it: the client refetches `/session`.
  """
  def start_session(conn, issued) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_session_token, issued.session_token)
    |> put_organization(Map.get(issued, :current_organization_id))
    |> put_admin_mode(Map.get(issued, :admin_mode?, false))
  end

  @doc "Where to go after signing in: a same-origin relative path only, else the console home."
  @spec return_target(term(), term()) :: binary()
  def return_target(requested, stored) do
    cond do
      safe_path?(requested) -> requested
      safe_path?(stored) -> stored
      true -> @default_target
    end
  end

  defp safe_path?(path) when is_binary(path) and byte_size(path) in 1..2048 do
    uri = URI.parse(path)

    String.starts_with?(path, "/") and not String.starts_with?(path, "//") and
      not String.contains?(path, ["\\", "\n", "\r", "\t"]) and is_nil(uri.scheme) and
      is_nil(uri.host) and not auth_page?(uri.path || "")
  end

  defp safe_path?(_path), do: false

  # Never back to a sign-in or invitation page.
  defp auth_page?(path),
    do:
      Enum.any?(
        ~w(/sign-in /console/sign-in /invitations /console/invitations),
        &String.starts_with?(path, &1)
      )

  defp put_organization(conn, id) when is_binary(id),
    do: put_session(conn, :current_organization_id, id)

  defp put_organization(conn, _none), do: conn

  defp put_admin_mode(conn, true),
    do: put_session(conn, :admin_mode_expires_at, AdminMode.expires_at())

  defp put_admin_mode(conn, _false), do: conn
end
