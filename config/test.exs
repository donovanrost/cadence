import Config

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cadence_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :cadence, start_background_jobs: false
config :cadence, contact_scheduler: [enabled: false]
config :cadence, command_dispatcher: [enabled: false]
config :cadence, command_verifier_scheduler: [enabled: false]
config :cadence, ingress_archive: [module: Cadence.IngressArchive.Postgres]
config :cadence, protocol_record_archive: [module: Cadence.Protocol.RecordArchive.Postgres]

config :cadence,
  telemetry_current_value_store: [module: Cadence.Telemetry.CurrentValueStore.Postgres]

config :cadence, telemetry_history_store: [module: Cadence.Telemetry.HistoryStore.Postgres]

config :cadence_web, CadenceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  server: false,
  secret_key_base: String.duplicate("1", 64)

config :logger, level: :warning
