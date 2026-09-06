import Config

config :live_vue, vite_host: "http://127.0.0.1:5173"

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 4,
    source_execution_timeout_ms: 15_000
  ]

config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "127.0.0.1"],
  check_origin: ["//localhost:4001", "//127.0.0.1:4001"],
  http: [ip: {127, 0, 0, 1}, port: 4001],
  code_reloader: true,
  debug_errors: true,
  watchers: [
    vite: {PhoenixVite.Npm, :run, [:vite, ~w(dev)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]
