defmodule CadenceWeb.SetupController do
  use CadenceWeb, :controller

  alias CadenceWeb.AuthenticatedEntry

  def show(conn, _params) do
    if AuthenticatedEntry.setup_access?(conn.assigns.current_scope) do
      render(conn, :show)
    else
      redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    end
  end
end
