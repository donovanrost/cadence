import Config

config :cadence, :opportunity_capability_secret, "cadence-dev-opportunity-capability-secret-2026"

config :cadence, provider_local_credentials: [enabled: true]

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: System.get_env("CADENCE_DEV_DATABASE", "cadence_dev"),
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  pool_size: 10

# Provider HTTP calls refuse private and reserved networks (OutboundGuard, api-ops 11-15); this
# environment allows loopback only, for the local simulator. Production allows nothing extra.
config :cadence, :provider_outbound, allow: ["127.0.0.1/32", "::1/128"]
