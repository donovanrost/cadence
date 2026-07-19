defmodule Cadence.Dashboards.Sources.TelemetryFixtures do
  @moduledoc false

  alias Cadence.Dashboards.{
    DataBinding,
    DataBindingInterval,
    DataSource,
    PlannedSourceRequest,
    ResolvedSourceBinding
  }

  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.ObservationIdentityState

  def source_request(overrides) do
    attrs =
      %{
        request_id: "source-request-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :telemetry,
        observables: ["HK.counter"],
        scope_context: %{
          organization_id: "org-1",
          mission_id: "mission-1",
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time_context: %{axis: :receipt_time},
        data_context: %{realm: :flight, data_source_id: "managed_questdb_primary"},
        value_type: :engineering,
        sampling: %{mode: :raw_series, max_raw_points: 100},
        overlays: []
      }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  def sample(point_id, sample_id, value, receipt_time, evidence_id, overrides \\ []) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-1",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: evidence_id,
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: nil,
      receipt_time: receipt_time,
      provenance: %{}
    }
    |> struct!(overrides)
  end

  def backfill_lifecycle_event(run_id, event_type, overrides) do
    %{
      backfill_lifecycle_event_id: "#{run_id}-#{event_type}",
      backfill_run_id: run_id,
      event_type: event_type,
      observable_id: "HK.counter",
      point_id: "HK.counter",
      occurred_at: ~U[2026-06-17 12:00:00Z]
    }
    |> Map.merge(Map.new(overrides))
  end

  def storage_provenance(observation_identity_id) do
    %{
      "storage" => %{
        "observation_identity_id" => observation_identity_id,
        "observation_id" => "observation-#{observation_identity_id}",
        "validity_state" => "canonical"
      }
    }
  end

  def identity_state(observation_identity_id, overrides \\ []) do
    struct!(
      ObservationIdentityState,
      Keyword.merge(
        [
          observation_identity_id: observation_identity_id,
          organization_id: "org-1",
          mission_id: "mission-1",
          realm: :flight,
          data_source_id: "managed_questdb_primary",
          binding_id: "flight-telemetry",
          observable_id: "HK.counter",
          point_id: "HK.counter",
          spacecraft_id: "sc-1",
          canonical_observation_id: "observation-#{observation_identity_id}",
          canonical_sample_id: "sample-#{observation_identity_id}",
          canonical_revision: 1,
          latest_observation_id: "observation-#{observation_identity_id}",
          latest_sample_id: "sample-#{observation_identity_id}",
          latest_revision: 1,
          validity_state: :canonical,
          canonical_count: 1,
          duplicate_count: 0,
          conflict_count: 0,
          superseded_count: 0,
          advisory_count: 0,
          first_seen_at: ~U[2026-06-17 12:00:00Z],
          last_seen_at: ~U[2026-06-17 12:00:00Z],
          payload: %{}
        ],
        overrides
      )
    )
  end

  def source_binding(capabilities \\ %{}) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "binding-rehearsal",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :rehearsal,
        logical_source: :telemetry,
        data_source_id: "customer-questdb-rehearsal",
        dataset: "rehearsal-12"
      },
      data_source: %DataSource{
        data_source_id: "customer-questdb-rehearsal",
        owner: :customer,
        kind: :byo_tsdb,
        isolation_level: :customer_owned,
        adapter: Telemetry,
        capabilities: capabilities
      },
      realm: :rehearsal,
      dataset: "rehearsal-12"
    }
  end

  def source_binding_with_interval(capabilities \\ %{}) do
    binding = source_binding(capabilities)

    %ResolvedSourceBinding{
      binding
      | binding_interval: %DataBindingInterval{
          data_binding_event_id: "binding-event-rehearsal-1",
          binding_id: "binding-rehearsal",
          organization_id: "org-1",
          mission_id: "mission-1",
          event_type: :binding_activated,
          status: :active,
          binding_version: 1,
          logical_source: :telemetry,
          realm: :rehearsal,
          data_source_id: "customer-questdb-rehearsal",
          dataset: "rehearsal-12",
          priority: 10,
          started_at: ~U[2026-06-17 11:55:00Z],
          active_from: ~U[2026-06-17 12:00:00Z]
        }
    }
  end

  def replay_source_binding(capabilities \\ %{}) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "binding-replay",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :replay,
        logical_source: :telemetry,
        data_source_id: "managed_questdb_replay",
        dataset: "replay-run-1"
      },
      data_source: %DataSource{
        data_source_id: "managed_questdb_replay",
        owner: :cadence,
        kind: :managed_questdb,
        isolation_level: :mission,
        adapter: Telemetry,
        capabilities: capabilities
      },
      realm: :replay,
      dataset: "replay-run-1"
    }
  end
end
