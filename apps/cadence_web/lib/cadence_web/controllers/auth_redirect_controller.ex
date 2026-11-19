defmodule CadenceWeb.AuthRedirectController do
  @moduledoc """
  L5: the old auth pages' GETs (`/sign-in`, `/invitations/:token`, `/no-organization`) send the
  browser to the console's (`/console/...`), so emailed links and bookmarks keep working. Only
  `return_to` is carried to sign-in; the console checks it (same-origin relative paths only).
  """

  use CadenceWeb, :controller

  def sign_in(conn, params) do
    query =
      case params["return_to"] do
        path when is_binary(path) and path != "" ->
          "?" <> URI.encode_query(%{"return_to" => path})

        _none ->
          ""
      end

    redirect(conn, to: "/console/sign-in" <> query)
  end

  def invitation(conn, %{"invitation_token" => token}),
    do: redirect(conn, to: "/console/invitations/" <> URI.encode(token, &URI.char_unreserved?/1))

  def no_organization(conn, _params), do: redirect(conn, to: "/console/no-organization")

  @doc "L21: the old notifications page; invitations are on the console's Account page."
  def notifications(conn, _params), do: redirect(conn, to: "/console/account")

  @doc "L6: the old admin-mode page; the console's account menu holds admin mode now."
  def admin_mode(conn, _params), do: redirect(conn, to: "/console")

  @doc "A legacy sign-in form POSTed from an old tab: 303 to the console's sign-in (DECISIONS #79)."
  def sign_in_form(conn, _params),
    do: conn |> put_status(:see_other) |> redirect(to: "/console/sign-in")

  @doc "A legacy invitation form POSTed from an old tab: 303 to the console's invitation page."
  def invitation_form(conn, %{"invitation_token" => token}),
    do:
      conn
      |> put_status(:see_other)
      |> redirect(to: "/console/invitations/" <> URI.encode(token, &URI.char_unreserved?/1))
end
