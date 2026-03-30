defmodule CadenceWeb.CurrentScopeController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    json(conn, %{data: CadenceWeb.ControlPlaneJSON.current_scope(conn.assigns.current_scope)})
  end
end
