import Config

# #242: the console e2e personas' password set (Cadence.Accounts.FixturePasswords, compiled only
# for dev and test) is inert unless this is true. Never in prod.exs or runtime.exs.
config :cadence, :fixture_passwords, true

config :cadence, :opportunity_capability_secret, "cadence-test-opportunity-capability-secret-2026"

# No disksup under test: the host's own disk would raise the journal-disk item and start early
# reclaims in every suite. Tests give the reading themselves (Cadence.IngressJournal.Volume).
config :os_mon, start_disksup: false

config :cadence, Cadence.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  # The partition suffix is runtime config (runtime.exs, #50): compile-time config stays stable, so
  # switching MIX_TEST_PARTITION doesn't recompile the whole app.
  database: "cadence_test",
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

# The journal is on by default (DECISIONS #95, config.exs). CADENCE_TEST_INGRESS_JOURNAL=off runs the
# suite with it off, the still-supported path; CI reruns the :ingest_journal_matrix tests that way.
config :cadence,
  ingress_journal: [
    enabled?: System.get_env("CADENCE_TEST_INGRESS_JOURNAL", "on") != "off",
    # base_path is per OS process and partition: set in runtime.exs (#50).
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
    # The Postgres read model, except while a test turns on an outage (DECISIONS #71).
    writer: Cadence.OutageTelemetryWriter,
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

# Provider HTTP calls refuse private and reserved networks (OutboundGuard, api-ops 11-15); this
# environment allows loopback only, for the local simulator. Production allows nothing extra.
config :cadence, :provider_outbound,
  allow: ["127.0.0.1/32", "::1/128"],
  # The suite's fake provider hosts (*.test) resolve to loopback; answers are still checked.
  resolver: {Cadence.TestSupport.ProviderHosts, :resolve}

# Env-backed credentials (local only): variable names any organization may use here, beyond its
# own CADENCE_TENANT_<ORG>_ prefix (EnvBackend, api-ops 11-15). Anything else is refused on save
# and on resolve.
config :cadence, :env_credentials,
  allow: [
    "EARENDIL_DEMO_PROVIDER_TOKEN",
    "CADENCE_PROVIDER_ACCOUNT_TOKEN",
    "PROVIDER_TEST_TOKEN",
    "CADENCE_PROVIDER_TEST_TOKEN"
  ],
  allow_prefixes: ["CADENCE_TEST_"]

# The console federation smoke's test-only application (Cadence.Applications.FixtureContributors;
# never set in dev or prod, a guard test checks).
config :cadence, :fixture_application_contributors, [
  Cadence.TestSupport.SurfaceFixtureApplication
]

# Retention sweepers (#694) are exercised directly in their tests: no timers in the suite.
config :cadence, :retention, enabled?: false

# The watermark coalescer's own timer cannot use a test's sandbox connection: tests flush through
# a watermark read or `WatermarkCoalescer.flush/0`.
config :cadence, :source_watermark_coalescing, interval_ms: :infinity
