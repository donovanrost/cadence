defmodule CadenceWeb.OperatorEntryController do
  use CadenceWeb, :controller

  alias CadenceWeb.AuthenticatedEntry

  def show(conn, _params) do
    redirect(conn, to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
  end
end
