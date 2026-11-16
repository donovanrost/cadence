import Config

config :opentelemetry, traces_exporter: :none

# Uplink sessions are qualified only by signed provider attestations (#44 D2); without
# provider evidence a session stays blocked (fencing_unproven).
config :cadence, :uplink_session_policy, Cadence.Control.UplinkSessionQualification

config :logger, :default_formatter,
  metadata: [
    :request_id,
    :otel_trace_id,
    :otel_span_id,
    :cadence_event,
    :mission_id,
    :partition_id,
    :generation,
    :duration_ms,
    :status,
    :spacecraft_id,
    :source_endpoint_id,
    :realized_contact_id,
    :path_id,
    :provider_binding_id,
    :journal_stream_id,
    :transport_session_id,
    :previous_transport_session_id,
    :error_class
  ]

# os_mon runs for disksup only: the ingress journal reads its own disk on demand
# (Cadence.IngressJournal.Volume, ux U66). No cpu/mem/os supervisors; its periodic check is
# hourly and its almost-full alarm threshold is 100 %, so it never raises alarms of its own.
config :os_mon,
  start_cpu_sup: false,
  start_memsup: false,
  start_os_sup: false,
  start_disksup: true,
  disk_space_check_interval: 60,
  disk_almost_full_threshold: 1.0

