import Config

# #242: the console e2e personas' password set (Cadence.Accounts.FixturePasswords, compiled only
# for dev and test) is inert unless this is true. Never in prod.exs or runtime.exs.
config :cadence, :fixture_passwords, true

config :cadence, :opportunity_capability_secret, "cadence-dev-opportunity-capability-secret-2026"

config :cadence, provider_local_credentials: [enabled: true]

# The journal shares the host's disk here (mostly not ours): its alert (ux U66) and early reclaim
# act only near a genuinely full disk, with under 10 GiB free (lead 11-15). Defaults (70/90/60,
# reclaim 80 -> 70, no floor) are for a disk of its own.
config :cadence, :ingress_journal,
  disk_caution: 0.95,
  disk_critical: 0.97,
  disk_clear: 0.93,
  early_reclaim_at: 0.97,
  early_reclaim_to: 0.95,
  disk_emergency_free_bytes: 10 * 1_024 * 1_024 * 1_024

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

# Env-backed credentials (local only): variable names any organization may use here, beyond its
# own CADENCE_TENANT_<ORG>_ prefix (EnvBackend, api-ops 11-15). Anything else is refused on save
# and on resolve.
config :cadence, :env_credentials,
  allow: ["EARENDIL_DEMO_PROVIDER_TOKEN"],
  allow_prefixes: []

# The dev store keeps two days of observations: Cadence's own retention job now drops the rest.
config :cadence, :telemetry_observation_retention, enabled?: true, retention_days: 2
