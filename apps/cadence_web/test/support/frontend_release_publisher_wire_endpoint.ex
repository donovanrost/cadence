defmodule CadenceWeb.FrontendReleasePublisherWireTestEndpoint do
  @moduledoc false

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.put_private(
      :frontend_release_publisher_config,
      Keyword.fetch!(opts, :publisher_config)
    )
    |> CadenceWeb.Endpoint.call([])
  end
end
