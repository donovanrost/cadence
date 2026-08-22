defmodule Cadence.Dashboards.SourceRegistryFixtures do
  @moduledoc false

  alias Cadence.Dashboards.{EvidenceRef, PlannedSourceRequest}

  alias Cadence.DataSources.{SourceHealthEvent, SourceHealthStatus}

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Telemetry.Sample

  def source_request(overrides \\ []) do
    attrs = %{
      request_id: "source-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  def production_source_request(logical_source, sampling_mode) do
    source_request(
      request_id: "source-request-#{logical_source}",
      logical_source: logical_source,
      sampling: %{mode: sampling_mode}
    )
  end

  def replay_source_request(overrides \\ []) do
    source_request(
      Keyword.merge(
        [
          time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"}
        ],
        overrides
      )
    )
  end

  def source_health_status(overrides) do
    attrs =
      %{
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        realm: :flight,
        dataset: "operational_observables",
        replay_run_id: nil,
        source_health_event_id: "source-health-operational-observables-1",
        event_type: :degraded,
        source_health: :degraded,
        previous_source_health: :healthy,
        reason: :source_probe_failed,
        observed_at: ~U[2026-06-21 20:30:00Z],
        last_seen_at: ~U[2026-06-21 20:30:00Z],
        transition_count: 1,
        payload: %{}
      }
      |> Map.merge(overrides)

    struct!(
      SourceHealthStatus,
      Map.put(attrs, :source_health_key, SourceHealthEvent.source_health_key(attrs))
    )
  end

  def data_binding(data_source_id) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org-1",
      mission_id: "mission-1",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: "flight"
    }
  end

  def data_binding(data_source_id, realm, metadata \\ %{}) do
    %DataBinding{
      binding_id: "#{realm}-telemetry",
      organization_id: "org-1",
      mission_id: "mission-1",
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm),
      metadata: metadata
    }
  end

  def data_source(data_source_id, capabilities, metadata \\ %{}) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      capabilities: Map.new(capabilities),
      metadata: metadata
    }
  end

  def test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter
    }
  end

  def production_source_registry_opts do
    [
      data_sources: [
        DataSources.default_managed_data_source(),
        DataSources.default_limits_data_source(),
        DataSources.default_events_data_source(),
        DataSources.default_operational_observables_data_source()
      ],
      data_bindings: [
        DataSources.default_flight_telemetry_binding(),
        DataSources.default_flight_limits_binding(),
        DataSources.default_flight_events_binding(),
        DataSources.default_flight_operational_observables_binding()
      ],
      validate_dashboard_contract?: true
    ]
  end

  def production_source_contracts do
    [
      %{
        logical_source: :telemetry,
        sampling_mode: :raw_series,
        binding_id: "default_flight_telemetry",
        data_source_id: "managed_questdb_primary",
        dataset: "flight",
        adapter_supported_products: [
          :latest_value,
          :bounded_receipt_time_history,
          :bounded_generation_time_history
        ],
        supported_time_axes: [:generation_time, :receipt_time],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:scalar, :wide],
        supports_watermarks?: true,
        completeness: :unknown
      },
      %{
        logical_source: :limits,
        sampling_mode: :latest_state,
        binding_id: "default_flight_limits",
        data_source_id: "managed_limits_projection",
        dataset: "telemetry_latest_limit_states",
        adapter_supported_products: [
          :latest_state,
          :event_history,
          :definition_intervals,
          :analysis_buckets
        ],
        supported_time_axes: [:receipt_time],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:scalar, :events, :intervals],
        supports_watermarks?: true,
        completeness: :unknown
      },
      %{
        logical_source: :events,
        sampling_mode: :event_history,
        binding_id: "default_flight_events",
        data_source_id: "managed_events_projection",
        dataset: "mission_events",
        adapter_supported_products: [
          :contact_intervals,
          :mission_timeline,
          :source_health_transitions,
          :source_watermark_events,
          :source_capability_postures,
          :telemetry_backfill_lifecycle,
          :telemetry_revision_decisions
        ],
        supported_time_axes: [:occurred_at],
        supported_value_types: [],
        supported_shapes: [:intervals, :events],
        supports_watermarks?: false,
        completeness: :partial
      },
      %{
        logical_source: :operational_observables,
        sampling_mode: :latest,
        binding_id: "default_flight_operational_observables",
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables",
        adapter_supported_products: [
          :constellation_health,
          :contacts_phase,
          :contacts_phase_history,
          :connection_state,
          :connection_state_history,
          :ground_station_antenna_pointing_state,
          :ground_station_antenna_pointing_state_history,
          :link_rf_lock_state,
          :link_rf_lock_state_history,
          :link_rf_frame_sync_state,
          :link_rf_frame_sync_state_history,
          :link_rf_metric,
          :link_rf_metric_history,
          :transport_bitrate,
          :transport_bitrate_history,
          :transport_execution_state_history,
          :managed_runtime_activity_history,
          :transport_runtime_activity_history,
          :ingress_processing_latency_history,
          :operational_metric_history,
          :operational_latest,
          :operational_state_history,
          :command_queue_depth,
          :ingress_processing_latency
        ],
        supported_time_axes: [:occurred_at],
        supported_value_types: [:raw, :engineering],
        supported_shapes: [:matrix, :events, :wide],
        supports_watermarks?: false,
        completeness: :known
      }
    ]
  end

  def capability_variant_data_source(:telemetry) do
    %{
      DataSources.default_managed_data_source()
      | capabilities: %{
          range_scan?: true,
          bounded_history?: true,
          latest?: true,
          watermarks?: true,
          native_decimation?: true
        }
    }
  end

  def capability_variant_data_source(:limits) do
    %{
      DataSources.default_limits_data_source()
      | capabilities: %{
          latest_state?: true,
          event_history?: true,
          definition_intervals?: false,
          watermarks?: false
        }
    }
  end

  def capability_variant_data_source(:events) do
    %{
      DataSources.default_events_data_source()
      | capabilities: %{
          contact_intervals?: true,
          mission_timeline?: true,
          source_health_transitions?: true,
          source_watermark_events?: true,
          source_capability_postures?: true,
          telemetry_backfill_lifecycle?: true,
          telemetry_revision_decisions?: true,
          watermarks?: true,
          external_projection?: true
        }
    }
  end

  def capability_variant_data_source(:operational_observables) do
    %{
      DataSources.default_operational_observables_data_source()
      | capabilities: %{
          constellation_health?: true,
          watermarks?: true,
          projected_snapshot_revision?: true
        }
    }
  end

  def sample(point_id, sample_id, value, receipt_time, evidence_id) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-1",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      evidence_id: evidence_id,
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      receipt_time: receipt_time
    }
  end

  def limit_event(point_id, overrides) do
    %Event{
      limit_event_id: "limit-event-1",
      mission_id: "mission-1",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-1",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 42,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: nil,
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
    |> struct!(overrides)
  end

  def limit_definition_interval(point_id, overrides) do
    %DefinitionInterval{
      definition_activation_key: "limit-activation-1",
      limit_definition_lifecycle_event_id: "limit-lifecycle-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      point_id: point_id,
      limit_set_name: "ops",
      scope_type: nil,
      scope_ref: nil,
      realm: nil,
      event_type: :registered,
      limit_definition_id: "limit-def-1",
      limit_definition_version: 1,
      active_from: ~U[2026-06-17 12:00:00Z],
      active_to: nil,
      observed_at: ~U[2026-06-17 12:00:00Z],
      thresholds: %{},
      metadata: %{},
      complete?: true
    }
    |> struct!(overrides)
  end

  def effective_interval(kind, interval_id, subject_id) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: kind,
      subject_kind: kind,
      subject_id: subject_id,
      starts_at: ~U[2026-06-21 20:00:00Z],
      source_event_id: "source-event-#{interval_id}",
      payload: %{subject_id: subject_id}
    }
  end

  def evidence_ref(evidence, kind, id) do
    Enum.find(evidence, fn
      %EvidenceRef{kind: ^kind, id: ^id} -> true
      _other -> false
    end)
  end

  def source_circuit_opts(breaker, opts) do
    realm = Keyword.get(opts, :realm, :flight)
    data_source_id = "#{realm}-questdb"

    [
      source_circuit_breaker: breaker,
      source_circuit_failure_threshold: 2,
      source_circuit_backoff_ms: 60_000,
      now_ms: Keyword.fetch!(opts, :now_ms),
      data_sources: [
        %DataSource{
          data_source_id: data_source_id,
          adapter: Cadence.Support.DashboardSourceTestAdapter
        }
      ],
      data_bindings: [data_binding(data_source_id, realm)],
      source_opts: %{
        telemetry: [
          test_pid: self(),
          mode: Keyword.fetch!(opts, :mode)
        ]
      }
    ]
  end
end