config :cadence,
  activation_governance: [approval_required: true],
  # Mission change-set kinds (Cadence.Platform.ConfigKind), see docs/apogee/domain/change-sets.md.
  configuration_kinds: [
    Cadence.Comms.ConfigKinds.GroundStation,
    # Composition: provider-managed transports cross Ground Networks and Comms (comms parity 2).
    Cadence.Management.ConfigKinds.Transport,
    Cadence.Spacecraft.ConfigKinds.Spacecraft,
    Cadence.Spacecraft.ConfigKinds.SpacecraftProfile,
    Cadence.Spacecraft.ConfigKinds.SpacecraftOverride,
    # App configuration through change sets (DECISIONS #77): derived telemetry points.
    Cadence.Governance.DerivedTelemetryKind,
    # ... and limit definitions (DECISIONS #77, stage 2).
    Cadence.Control.LimitDefinitionKind,
    # Derived: re-materializes profile routes after the ops above (finalize/3).
    Cadence.Comms.ConfigKinds.SpacecraftRoutes,
    # Derived: framing compatibility HOLDs when the profile becomes framing authority.
    Cadence.Comms.ConfigKinds.FramingCompatibility,
    # Derived: catalog compatibility HOLDs when spacecraft move to another catalog (#36/#65).
    Cadence.Spacecraft.ConfigKinds.CatalogCompatibility,
    # Derived: commanding and telemetry switch HOLDs (L22).
    Cadence.Spacecraft.ConfigKinds.SwitchCompatibility,
    # Derived: handled APIDs HOLDs (L22).
    Cadence.Spacecraft.ConfigKinds.ApidCompatibility
  ],
  # Which spacecraft have had traffic, for the archive HOLD (#49/#50).
  spacecraft_traffic: Cadence.Control.SpacecraftTraffic,
  # Which other missions of the organization fly a SCID through a shared provider account, for
  # the same-SCID HOLD (ux U81 §1).
  scid_sharing: Cadence.Control.ScidSharing,
  # The mission's catalog points for the derived_telemetry kind's checks (#77), configured so
  # governance has no compile-time edge to projections.
  derived_point_catalog: Cadence.Ops.PointCatalog,
  # Catalog revision lookup for profile/override catalog changes (#36/#65), configured so the
  # spacecraft kinds have no compile-time edge to the catalog context.
  catalog_revisions: Cadence.Catalog,
  # A catalog revision's APIDs, for profile/override handled_apids (L22), configured likewise.
  catalog_apids: Cadence.MissionModels.CatalogApids,
  # Builds runtime activations for profile-framed change-set applies (DECISIONS #36).
  configuration_generation: Cadence.Control.ConfigurationGeneration,
  ecto_repos: [Cadence.Repo],
  start_background_jobs: true,
  background_jobs: [
    safety_poll_interval_ms: 60_000,
    max_concurrency: 4
  ],
  # On by default (DECISIONS #95): received bytes are journaled before processing. The off path
  # stays supported and tested (the :ingest_journal_matrix tag, CADENCE_TEST_INGRESS_JOURNAL=off).
  ingress_journal: [
    enabled?: true,
    base_path: Path.expand("../../../var/ingress_journal", __DIR__),
    max_bytes: 8 * 1_024 * 1_024 * 1_024,
    segment_bytes: 256 * 1_024 * 1_024,
    capture_record_bytes: 256 * 1_024,
    processing_max_batch_entries: 8,
    processing_max_batch_bytes: 2 * 1_024 * 1_024,
    durability: :sync,
    checkpoint_interval_ms: 250,
    consumers: [:processing, :archive]
  ],
  ingress_archive: [
    module: Cadence.IngressArchive.FileSystem,
    base_path: Path.expand("../../../var/ingress_archive", __DIR__),
    flush_interval_ms: 250,
    flush_count: 100
  ],
  ingress_archive_consumer: [
    required_completion: :durable,
    max_batch_entries: 128,
    max_batch_bytes: 8 * 1_024 * 1_024,
    max_dwell_ms: 25,
    retry_initial_ms: 50,
    retry_max_ms: 5_000
  ],
  protocol_record_archive: [
    module: Cadence.Protocol.RecordArchive.FileSystem,
    base_path: Path.expand("../../../var/protocol_record_archive", __DIR__),
    flush_interval_ms: 250,
    flush_count: 250
  ],
  telemetry_current_value_store: [module: Cadence.Telemetry.CurrentValueStore.ETS],
  telemetry_storage: [
    writer: Cadence.Telemetry.Storage.Writers.QuestDB,
    realm: :flight,
    data_source_id: "managed_questdb_primary",
    binding_id: "default_flight_telemetry"
  ],
  telemetry_history_store: [
    module: Cadence.Telemetry.HistoryStore.QuestDB,
    realm: :flight,
    data_source_id: "managed_questdb_primary"
  ],
  data_sources: [
    persisted?: true,
    bootstrap_defaults?: true
  ],
  data_source_adapters: [
    telemetry: [
      version: 1,
      label: "Telemetry",
      description: "Latest and historical spacecraft telemetry.",
      module: Cadence.Dashboards.Sources.Telemetry,
      probe_module: Cadence.Control.DataSources.Probes.Telemetry,
      default_data_source_capabilities: %{
        latest?: true,
        range_scan?: true,
        bounded_history?: true,
        watermarks?: true,
        native_decimation?: false
      }
    ],
    limits: [
      version: 1,
      label: "Limits",
      description: "Current and historical telemetry limit state.",
      module: Cadence.Dashboards.Sources.Limits,
      default_data_source_capabilities: %{
        latest_state?: true,
        event_history?: true,
        definition_intervals?: true,
        watermarks?: true
      }
    ],
    operational_observables: [
      version: 1,
      label: "Operational observables",
      description: "Cadence operational state and metric projections.",
      module: Cadence.Dashboards.Sources.OperationalObservables,
      default_data_source_capabilities: %{
        constellation_health?: true,
        watermarks?: false
      }
    ],
    events: [
      version: 1,
      label: "Events",
      description: "Mission, contact, source, and data-management events.",
      module: Cadence.Dashboards.Sources.Events,
      default_data_source_capabilities: %{
        contact_intervals?: true,
        mission_timeline?: true,
        source_health_transitions?: true,
        source_watermark_events?: true,
        source_capability_postures?: true,
        telemetry_backfill_lifecycle?: true,
        telemetry_revision_decisions?: true,
        watermarks?: false
      }
    ]
  ],
  dashboard_source_circuit_breaker: [
    enabled?: true,
    failure_threshold: 3,
    backoff_ms: 30_000
  ],
  dashboard_source_execution: [
    max_concurrency: 4,
    timeout_ms: 5_000
  ],
  data_source_health_events: [
    enabled?: true,
    freshness: [
      default_max_age_ms: 300_000,
      managed_tsdb: [questdb: 60_000],
      byo_tsdb: [questdb: 300_000],
      projection: [postgres_projection: 300_000]
    ]
  ],
  dashboard_source_readiness_policy: [
    policy_id: :default,
    block_source_health: [:unavailable],
    block_freshness: [:fresh]
  ],
  data_source_probe_scheduler: [
    enabled?: true,
    interval_ms: 60_000,
    max_concurrency: 4,
    probe_timeout_ms: 5_000
  ],
  data_source_watermark_events: [
    enabled?: true
  ],
  contact_scheduler: [enabled: true, safety_poll_interval_ms: 60_000],
  contact_scheduler_global_safety: [enabled: false, safety_poll_interval_ms: 300_000],
  provider_reservation_reconciler: [
    enabled: true,
    safety_poll_interval_ms: 5_000,
    max_concurrency: 4
  ],
  command_dispatcher: [
    enabled: true,
    safety_poll_interval_ms: 60_000,
    lane_safety_poll_interval_ms: 60_000
  ],
  environment_admin: [enabled: false],
  command_verifier_scheduler: [enabled: true, safety_poll_interval_ms: 60_000],
  generators: [timestamp_type: :utc_datetime_usec]

import_config "job_handlers.exs"
import_config "#{config_env()}.exs"
