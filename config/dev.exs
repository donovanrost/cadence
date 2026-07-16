import Config

config :cadence, provider_local_credentials: [enabled: true]

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cadence_dev",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool_size: 10

config :cadence_web, CadenceWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4001],
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:cadence_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:cadence_web, ~w(--watch)]}
  ]
