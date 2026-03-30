defmodule CadenceWeb.Plugs.RequireCurrentScope do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_scope: nil}} = conn, _opts) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{errors: [%{reason: "unauthenticated"}]})
    |> halt()
  end

  def call(conn, _opts), do: conn
end
