defmodule CadenceWeb.Plugs.PreserveRequestMethod do
  @moduledoc false

  @behaviour Plug

  alias Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Conn{} = conn, _opts), do: Conn.assign(conn, :original_method, conn.method)
end
