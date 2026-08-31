defmodule CadenceWeb.Plugs.BrowserAccepts do
  @moduledoc false

  @host_prefix "/api/cadence/application-host/v1/"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: request_path} = conn, _opts) do
    formats = if String.starts_with?(request_path, @host_prefix), do: ["json"], else: ["html"]
    Phoenix.Controller.accepts(conn, formats)
  end
end
