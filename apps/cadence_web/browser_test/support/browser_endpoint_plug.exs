defmodule CadenceWeb.Assets.BrowserEndpointPlug do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    router_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"

    conn
    |> Phoenix.Controller.put_router_url(router_url)
    |> CadenceWeb.Endpoint.call(opts)
  end
end
