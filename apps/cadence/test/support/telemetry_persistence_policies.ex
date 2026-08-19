defmodule Cadence.TestSupport.TelemetryPersistencePolicies do
  @moduledoc false

  alias Cadence.IngressArchive
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.Persistence
  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Storage}

  def postgres(opts \\ []) do
    current_value_store =
      CurrentValueStore.policy(module: Cadence.Telemetry.CurrentValueStore.Postgres)

    telemetry_storage =
      Storage.policy(
        [
          writer: Cadence.Telemetry.Storage.Writers.PostgresReadModel,
          organization_id: Keyword.get(opts, :organization_id, "org-test"),
          realm: Keyword.get(opts, :realm, :flight),
          data_source_id: Keyword.get(opts, :data_source_id, "managed_questdb_primary"),
          binding_id: Keyword.get(opts, :binding_id, "default_flight_telemetry")
        ],
        current_value_store_policy: current_value_store
      )

    ingress_archive = IngressArchive.policy(module: Cadence.IngressArchive.Postgres)
    record_archive = RecordArchive.policy(module: Cadence.Protocol.RecordArchive.Postgres)

    history_store =
      HistoryStore.policy(
        [module: Cadence.Telemetry.HistoryStore.Postgres],
        storage_policy: telemetry_storage
      )

    %{
      current_value_store: current_value_store,
      telemetry_storage: telemetry_storage,
      history_store: history_store,
      ingress_archive: ingress_archive,
      record_archive: record_archive,
      persistence: Persistence.policy(ingress_archive, record_archive, telemetry_storage)
    }
  end
end
