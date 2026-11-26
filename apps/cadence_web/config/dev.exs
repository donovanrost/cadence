import Config

# CADENCE_LIVE_VUE_VITE_PORT (default 5173) must match the port vite.config.mjs
# binds, so each worktree's LiveView pages load their own Vite dev server.
config :live_vue,
  vite_host: "http://127.0.0.1:#{System.get_env("CADENCE_LIVE_VUE_VITE_PORT", "5173")}"

# Apogee console SPA: in dev, Phoenix serves /console by fetching index.html
# from the console's Vite dev server (frontend/apps/console). Set
# CONSOLE_VITE_ORIGIN="" to serve the built priv/static/console instead.
config :cadence_web, :console,
  dev_server:
    (case System.get_env("CONSOLE_VITE_ORIGIN", "http://127.0.0.1:5181") do
       "" -> nil
       url -> url
     end)

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 4,
    source_execution_timeout_ms: 15_000
  ]

dev_port = String.to_integer(System.get_env("PORT", "4001"))

config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "127.0.0.1"],
  check_origin: ["//localhost:#{dev_port}", "//127.0.0.1:#{dev_port}"],
  http: [ip: {127, 0, 0, 1}, port: dev_port],
  code_reloader: true,
  reloadable_apps: [:cadence, :cadence_catalog, :ccsds, :xtce, :cadence_web],
  debug_errors: true,
  watchers: [
    vite: {PhoenixVite.Npm, :run, [:vite, ~w(dev)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]

# #780: the development ingest routes exist in dev and test only; prod never sets this.
config :cadence_web, :dev_ingest_routes, true
