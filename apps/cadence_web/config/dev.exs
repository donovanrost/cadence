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

# Dev only: /dev/mailbox (HTML and /json) shows the mail the Local adapter holds, so a seed that
# works through the public API can read an invitation link, as a person would from their inbox.
# The router compiles the route in only when this is true; test and prod leave it off (#745).
config :cadence_web, :dev_routes, true

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 4,
    source_execution_timeout_ms: 15_000
  ]

dev_port = String.to_integer(System.get_env("PORT", "4001"))

# CADENCE_CI_SERVER=1: the console-e2e CI server only. No code reloader and no Vite or Tailwind
# watchers. Under concurrent requests the reloader raced Mix's project loading ("Trying to load
# XTCE.MixProject ... another project with the same name was already defined", run 44741752992),
# and CI serves built assets anyway. Inert unless set, so local dev is unchanged. `code_reloader`
# is read at compile time: set it before compiling.
ci_server? = System.get_env("CADENCE_CI_SERVER") in ["1", "true"]

# The Tidewave dev toolbar, not on the CI server: it loads from tidewave.ai into every page and
# scans the DOM, which the console's fleet-scale budgets were timing (#867). The endpoint reads it
# with Application.compile_env: a build compiled under the other setting fails the boot-time
# compile-env check (as code_reloader does), so set CADENCE_CI_SERVER before compiling.
config :cadence_web, :tidewave?, not ci_server?

config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "127.0.0.1"],
  check_origin: ["//localhost:#{dev_port}", "//127.0.0.1:#{dev_port}"],
  http: [ip: {127, 0, 0, 1}, port: dev_port],
  code_reloader: not ci_server?,
  reloadable_apps: [:cadence, :cadence_catalog, :ccsds, :xtce, :cadence_web],
  debug_errors: true,
  watchers:
    if(ci_server?,
      do: [],
      else: [
        vite: {PhoenixVite.Npm, :run, [:vite, ~w(dev)]},
        tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
      ]
    )

# #780: the development ingest routes exist in dev and test only; prod never sets this.
config :cadence_web, :dev_ingest_routes, true
