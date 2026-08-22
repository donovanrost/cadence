import Config

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 4,
    source_execution_timeout_ms: 15_000
  ]

config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4001],
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cadence_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]
