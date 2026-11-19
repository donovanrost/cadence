defmodule CadenceWeb.Endpoint do
  use CadenceWeb, :endpoint

  @session_options [
    store: :cookie,
    key: "_cadence_web_key",
    signing_salt: "browser-auth",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  # Apogee console SPA live data. Session-authenticated: the client sends its
  # CSRF token as the `_csrf_token` param so Phoenix exposes the cookie session.
  socket("/socket/console", CadenceWeb.ConsoleSocket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Static,
    at: "/",
    from: :cadence_web,
    gzip: false,
    only: CadenceWeb.static_paths()
  )

  # Hashed console bundles from `vite build` (frontend/apps/console). The
  # index.html is deliberately not static: CadenceWeb.Console.SPAController
  # serves it behind authentication with the CSRF token injected.
  plug(Plug.Static,
    at: "/console/assets",
    from: {:cadence_web, "priv/static/console/assets"},
    gzip: false,
    headers: %{"cache-control" => "public, max-age=31536000, immutable"}
  )

  plug(CadenceWeb.Plugs.FrontendReleasePublisher)
  plug(CadenceWeb.Plugs.FrontendReleaseRequestBody)

  if Mix.env() == :dev do
    plug(Tidewave)
  end

  # Multipart allows catalog uploads up to Cadence.Catalog.Upload.max_bytes
  # (50 MiB) plus form overhead; other parsers keep Plug's defaults.
  plug(Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 56_000_000}, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(CadenceWeb.Plugs.FrontendReleasePublisherSession, @session_options)
  plug(Plug.MethodOverride)
  plug(CadenceWeb.Plugs.PreserveRequestMethod)
  plug(Plug.Head)
  plug(CadenceWeb.Router)
end
