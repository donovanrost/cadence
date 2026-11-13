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
end
