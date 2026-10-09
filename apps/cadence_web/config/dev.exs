import Config

config :live_vue, vite_host: "http://127.0.0.1:5173"

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
  reloadable_apps: [:cadence, :cadence_web],
  debug_errors: true,
  watchers: [
    vite: {PhoenixVite.Npm, :run, [:vite, ~w(dev)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]
