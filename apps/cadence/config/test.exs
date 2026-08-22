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
config :cadence, control_supervisor: [start_mission_recovery?: false]

config :cadence, :event_bus,
  delivery: :sync,
  before_notify: {Ecto.Adapters.SQL.Sandbox, :allow, [Cadence.Repo]}

config :cadence, contact_scheduler: [enabled: false]
config :cadence, contact_scheduler_global_safety: [enabled: false]
config :cadence, provider_reservation_reconciler: [enabled: false]
config :cadence, provider_event_ingestion: [enabled: false]
config :cadence, provider_local_credentials: [enabled: true]
config :cadence, command_dispatcher: [enabled: false]
config :cadence, command_verifier_scheduler: [enabled: false]
config :cadence, password_hash_iterations: 1_000

config :cadence,
  ingress_journal: [
    enabled?: true,
    base_path:
      Path.join(
        System.tmp_dir!(),
        "cadence-ingress-journal-test-#{System.pid()}-#{System.get_env("MIX_TEST_PARTITION", "0")}"
      ),
    max_bytes: 64 * 1_024 * 1_024,
    segment_bytes: 1 * 1_024 * 1_024,
    capture_record_bytes: 256 * 1_024,
    processing_max_batch_entries: 1,
    processing_max_batch_bytes: 256 * 1_024,
    durability: :page_cache,
    checkpoint_interval_ms: 25,
    consumers: [:processing, :archive]
  ]

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

config :cadence, data_sources: [persisted?: false, bootstrap_defaults?: false]

config :cadence, dashboard_source_circuit_breaker: [enabled?: false]
config :cadence, data_source_health_events: [enabled?: false]
config :cadence, data_source_probe_scheduler: [enabled?: false]
config :cadence, data_source_watermark_events: [enabled?: false]

config :logger, level: :warning
