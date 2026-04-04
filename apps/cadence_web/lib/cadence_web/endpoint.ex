defmodule CadenceWeb.Endpoint do
  use CadenceWeb, :endpoint

  @session_options [
    store: :cookie,
    key: "_cadence_web_key",
    signing_salt: "browser-auth",
    same_site: "Lax"
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Static,
    at: "/",
    from: :cadence_web,
    gzip: false,
    only: CadenceWeb.static_paths()

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.Session, @session_options
  plug Plug.MethodOverride
  plug Plug.Head
  plug CadenceWeb.Router
end
