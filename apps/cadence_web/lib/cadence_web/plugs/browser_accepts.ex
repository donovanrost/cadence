defmodule CadenceWeb.Plugs.BrowserAccepts do
  @moduledoc false

  @json_prefixes ["/api/cadence/application-host/v1/", "/api/cadence/contact-workspace/v1/"]

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: request_path} = conn, _opts) do
    formats = if String.starts_with?(request_path, @json_prefixes), do: ["json"], else: ["html"]
    Phoenix.Controller.accepts(conn, formats)
  end
end
