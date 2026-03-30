defmodule CadenceWeb.Endpoint do
  use CadenceWeb, :endpoint

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug CadenceWeb.Router
end
