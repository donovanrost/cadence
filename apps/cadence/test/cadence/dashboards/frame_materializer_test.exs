defmodule Cadence.Dashboards.FrameMaterializerTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    Field,
    Frame,
    FrameMaterializer,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCacheKey,
    SourceResult,
    SourceWatermark
  }

  test "materializes source frames for a placement consumer" do
    request = source_request()
    source_result = source_result(:telemetry, :scalar)

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"}
      )

    assert materialized.placement_id == "placement_power"
    assert materialized.request_id == request.request_id
    assert materialized.role == :primary
    assert [%Frame{source: :telemetry, shape: :scalar}] = materialized.frames
    assert materialized.frame_key == nil

    assert [%ResolveWarning{scope: :placement, placement_id: "placement_power"}] =
             materialized.warnings
  end

  test "builds frame cache key from placement display context" do
    request = source_request(:limits)
    source_result = source_result(:limits, :events)
    source_key = RuntimeCacheKey.source_result(request)

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result,
        %{placement_id: "placement_limits", role: :limits, widget_type_id: "widget_value_tile"},
        source_result_key: source_key,
        placement_size: %{width_px: 640, height_px: 240},
        display: %{density: :compact},
        catalog_revision: "catalog:v1"
      )

    assert %RuntimeCacheKey{layer: :frame} = materialized.frame_key
    assert materialized.frame_key.parts.source_result_fingerprint == source_key.fingerprint
    assert materialized.frame_key.parts.source_result_request.logical_source == :limits
    assert materialized.frame_key.parts.placement_id == "placement_limits"
    assert materialized.frame_key.parts.placement_size == %{width_px: 640, height_px: 240}
    assert materialized.frame_key.parts.display == %{density: :compact}
    assert materialized.frame_key.parts.frame_shape == :events
    assert materialized.frame_key.parts.catalog_revision == "catalog:v1"
  end

  test "builds distinct frame cache keys for different telemetry revision dependencies" do
    request = source_request(:telemetry)
    source_key = RuntimeCacheKey.source_result(request)

    conflict_result =
      source_result(:telemetry, :scalar,
        meta: %{
          telemetry_revision_dependency: revision_dependency("identity-1", "conflict-fingerprint")
        }
      )

    resolved_result =
      source_result(:telemetry, :scalar,
        meta: %{
          telemetry_revision_dependency: revision_dependency("identity-1", "resolved-fingerprint")
        }
      )

    conflict =
      FrameMaterializer.materialize(
        request,
        conflict_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"},
        source_result_key: source_key
      )

    resolved =
      FrameMaterializer.materialize(
        request,
        resolved_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"},
        source_result_key: source_key
      )

    assert conflict.frame_key.parts.telemetry_revision_dependency ==
             revision_dependency("identity-1", "conflict-fingerprint")

    assert resolved.frame_key.parts.telemetry_revision_dependency ==
             revision_dependency("identity-1", "resolved-fingerprint")

    assert conflict.frame_key.fingerprint != resolved.frame_key.fingerprint
  end

  test "copies capability provenance onto materialized frames" do
    provenance = capability_provenance()

    request =
      source_request(:telemetry,
        metadata: %{capability_provenance: provenance}
      )

    source_result = source_result(:telemetry, :scalar)

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"}
      )

    assert materialized.capability_provenance == provenance

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^provenance}
             }
           ] = materialized.frames
  end

  test "copies replay source request context onto materialized frames" do
    request =
      source_request(:telemetry,
        time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
        data_context: %{
          realm: :replay,
          replay_run_id: "replay-run-1",
          source_contexts: %{
            telemetry: %{
              data_source_id: "replay-questdb",
              source_binding_id: "replay-binding",
              dataset: "replay-dataset",
              view: :all_revisions
            }
          }
        }
      )

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result(:telemetry, :scalar),
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"}
      )

    assert [
             %Frame{
               meta: %{
                 source_request_time_context: %{
                   mode: :replay_run,
                   axis: :receipt_time,
                   replay_run_id: "replay-run-1"
                 },
                 source_request_context: %{
                   source_request_id: "source_req_telemetry",
                   logical_source: :telemetry,
                   time_mode: :replay_run,
                   time_axis: :receipt_time,
                   replay_run_id: "replay-run-1",
                   requested_realm: :replay,
                   requested_data_view: :all_revisions,
                   requested_data_source_id: "replay-questdb",
                   requested_source_binding_id: "replay-binding",
                   requested_dataset: "replay-dataset"
                 }
               }
             }
           ] = materialized.frames
  end

  test "normalizes source result frames before placement materialization" do
    request = source_request()

    source_result = %SourceResult{
      request_id: request.request_id,
      frames: [
        %{
          "frame_id" => "source-result-frame",
          "source" => "telemetry",
          "shape" => "scalar",
          "fields" => [
            %{"name" => "value", "kind" => "number", "values" => [42]}
          ]
        }
      ],
      warnings: [
        %{"code" => "watermark_unknown", "severity" => "info"}
      ]
    }

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"}
      )

    assert [
             %Frame{
               frame_id: "source-result-frame",
               source: :telemetry,
               shape: :scalar,
               fields: [%Field{name: "value", kind: :number, values: [42]}]
             }
           ] = materialized.frames

    assert [%ResolveWarning{code: :watermark_unknown, severity: :info, scope: :placement}] =
             materialized.warnings
  end

  test "promotes durable source watermark metadata onto materialized frame markers" do
    request = source_request()

    source_result =
      source_result(:telemetry, :scalar,
        watermarks: [
          %SourceWatermark{
            logical_source: :telemetry,
            request_id: request.request_id,
            source_binding_id: "default_flight_telemetry",
            data_source_id: "managed_questdb_primary",
            realm: :flight,
            dataset: "flight",
            complete_through: ~U[2026-06-21 18:00:00Z],
            latest_receipt_time: ~U[2026-06-21 18:00:00Z],
            retention_starts_at: ~U[2026-06-21 17:00:00Z],
            sample_count: 12,
            confidence: :best_effort,
            freshness_state: :retention_gap,
            meta: %{
              durable_source_watermark?: true,
              source_watermark_event_id: "watermark-event-durable",
              source_watermark_observed_at: ~U[2026-06-21 18:00:01Z],
              source_watermark_last_seen_at: ~U[2026-06-21 18:00:01Z],
              source_watermark_reason: :telemetry_storage_write
            }
          }
        ]
      )

    materialized =
      FrameMaterializer.materialize(
        request,
        source_result,
        %{placement_id: "placement_power", role: :primary, widget_type_id: "widget_value_tile"}
      )

    assert [
             %Frame{
               meta: %{
                 source_watermarks: [
                   %{
                     durable_source_watermark?: true,
                     source_watermark_event_id: "watermark-event-durable",
                     source_watermark_observed_at: ~U[2026-06-21 18:00:01Z],
                     source_watermark_last_seen_at: ~U[2026-06-21 18:00:01Z],
                     source_watermark_reason: :telemetry_storage_write,
                     complete_through: ~U[2026-06-21 18:00:00Z],
                     freshness_state: :retention_gap
                   }
                 ]
               }
             }
           ] = materialized.frames
  end

  defp source_request(logical_source \\ :telemetry, opts \\ []) do
    %PlannedSourceRequest{
      request_id: "source_req_#{logical_source}",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      logical_source: logical_source,
      observables: ["battery_voltage"],
      time_context: Keyword.get(opts, :time_context, %{}),
      data_context: Keyword.get(opts, :data_context, %{}),
      sampling: %{mode: :latest},
      limit_context: %{semantics_mode: "observed"},
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp capability_provenance do
    %{
      logical_source: :telemetry,
      binding_id: "default_flight_telemetry",
      data_source_id: "managed_questdb_primary",
      realm: :flight,
      dataset: "flight",
      supported_sampling: [:latest],
      capability_fingerprint: "capability:telemetry:v1"
    }
  end

  defp source_result(source, shape, opts \\ []) do
    %SourceResult{
      request_id: "source_req_telemetry",
      frames: [
        %Frame{
          frame_id: "frame_#{source}",
          source: source,
          shape: shape
        }
      ],
      meta: Keyword.get(opts, :meta, %{}),
      watermarks: Keyword.get(opts, :watermarks, []),
      warnings: [
        %ResolveWarning{
          code: :watermark_unknown,
          severity: :info,
          scope: :dashboard,
          message: "Watermark unknown"
        }
      ]
    }
  end

  defp revision_dependency(observation_identity_id, fingerprint) do
    %{
      kind: :telemetry_observation_identity_state,
      fingerprint: fingerprint,
      observation_identity_ids: [observation_identity_id]
    }
  end
end
