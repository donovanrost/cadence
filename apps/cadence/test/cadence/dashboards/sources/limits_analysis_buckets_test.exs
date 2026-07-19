defmodule Cadence.Dashboards.Sources.LimitsAnalysisBucketsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceResult
  }

  alias Cadence.Dashboards.Sources.Limits
  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Telemetry.Sample

  test "resolves compare limit analysis buckets from telemetry samples" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:03:00Z]

    sample_history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-1", 95, ~U[2026-06-17 12:00:10Z], "evidence-1"),
        sample(point_id, "sample-2", 105, ~U[2026-06-17 12:00:40Z], "evidence-2"),
        sample(point_id, "sample-3", 42, ~U[2026-06-17 12:01:10Z], "evidence-3")
      ]
    end

    interval_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        definition_interval(point_id,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: nil,
          thresholds: %{"yellow_high" => 90, "red_high" => 100}
        )
      ]
    end

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        event(point_id,
          limit_event_id: "observed-limit-event-1",
          sample_id: "sample-1",
          normalized_state: :yellow,
          limit_state: :yellow_high,
          violation: true,
          receipt_time: ~U[2026-06-17 12:00:10Z]
        ),
        event(point_id,
          limit_event_id: "observed-limit-event-2",
          sample_id: "sample-2",
          normalized_state: :green,
          limit_state: :green,
          violation: false,
          receipt_time: ~U[2026-06-17 12:00:40Z]
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :compare},
          sampling: %{
            mode: :analysis_buckets,
            products: [:analysis_buckets],
            bucket_width_ms: 60_000
          },
          time_context: %{axis: :receipt_time, from: from_time, to: to_time}
        ),
        sample_history_fun: sample_history_fun,
        interval_fun: interval_fun,
        history_fun: history_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    assert result.meta.supported_capability == :limit_comparison_analysis
    assert result.meta.degraded?
    assert frame.frame_id == "limits-request-1:HK.counter:analysis_buckets:compare"
    assert frame.meta.sampling == :analysis_buckets
    assert frame.meta.semantics_mode == :compare
    assert frame.meta.synthetic_limit_analysis?
    assert frame.meta.bucket_width_ms == 60_000
    assert frame.meta.returned_buckets == 2
    assert frame.meta.returned_events == 3
    assert frame.meta.divergence_count == 1

    assert Enum.map(warnings, & &1.code) == [
             :watermark_unknown,
             :limit_analysis_diverged
           ]

    assert %Field{
             name: "bucket_start",
             values: [~U[2026-06-17 12:00:00.000Z], ~U[2026-06-17 12:01:00.000Z]]
           } = Enum.find(frame.fields, &(&1.name == "bucket_start"))

    assert %Field{
             name: "bucket_end",
             values: [~U[2026-06-17 12:01:00.000Z], ~U[2026-06-17 12:02:00.000Z]]
           } = Enum.find(frame.fields, &(&1.name == "bucket_end"))

    assert %Field{name: "event_count", values: [2, 1]} =
             Enum.find(frame.fields, &(&1.name == "event_count"))

    assert %Field{name: "sample_id", values: ["sample-2", "sample-3"]} =
             Enum.find(frame.fields, &(&1.name == "sample_id"))

    assert %Field{name: "sample_ids", values: [["sample-1", "sample-2"], ["sample-3"]]} =
             Enum.find(frame.fields, &(&1.name == "sample_ids"))

    assert %Field{name: "normalized_state", values: [:red, :green]} =
             Enum.find(frame.fields, &(&1.name == "normalized_state"))

    assert %Field{name: "limit_state", values: [:red_high, :green]} =
             Enum.find(frame.fields, &(&1.name == "limit_state"))

    assert %Field{name: "observed_normalized_state", values: [:green, nil]} =
             Enum.find(frame.fields, &(&1.name == "observed_normalized_state"))

    assert %Field{name: "limit_state_diverged", values: [true, false]} =
             Enum.find(frame.fields, &(&1.name == "limit_state_diverged"))

    assert %Field{name: "limit_divergence_count", values: [1, 0]} =
             Enum.find(frame.fields, &(&1.name == "limit_divergence_count"))
  end

  test "splits observed analysis buckets by limit definition identity" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:01:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        event(point_id,
          limit_event_id: "limit-event-v1",
          sample_id: "sample-v1",
          normalized_state: :yellow,
          limit_state: :yellow_high,
          violation: true,
          limit_definition_id: "limit-def-a",
          limit_definition_version: 1,
          limit_set_name: "ops-a",
          receipt_time: ~U[2026-06-17 12:00:10Z]
        ),
        event(point_id,
          limit_event_id: "limit-event-v2",
          sample_id: "sample-v2",
          normalized_state: :red,
          limit_state: :red_high,
          violation: true,
          limit_definition_id: "limit-def-b",
          limit_definition_version: 2,
          limit_set_name: "ops-b",
          receipt_time: ~U[2026-06-17 12:00:40Z]
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          sampling: %{
            mode: :analysis_buckets,
            products: [:analysis_buckets],
            bucket_width_ms: 60_000
          },
          time_context: %{axis: :receipt_time, from: from_time, to: to_time}
        ),
        history_fun: history_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame]} = result
    refute result.meta.degraded?
    assert frame.meta.sampling == :analysis_buckets
    assert frame.meta.semantics_mode == :observed
    assert frame.meta.returned_buckets == 2
    assert frame.meta.returned_events == 2

    assert %Field{
             name: "bucket_start",
             values: [~U[2026-06-17 12:00:00.000Z], ~U[2026-06-17 12:00:00.000Z]]
           } = Enum.find(frame.fields, &(&1.name == "bucket_start"))

    assert %Field{
             name: "bucket_end",
             values: [~U[2026-06-17 12:01:00.000Z], ~U[2026-06-17 12:01:00.000Z]]
           } = Enum.find(frame.fields, &(&1.name == "bucket_end"))

    assert %Field{name: "event_count", values: [1, 1]} =
             Enum.find(frame.fields, &(&1.name == "event_count"))

    assert %Field{name: "limit_event_id", values: ["limit-event-v1", "limit-event-v2"]} =
             Enum.find(frame.fields, &(&1.name == "limit_event_id"))

    assert %Field{name: "limit_definition_id", values: ["limit-def-a", "limit-def-b"]} =
             Enum.find(frame.fields, &(&1.name == "limit_definition_id"))

    assert %Field{name: "limit_definition_version", values: [1, 2]} =
             Enum.find(frame.fields, &(&1.name == "limit_definition_version"))

    assert %Field{name: "limit_set_name", values: ["ops-a", "ops-b"]} =
             Enum.find(frame.fields, &(&1.name == "limit_set_name"))

    assert %Field{name: "normalized_state", values: [:yellow, :red]} =
             Enum.find(frame.fields, &(&1.name == "normalized_state"))
  end

  defp source_request(overrides) do
    attrs =
      %{
        request_id: "limits-request-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :limits,
        observables: ["HK.counter"],
        scope_context: %{
          organization_id: "org-1",
          mission_id: "mission-1",
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time_context: %{axis: :generation_time},
        data_context: %{realm: :flight},
        value_type: :engineering,
        sampling: %{mode: :latest_state},
        overlays: []
      }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp sample(point_id, sample_id, value, receipt_time, evidence_id, overrides \\ []) do
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

  defp event(point_id, overrides) do
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

  defp definition_interval(point_id, overrides) do
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

  defp source_binding(capabilities \\ %{}) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "default_flight_limits",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        logical_source: :limits,
        data_source_id: "managed_limits_projection",
        dataset: "telemetry_latest_limit_states"
      },
      data_source: %DataSource{
        data_source_id: "managed_limits_projection",
        owner: :cadence,
        kind: :projection,
        isolation_level: :shared,
        adapter: Limits,
        capabilities: capabilities
      },
      realm: :flight,
      dataset: "telemetry_latest_limit_states"
    }
  end
end
