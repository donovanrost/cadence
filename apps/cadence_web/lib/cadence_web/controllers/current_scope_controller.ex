defmodule CadenceWeb.CurrentScopeController do
  use CadenceWeb, :controller

  alias CadenceWeb.API.IdentityJSON, as: IdentityJSON

  def show(conn, _params) do
    json(conn, %{
      data: IdentityJSON.current_scope(conn.assigns.current_scope)
    })
  end
end
