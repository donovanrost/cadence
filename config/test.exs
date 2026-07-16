import Config

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cadence_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5_000,
  queue_interval: 10_000

config :cadence, start_background_jobs: false
config :cadence, contact_scheduler: [enabled: false]
config :cadence, contact_scheduler_global_safety: [enabled: false]
config :cadence, provider_reservation_reconciler: [enabled: false]
config :cadence, provider_event_ingestion: [enabled: false]
config :cadence, provider_local_credentials: [enabled: true]
config :cadence, command_dispatcher: [enabled: false]
config :cadence, command_verifier_scheduler: [enabled: false]
config :cadence, password_hash_iterations: 1_000
config :cadence, ingress_archive: [module: Cadence.IngressArchive.Postgres]
config :cadence, protocol_record_archive: [module: Cadence.Protocol.RecordArchive.Postgres]

config :cadence,
  telemetry_current_value_store: [module: Cadence.Telemetry.CurrentValueStore.Postgres]

config :cadence,
  telemetry_storage: [
    writer: Cadence.Telemetry.Storage.Writers.PostgresReadModel,
    organization_id: "org-test",
    realm: :flight,
    data_source_id: "managed_questdb_primary",
    binding_id: "default_flight_telemetry"
  ]

config :cadence, telemetry_history_store: [module: Cadence.Telemetry.HistoryStore.Postgres]

config :cadence, dashboard_data_sources: [persisted?: false, bootstrap_defaults?: false]

config :cadence, dashboard_source_circuit_breaker: [enabled?: false]
config :cadence, dashboard_source_health_events: [enabled?: false]
config :cadence, dashboard_source_probe_scheduler: [enabled?: false]
config :cadence, dashboard_source_watermark_events: [enabled?: false]

config :cadence_web, CadenceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4101],
  server: false,
  secret_key_base: String.duplicate("1", 64)

config :cadence_web, CadenceWeb.Mailer, adapter: Swoosh.Adapters.Test
config :cadence_web, dashboard_live_refresh_ms: 60_000

config :cadence_web,
  dashboard_engine_source_execution: [
    source_execution_max_concurrency: 1,
    source_execution_timeout_ms: :infinity
  ]

config :logger, level: :warning
