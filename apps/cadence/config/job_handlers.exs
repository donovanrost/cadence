import Config

# The durable queue is platform-owned; executable domain handlers are wired at
# composition roots. Keep this registration independently importable for
# applications that exercise Cadence jobs without loading the full web config.
config :cadence, :job_handlers, %{
  replay_telemetry_scope: {Cadence.Replay, :execute_enqueued_run},
  telemetry_latest_value_rebuild:
    {Cadence.Projections.TelemetryLatestValues, :execute_enqueued_run},
  derived_telemetry_evaluation: {Cadence.Control.DerivedTelemetry, :execute_enqueued_run},
  derived_telemetry_latest_value_rebuild:
    {Cadence.Projections.DerivedTelemetryLatestValues, :execute_enqueued_run},
  telemetry_limit_evaluation: {Cadence.Limits, :execute_enqueued_run},
  telemetry_latest_limit_state_refresh:
    {Cadence.Projections.TelemetryLatestLimitStates, :execute_enqueued_refresh_run},
  telemetry_latest_limit_state_rebuild:
    {Cadence.Projections.TelemetryLatestLimitStates, :execute_enqueued_run},
  mission_event_rebuild: {Cadence.Projections.MissionEvents, :execute_enqueued_run},
  catalog_import_run: {Cadence.Catalog, :execute_enqueued_run},
  telemetry_historical_data_workflow:
    {Cadence.Telemetry.DataManagement, :execute_enqueued_historical_data_workflow},
  managed_questdb_provisioning:
    {Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs, :execute_enqueued_run},
  tsdb_backend_lifecycle:
    {Cadence.Control.DataSources.TSDBBackendLifecycleJobs, :execute_enqueued_run}
}
