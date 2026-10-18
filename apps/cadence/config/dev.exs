import Config

config :cadence, :opportunity_capability_secret, "cadence-dev-opportunity-capability-secret-2026"

config :cadence, provider_local_credentials: [enabled: true]

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cadence_dev",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool_size: 10
