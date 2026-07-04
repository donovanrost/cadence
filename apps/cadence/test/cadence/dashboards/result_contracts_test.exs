defmodule Cadence.Dashboards.ResultContractsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataContext,
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    LimitContext,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning,
    ScopeContext,
    SourceCapabilities,
    SourceFacts,
    SourceResult,
    SourceWatermark,
    TimeContext
  }

  test "fields normalize serialized keys and kind vocabularies" do
    assert %Field{
             name: "radio.bit_rate",
             kind: :number,
             values: [9600],
             metadata: %{"unit" => "bps"}
           } =
             Field.normalize(%{
               "name" => "radio.bit_rate",
               "kind" => "number",
               "values" => [9600],
               "metadata" => %{"unit" => "bps"}
             })
  end

  test "frames normalize serialized keys, vocabularies, and nested fields" do
    assert %Frame{
             frame_id: "frame-1",
             source: :operational_observables,
             shape: :matrix,
             time_axis: :receipt_time,
             scope: %{"spacecraft_id" => "sc-1"},
             fields: [
               %Field{name: "time", kind: :time},
               "invalid-field"
             ],
             overlays: %{"limits" => ["limit-frame"]},
             meta: %{"source_request_id" => "source-request-1"}
           } =
             Frame.normalize(%{
               "frame_id" => "frame-1",
               "source" => "operational-observables",
               "shape" => "matrix",
               "time_axis" => "receipt-time",
               "scope" => %{"spacecraft_id" => "sc-1"},
               "fields" => [
                 %{"name" => "time", "kind" => "time", "values" => []},
                 "invalid-field"
               ],
               "overlays" => %{"limits" => ["limit-frame"]},
               "meta" => %{"source_request_id" => "source-request-1"}
             })
  end

  test "placement frames normalize overlays, warnings, and request ids" do
    assert %PlacementFrames{
             primary: [
               %Frame{
                 source: :telemetry,
                 shape: :scalar,
                 fields: [%Field{name: "value", kind: :number, values: [42]}]
               }
             ],
             overlays: %{
               limits: [
                 %Frame{
                   source: :limits,
                   shape: :scalar,
                   fields: [%Field{name: "state", kind: :enum, values: [:green]}]
                 }
               ]
             },
             warnings: [%ResolveWarning{code: :watermark_unknown, severity: :info}],
             planned_request_ids: ["source-request-1"]
           } =
             PlacementFrames.normalize(%{
               "primary" => [
                 %{
                   "source" => "telemetry",
                   "shape" => "scalar",
                   "fields" => [%{"name" => "value", "kind" => "number", "values" => [42]}]
                 }
               ],
               "overlays" => %{
                 "limits" => [
                   %{
                     "source" => "limits",
                     "shape" => "scalar",
                     "fields" => [%{"name" => "state", "kind" => "enum", "values" => [:green]}]
                   }
                 ]
               },
               "warnings" => [%{"code" => "watermark_unknown", "severity" => "info"}],
               "planned_request_ids" => ["source-request-1"]
             })
  end

  test "source results normalize serialized frames, warnings, and watermarks" do
    assert %SourceResult{
             request_id: "source-request-1",
             frames: [
               %Frame{
                 source: :telemetry,
                 shape: :scalar,
                 fields: [%Field{name: "value", kind: :number}]
               },
               "invalid-frame"
             ],
             warnings: [%ResolveWarning{code: :watermark_unknown, severity: :info}],
             watermarks: [%SourceWatermark{logical_source: :telemetry, confidence: :unknown}],
             meta: %{"returned_frame_count" => 1}
           } =
             SourceResult.normalize(%{
               "request_id" => "source-request-1",
               "frames" => [
                 %{
                   "source" => "telemetry",
                   "shape" => "scalar",
                   "fields" => [%{"name" => "value", "kind" => "number"}]
                 },
                 "invalid-frame"
               ],
               "warnings" => [
                 %{"code" => "watermark_unknown", "severity" => "info"}
               ],
               "watermarks" => [
                 %{"logical_source" => "telemetry", "confidence" => "unknown"}
               ],
               "meta" => %{"returned_frame_count" => 1}
             })
  end

  test "source capabilities normalize serialized vocabularies and booleans" do
    assert %SourceCapabilities{
             logical_source: :telemetry,
             supported_sampling: [:latest, :decimated_envelope],
             supported_products: [:latest_value],
             supported_time_axes: [:receipt_time],
             supported_value_types: [:engineering],
             supported_shapes: [:scalar, :wide],
             supports_watermarks?: true,
             completeness: :partial,
             metadata: %{"storage" => "questdb"}
           } =
             SourceCapabilities.normalize(%{
               "logical_source" => "telemetry",
               "supported_sampling" => ["latest", "decimated-envelope"],
               "supported_products" => ["latest_value"],
               "supported_time_axes" => ["receipt-time"],
               "supported_value_types" => ["engineering"],
               "supported_shapes" => ["scalar", "wide"],
               "supports_watermarks?" => "true",
               "completeness" => "partial",
               "metadata" => %{"storage" => "questdb"}
             })
  end

  test "source facts normalize watermarks, source health, and metadata" do
    assert %SourceFacts{
             watermark: %SourceWatermark{logical_source: :telemetry, confidence: :unknown},
             watermarks: [
               %SourceWatermark{logical_source: :telemetry, freshness_state: :retention_gap}
             ],
             source_binding_segments: [%{"dataset" => "flight"}],
             source_health: :unavailable,
             meta: %{"reason" => "probe_failed"}
           } =
             SourceFacts.normalize(%{
               "watermark" => %{"logical_source" => "telemetry", "confidence" => "unknown"},
               "watermarks" => [
                 %{"logical_source" => "telemetry", "freshness_state" => "retention-gap"}
               ],
               "source_binding_segments" => [%{"dataset" => "flight"}],
               "source_health" => "unavailable",
               "meta" => %{"reason" => "probe_failed"}
             })
  end

  test "resolve warnings normalize typed evidence and links while preserving invalid entries" do
    assert %ResolveWarning{
             code: :watermark_unknown,
             severity: :info,
             scope: :placement,
             details: %{"reason" => "missing"},
             evidence: [%EvidenceRef{kind: :source_request, source: :telemetry}, "invalid-ref"],
             links: [%DataLink{target: :telemetry_point, source: :warning}, "invalid-link"]
           } =
             ResolveWarning.normalize(%{
               "code" => "watermark_unknown",
               "severity" => "info",
               "scope" => "placement",
               "details" => %{"reason" => "missing"},
               "evidence" => [
                 %{
                   "kind" => "source_request",
                   "id" => "source-request-1",
                   "source" => "telemetry"
                 },
                 "invalid-ref"
               ],
               "links" => [
                 %{
                   "link_id" => "telemetry-point:HK.counter",
                   "label" => "Telemetry point",
                   "target" => "telemetry_point",
                   "target_id" => "HK.counter",
                   "source" => "warning"
                 },
                 "invalid-link"
               ]
             })
  end

  test "source watermarks normalize source and freshness vocabularies" do
    assert %SourceWatermark{
             logical_source: :telemetry,
             request_id: "source-request-1",
             confidence: :unknown,
             freshness_state: :retention_gap,
             freshness_policy: %{"max_age_ms" => 60_000},
             meta: %{"reason" => "retention"}
           } =
             SourceWatermark.normalize(%{
               "logical_source" => "telemetry",
               "request_id" => "source-request-1",
               "confidence" => "unknown",
               "freshness_state" => "retention-gap",
               "freshness_policy" => %{"max_age_ms" => 60_000},
               "meta" => %{"reason" => "retention"}
             })
  end

  test "planned source requests normalize contexts, overlays, and consumers" do
    assert %PlannedSourceRequest{
             logical_source: :telemetry,
             observables: ["HK.counter"],
             scope_context: %ScopeContext{primary: %{kind: "spacecraft"}},
             time_context: %TimeContext{mode: "live"},
             data_context: %DataContext{realm: "flight"},
             limit_context: %LimitContext{semantics_mode: "observed"},
             overlays: [:limits],
             consumers: [
               %{placement_id: "placement-1", role: :primary, widget_type_id: "value_tile"}
             ],
             sampling: %{"mode" => "latest"},
             metadata: %{"source" => "test"}
           } =
             PlannedSourceRequest.normalize(%{
               "request_id" => "source-request-1",
               "logical_source" => "telemetry",
               "observables" => ["HK.counter"],
               "scope_context" => %{
                 "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc_001"]}
               },
               "time_context" => %{"mode" => "live"},
               "data_context" => %{"realm" => "flight"},
               "limit_context" => %{"semantics_mode" => "observed"},
               "overlays" => ["limits"],
               "consumers" => [
                 %{
                   "placement_id" => "placement-1",
                   "role" => "primary",
                   "widget_type_id" => "value_tile"
                 }
               ],
               "sampling" => %{"mode" => "latest"},
               "metadata" => %{"source" => "test"}
             })
  end
end
