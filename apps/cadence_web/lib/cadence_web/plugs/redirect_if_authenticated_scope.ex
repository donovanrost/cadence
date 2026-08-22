defmodule CadenceWeb.Plugs.RedirectIfAuthenticatedScope do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias CadenceWeb.AuthenticatedEntry

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_scope: nil}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> redirect(to: AuthenticatedEntry.entry_path(conn.assigns.current_scope))
    |> halt()
  end
end
