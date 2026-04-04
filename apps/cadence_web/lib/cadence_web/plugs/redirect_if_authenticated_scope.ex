defmodule CadenceWeb.Plugs.RedirectIfAuthenticatedScope do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_scope: nil}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> redirect(to: "/operator")
    |> halt()
  end
end
