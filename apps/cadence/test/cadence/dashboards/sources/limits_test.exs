defmodule Cadence.Dashboards.Sources.LimitsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    FrameEvidence,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceResult
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Dashboards.Sources.Limits
  alias Cadence.Limits.{DefinitionInterval, Event}
  alias Cadence.Telemetry.Sample

  test "resolves latest observed limit state into a scalar overlay frame" do
    generation_time = ~U[2026-06-17 12:00:00Z]
    receipt_time = ~U[2026-06-17 12:00:01Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})

      event(point_id,
        limit_event_id: "limit-event-1",
        sample_id: "sample-1",
        normalized_state: :yellow,
        limit_state: :yellow_high,
        violation: true,
        generation_time: generation_time,
        receipt_time: receipt_time
      )
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          definition_activation_key: "limit-activation-1",
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: ~U[2026-06-17 13:00:00Z]
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(),
        latest_fun: latest_fun,
        interval_fun: interval_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "limits-request-1", frames: [frame]} = result
    assert %Frame{source: :limits, shape: :scalar, time_axis: :generation_time} = frame

    assert [
             %Field{name: "time", kind: :time, values: [^generation_time]},
             %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
             %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
             %Field{name: "violation", kind: :boolean, values: [true]}
           ] = frame.fields

    assert frame.meta.limit_event_id == "limit-event-1"
    assert frame.meta.sample_id == "sample-1"
    assert frame.meta.limit_definition_id == "limit-def-1"
    assert frame.meta.limit_definition_version == 3
    assert frame.meta.limit_set_name == "ops"
    assert frame.meta.sampling == :latest_state
    assert frame.meta.semantics_mode == :observed
    assert frame.meta.analysis_basis == :observed_fact
    assert frame.meta.returned_points == 1
    assert frame.meta.realm == :flight
    assert frame.meta.data_source_id == "managed_limits_projection"

    assert [
             %{
               active_from: ~U[2026-06-17 11:00:00Z],
               limit_definition_lifecycle_event_id: "limit-lifecycle-1",
               limit_definition_id: "limit-def-1",
               limit_definition_version: 1,
               limit_set_name: "ops",
               point_id: "HK.counter"
             }
           ] = frame.meta.selected_limit_definition_intervals

    assert [
             %EvidenceRef{kind: :limit_event, id: "limit-event-1", source: :limits},
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-1",
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-1"},
             %EvidenceRef{kind: :limit_definition, id: "limit-def-1", source: :limits}
           ] = frame.meta.evidence

    assert [
             %DataLink{target: :telemetry_point, target_id: "HK.counter", source: :frame},
             %DataLink{target: :limit_event, target_id: "limit-event-1", source: :frame},
             %DataLink{target: :limit_definition, target_id: "limit-def-1", source: :frame},
             %DataLink{target: :telemetry_sample, target_id: "sample-1", source: :frame}
           ] = frame.meta.links

    refute result.meta.degraded?
    assert result.meta.supported_capability == :latest_limit_state

    assert [
             %ResolveWarning{
               code: :watermark_unknown,
               severity: :info,
               links: [
                 %DataLink{target: :telemetry_point, target_id: "HK.counter", source: :warning}
               ]
             }
           ] = result.warnings

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "managed_limits_projection"
    assert opts[:dataset] == "telemetry_latest_limit_states"
    assert opts[:semantics_mode] == :observed
    assert opts[:spacecraft_id] == "sc-1"

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:realm] == :flight
    assert interval_opts[:data_source_id] == "managed_limits_projection"
    assert interval_opts[:dataset] == "telemetry_latest_limit_states"
    assert interval_opts[:semantics_mode] == :observed
  end

  test "does not treat non-spacecraft primary scope ids as spacecraft filters" do
    parent = self()

    latest_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:latest_opts, opts})
      event(point_id, [])
    end

    result =
      Limits.resolve(
        source_request(
          scope_context: %{
            primary: %{kind: "contact", mode: "one", ids: ["contact-1"]}
          }
        ),
        latest_fun: latest_fun
      )

    assert %SourceResult{frames: [%Frame{}]} = result
    assert_receive {:latest_opts, opts}
    refute Keyword.has_key?(opts, :spacecraft_id)
  end

  test "routes replay observed limit reads through replay source filters" do
    receipt_time = ~U[2026-06-17 12:00:01Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      event(point_id, receipt_time: receipt_time)
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})
      [definition_interval(point_id, active_from: ~U[2026-06-17 11:00:00Z])]
    end

    watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:watermark, organization_id, mission_id, point_id, opts})

      %{
        complete_through: receipt_time,
        latest_receipt_time: receipt_time,
        retention_starts_at: ~U[2026-06-17 11:00:00Z],
        confidence: :best_effort
      }
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"}
        ),
        latest_fun: latest_fun,
        interval_fun: interval_fun,
        watermark_fun: watermark_fun,
        source_binding: replay_source_binding(%{watermarks?: true})
      )

    assert %SourceResult{frames: [%Frame{} = frame]} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_limits_replay"
    assert frame.meta.replay_run_id == "replay-run-1"

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", latest_opts}
    assert latest_opts[:realm] == :replay
    assert latest_opts[:data_source_id] == "managed_limits_replay"
    assert latest_opts[:dataset] == "replay_limit_states"
    assert latest_opts[:replay_run_id] == "replay-run-1"
    assert latest_opts[:semantics_mode] == :observed

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:realm] == :replay
    assert interval_opts[:data_source_id] == "managed_limits_replay"
    assert interval_opts[:dataset] == "replay_limit_states"
    assert interval_opts[:replay_run_id] == "replay-run-1"

    assert_receive {:watermark, "org-1", "mission-1", "HK.counter", watermark_opts}
    assert watermark_opts[:realm] == :replay
    assert watermark_opts[:data_source_id] == "managed_limits_replay"
    assert watermark_opts[:dataset] == "replay_limit_states"
    assert watermark_opts[:replay_run_id] == "replay-run-1"
  end

  test "resolves latest limit state as of an archive receipt-time upper bound" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      event(point_id, receipt_time: to_time)
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :receipt_time,
            from: from_time,
            to: to_time
          }
        ),
        latest_fun: latest_fun,
        source_binding: source_binding()
      )

    assert [%Frame{meta: %{warning_codes: warning_codes}}] = result.frames
    refute :time_range_ignored in warning_codes
    refute result.meta.degraded?

    assert Enum.map(result.warnings, & &1.code) == [:watermark_unknown]

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:to_receipt_time] == to_time
    refute Keyword.has_key?(opts, :from_receipt_time)
  end

  test "warns when latest limit-state archive request has no receipt-time upper bound" do
    from_time = ~U[2026-06-17 12:00:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      event(point_id, receipt_time: from_time)
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :receipt_time,
            from: from_time
          }
        ),
        latest_fun: latest_fun,
        source_binding: source_binding()
      )

    assert [%Frame{meta: %{warning_codes: warning_codes}}] = result.frames
    assert :time_range_ignored in warning_codes
    assert result.meta.degraded?

    assert Enum.map(result.warnings, & &1.code) == [
             :watermark_unknown,
             :time_range_ignored
           ]

    assert %ResolveWarning{
             severity: :warning,
             details: %{
               requested_time_mode: :archive,
               requested_axis: :receipt_time,
               fallback: :latest_projection
             }
           } = Enum.find(result.warnings, &(&1.code == :time_range_ignored))

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "warns when latest limit-state archive request uses a non-receipt time axis" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      event(point_id, receipt_time: to_time)
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :generation_time,
            from: from_time,
            to: to_time
          }
        ),
        latest_fun: latest_fun,
        source_binding: source_binding()
      )

    assert [%Frame{meta: %{warning_codes: warning_codes}}] = result.frames
    assert :time_range_ignored in warning_codes
    assert result.meta.degraded?

    assert Enum.map(result.warnings, & &1.code) == [
             :watermark_unknown,
             :time_range_ignored
           ]

    assert %ResolveWarning{
             severity: :warning,
             details: %{
               requested_time_mode: :archive,
               requested_axis: :generation_time,
               fallback: :latest_projection
             }
           } = Enum.find(result.warnings, &(&1.code == :time_range_ignored))

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "returns an empty scalar frame with an informational warning when no state exists" do
    latest_fun = fn _organization_id, _mission_id, _point_id, _opts -> nil end

    result =
      Limits.resolve(
        source_request(),
        latest_fun: latest_fun
      )

    assert [%Frame{shape: :scalar, time_axis: :receipt_time, fields: fields} = frame] =
             result.frames

    assert Enum.all?(fields, &(&1.values == []))
    assert frame.meta.returned_points == 0
    refute result.meta.degraded?

    assert Enum.map(result.warnings, & &1.code) == [
             :watermark_unknown,
             :unknown_limit_definition
           ]
  end

  test "resolves observed limit event history into event frames" do
    first_receipt = ~U[2026-06-17 12:00:01Z]
    second_receipt = ~U[2026-06-17 12:00:02Z]
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:00:05Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})

      [
        event(point_id,
          limit_event_id: "limit-event-1",
          sample_id: "sample-1",
          normalized_state: :green,
          limit_state: :green,
          violation: false,
          receipt_time: first_receipt
        ),
        event(point_id,
          limit_event_id: "limit-event-2",
          sample_id: "sample-2",
          normalized_state: :red,
          limit_state: :red_high,
          violation: true,
          receipt_time: second_receipt
        )
      ]
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          definition_activation_key: "limit-activation-1",
          active_from: first_receipt,
          active_to: second_receipt
        ),
        definition_interval(point_id,
          definition_activation_key: "limit-activation-2",
          limit_definition_lifecycle_event_id: "limit-lifecycle-2",
          active_from: second_receipt,
          active_to: nil
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :event_history, products: [:event_history], limit: 250}
        ),
        history_fun: history_fun,
        interval_fun: interval_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "limits-request-1", frames: [frame]} = result
    assert %Frame{source: :limits, shape: :events, time_axis: :receipt_time} = frame

    assert [
             %Field{name: "time", kind: :time, values: [^first_receipt, ^second_receipt]},
             %Field{
               name: "limit_event_id",
               kind: :string,
               values: ["limit-event-1", "limit-event-2"]
             },
             %Field{name: "sample_id", kind: :string, values: ["sample-1", "sample-2"]},
             %Field{
               name: "limit_definition_id",
               kind: :string,
               values: ["limit-def-1", "limit-def-1"]
             },
             %Field{name: "limit_definition_version", kind: :number, values: [3, 3]},
             %Field{name: "normalized_state", kind: :enum, values: [:green, :red]},
             %Field{name: "limit_state", kind: :enum, values: [:green, :red_high]},
             %Field{name: "violation", kind: :boolean, values: [false, true]}
           ] = frame.fields

    assert frame.meta.sampling == :event_history
    assert frame.meta.analysis_basis == :observed_fact
    assert frame.meta.returned_events == 2

    assert [
             %{definition_activation_key: "limit-activation-1"},
             %{definition_activation_key: "limit-activation-2"}
           ] = frame.meta.selected_limit_definition_intervals

    assert Enum.map(frame.meta.evidence, & &1.kind) == [
             :limit_event,
             :limit_event,
             :limit_definition_interval,
             :limit_definition_lifecycle_event,
             :limit_definition,
             :limit_definition_interval,
             :limit_definition_lifecycle_event
           ]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:telemetry_point, "HK.counter"},
             {:limit_event, "limit-event-1"},
             {:limit_event, "limit-event-2"},
             {:limit_definition, "limit-def-1"},
             {:telemetry_sample, "sample-1"},
             {:telemetry_sample, "sample-2"}
           ]

    refute frame.meta.truncated?
    assert result.meta.supported_capability == :limit_event_history
    refute result.meta.degraded?

    assert_receive {:history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "managed_limits_projection"
    assert opts[:dataset] == "telemetry_latest_limit_states"
    assert opts[:semantics_mode] == :observed
    assert opts[:spacecraft_id] == "sc-1"
    assert opts[:from_receipt_time] == from_time
    assert opts[:to_receipt_time] == to_time
    assert opts[:limit] == 250
    assert opts[:order] == :asc

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:from_receipt_time] == from_time
    assert interval_opts[:to_receipt_time] == to_time
  end

  test "uses projection watermark when resolved data source supports watermarks" do
    parent = self()
    latest_receipt_time = ~U[2026-06-17 12:05:00Z]
    retention_starts_at = ~U[2026-06-17 11:00:00Z]

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      event(point_id, receipt_time: latest_receipt_time)
    end

    watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:watermark, organization_id, mission_id, point_id, opts})

      {:ok,
       %{
         complete_through: latest_receipt_time,
         latest_receipt_time: latest_receipt_time,
         retention_starts_at: retention_starts_at,
         sample_count: 2,
         confidence: :best_effort
       }}
    end

    result =
      Limits.resolve(
        source_request(),
        latest_fun: latest_fun,
        watermark_fun: watermark_fun,
        source_binding: source_binding(%{watermarks?: true})
      )

    assert [
             %SourceWatermark{
               confidence: :best_effort,
               complete_through: ^latest_receipt_time,
               latest_receipt_time: ^latest_receipt_time,
               retention_starts_at: ^retention_starts_at,
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             } = watermark
           ] = result.watermarks

    assert watermark.meta.point_watermarks["HK.counter"].sample_count == 2
    refute Enum.any?(result.warnings, &(&1.code == :watermark_unknown))
    assert [%Frame{} = frame] = result.frames
    refute :watermark_unknown in frame.meta.warning_codes

    assert_receive {:watermark, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "managed_limits_projection"
    assert opts[:dataset] == "telemetry_latest_limit_states"
    assert opts[:semantics_mode] == :observed
    assert opts[:spacecraft_id] == "sc-1"
  end

  test "resolves effective limit definition intervals into interval frames" do
    first_from = ~U[2026-06-17 12:00:00Z]
    second_from = ~U[2026-06-17 12:10:00Z]
    to_time = ~U[2026-06-17 12:20:00Z]
    parent = self()

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          limit_definition_id: "limit-def-1",
          limit_definition_version: 1,
          active_from: first_from,
          active_to: second_from,
          thresholds: %{
            "yellow_low" => 10,
            "yellow_high" => 90,
            "red_low" => 5,
            "red_high" => 95
          }
        ),
        definition_interval(point_id,
          limit_definition_lifecycle_event_id: "limit-lifecycle-2",
          definition_activation_key: "limit-activation-2",
          limit_definition_id: "limit-def-1",
          limit_definition_version: 2,
          active_from: second_from,
          active_to: nil,
          thresholds: %{
            "yellow_low" => 20,
            "yellow_high" => 80,
            "red_low" => 10,
            "red_high" => 90
          }
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: first_from, to: to_time},
          sampling: %{mode: :intervals, products: [:definition_intervals]}
        ),
        interval_fun: interval_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "limits-request-1", frames: [frame]} = result
    assert %Frame{source: :limits, shape: :intervals, time_axis: :receipt_time} = frame

    assert [
             %Field{name: "active_from", kind: :time, values: [^first_from, ^second_from]},
             %Field{name: "active_to", kind: :time, values: [^second_from, nil]},
             %Field{
               name: "limit_definition_id",
               kind: :string,
               values: ["limit-def-1", "limit-def-1"]
             },
             %Field{name: "limit_definition_version", kind: :number, values: [1, 2]},
             %Field{name: "limit_set_name", kind: :string, values: ["ops", "ops"]},
             %Field{name: "red_low", kind: :number, values: [5, 10]},
             %Field{name: "yellow_low", kind: :number, values: [10, 20]},
             %Field{name: "yellow_high", kind: :number, values: [90, 80]},
             %Field{name: "red_high", kind: :number, values: [95, 90]}
           ] = frame.fields

    assert frame.meta.sampling == :definition_intervals
    assert frame.meta.analysis_basis == :observed_fact
    assert frame.meta.returned_intervals == 2
    refute frame.meta.incomplete_intervals?
    assert result.meta.supported_capability == :limit_definition_intervals
    refute result.meta.degraded?

    assert [
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-1",
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-1"},
             %EvidenceRef{kind: :limit_definition, id: "limit-def-1", source: :limits},
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-2",
               source: :limits,
               confidence: :direct
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-2"}
           ] = frame.meta.evidence

    assert [
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-1"
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-1"},
             %EvidenceRef{kind: :limit_definition, id: "limit-def-1"},
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-2"
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-2"}
           ] = FrameEvidence.frame_evidence_refs(frame)

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:telemetry_point, "HK.counter"},
             {:limit_definition, "limit-def-1"}
           ]

    assert [
             %{
               limit_definition_lifecycle_event_id: "limit-lifecycle-1",
               active_from: ^first_from
             },
             %{
               limit_definition_lifecycle_event_id: "limit-lifecycle-2",
               active_from: ^second_from
             }
           ] = frame.meta.activation_evidence

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "managed_limits_projection"
    assert opts[:dataset] == "telemetry_latest_limit_states"
    assert opts[:semantics_mode] == :observed
    assert opts[:from_receipt_time] == first_from
    assert opts[:to_receipt_time] == to_time
    refute Keyword.has_key?(opts, :spacecraft_id)
  end

  test "warns when definition intervals cannot hydrate definition payloads" do
    interval_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [definition_interval(point_id, complete?: false, thresholds: %{})]
    end

    result =
      Limits.resolve(
        source_request(sampling: %{mode: :intervals, products: [:definition_intervals]}),
        interval_fun: interval_fun
      )

    assert [%Frame{meta: %{incomplete_intervals?: true, warning_codes: warning_codes}}] =
             result.frames

    assert :incomplete_limit_definition_intervals in warning_codes
    assert result.meta.degraded?

    assert %ResolveWarning{
             severity: :warning,
             details: %{missing_limit_definitions: [%{limit_definition_id: "limit-def-1"}]}
           } = Enum.find(result.warnings, &(&1.code == :incomplete_limit_definition_intervals))
  end

  test "rejects unsupported products before reading limits" do
    latest_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("latest state should not be read for unsupported products")
    end

    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("event history should not be read for unsupported products")
    end

    result =
      Limits.resolve(
        source_request(
          sampling: %{mode: :unknown_limit_product, products: [:unknown_limit_product]}
        ),
        latest_fun: latest_fun,
        history_fun: history_fun
      )

    assert %SourceResult{frames: [], warnings: warnings} = result
    assert result.meta.degraded?
    assert Enum.map(warnings, & &1.code) == [:watermark_unknown, :unsupported_limits_product]

    assert %ResolveWarning{
             severity: :warning,
             details: %{requested_product: :unknown_limit_product}
           } = Enum.find(warnings, &(&1.code == :unsupported_limits_product))
  end

  test "resolves recomputed latest limit state from latest telemetry sample" do
    receipt_time = ~U[2026-06-17 12:03:00Z]
    parent = self()

    latest_sample_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest_sample, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-latest", 96, receipt_time, "evidence-latest")
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: nil,
          thresholds: %{"yellow_high" => 90, "red_high" => 100}
        )
      ]
    end

    forbidden_latest_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("observed latest limit projection should not be read for recomputed analysis")
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :recomputed},
          sampling: %{mode: :latest_state},
          time_context: %{axis: :receipt_time, to: receipt_time}
        ),
        latest_sample_fun: latest_sample_fun,
        interval_fun: interval_fun,
        latest_fun: forbidden_latest_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    refute result.meta.degraded?
    assert result.meta.supported_capability == :recomputed_limit_analysis
    assert Enum.map(warnings, & &1.code) == [:watermark_unknown]
    assert frame.frame_id == "limits-request-1:HK.counter:latest_state:recomputed"
    assert frame.shape == :scalar
    assert frame.meta.sampling == :latest_state
    assert frame.meta.semantics_mode == :recomputed
    assert frame.meta.analysis_basis == :recomputed_analysis
    assert frame.meta.synthetic_limit_analysis?
    assert frame.meta.returned_points == 1
    assert frame.meta.source_sample_count == 1
    assert frame.meta.divergence_count == 0
    assert frame.meta.sample_id == "sample-latest"
    assert frame.meta.limit_definition_id == "limit-def-1"

    assert [
             %Field{name: "time", values: [^receipt_time]},
             %Field{name: "sample_id", values: ["sample-latest"]},
             %Field{name: "limit_definition_id", values: ["limit-def-1"]},
             %Field{name: "limit_definition_version", values: [1]},
             %Field{name: "normalized_state", values: [:yellow]},
             %Field{name: "limit_state", values: [:yellow_high]},
             %Field{name: "violation", values: [true]}
           ] = frame.fields

    assert %EvidenceRef{kind: :raw_evidence, id: "evidence-latest", source: :telemetry} =
             Enum.find(frame.meta.evidence, &(&1.kind == :raw_evidence))

    assert_receive {:latest_sample, "org-1", "mission-1", "HK.counter", latest_opts}
    assert latest_opts[:semantics_mode] == :recomputed
    assert latest_opts[:to_receipt_time] == receipt_time

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:semantics_mode] == :recomputed
  end

  test "compares recomputed latest limit state with observed latest projection" do
    receipt_time = ~U[2026-06-17 12:03:00Z]

    latest_sample_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-latest", 96, receipt_time, "evidence-latest")
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

    latest_fun = fn _organization_id, _mission_id, point_id, opts ->
      assert opts[:semantics_mode] == :observed

      event(point_id,
        limit_event_id: "observed-latest-limit",
        sample_id: "sample-latest",
        normalized_state: :green,
        limit_state: :green,
        violation: false,
        receipt_time: receipt_time
      )
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :compare},
          sampling: %{mode: :latest_state},
          time_context: %{axis: :receipt_time, to: receipt_time}
        ),
        latest_sample_fun: latest_sample_fun,
        interval_fun: interval_fun,
        latest_fun: latest_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    assert result.meta.degraded?
    assert result.meta.supported_capability == :limit_comparison_analysis
    assert frame.meta.semantics_mode == :compare
    assert frame.meta.analysis_basis == :limit_comparison_analysis
    assert frame.meta.observed_event_count == 1
    assert frame.meta.divergence_count == 1

    assert Enum.map(warnings, & &1.code) == [
             :watermark_unknown,
             :limit_analysis_diverged
           ]

    assert %Field{name: "normalized_state", values: [:yellow]} =
             Enum.find(frame.fields, &(&1.name == "normalized_state"))

    assert %Field{name: "observed_limit_event_id", values: ["observed-latest-limit"]} =
             Enum.find(frame.fields, &(&1.name == "observed_limit_event_id"))

    assert %Field{name: "observed_normalized_state", values: [:green]} =
             Enum.find(frame.fields, &(&1.name == "observed_normalized_state"))

    assert %Field{name: "limit_state_diverged", values: [true]} =
             Enum.find(frame.fields, &(&1.name == "limit_state_diverged"))
  end

  test "routes replay compare latest analysis through replay limit and telemetry filters" do
    receipt_time = ~U[2026-06-17 12:03:00Z]
    parent = self()

    latest_sample_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest_sample, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-replay-latest", 96, receipt_time, "evidence-replay-latest")
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: nil,
          thresholds: %{"yellow_high" => 90, "red_high" => 100}
        )
      ]
    end

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:observed_latest, organization_id, mission_id, point_id, opts})

      event(point_id,
        limit_event_id: "observed-replay-limit",
        sample_id: "sample-replay-latest",
        normalized_state: :green,
        limit_state: :green,
        violation: false,
        receipt_time: receipt_time
      )
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :compare},
          sampling: %{mode: :latest_state},
          time_context: %{
            mode: :replay_run,
            axis: :receipt_time,
            to: receipt_time,
            replay_run_id: "replay-run-1"
          },
          data_context: %{
            realm: :replay,
            replay_run_id: "replay-run-1",
            source_contexts: %{
              telemetry: %{
                data_source_id: "managed_telemetry_replay",
                source_binding_id: "replay_telemetry",
                dataset: "replay"
              }
            }
          }
        ),
        latest_sample_fun: latest_sample_fun,
        interval_fun: interval_fun,
        latest_fun: latest_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame]} = result
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.semantics_mode == :compare
    assert frame.meta.observed_event_count == 1

    assert_receive {:latest_sample, "org-1", "mission-1", "HK.counter", latest_opts}
    assert latest_opts[:realm] == :replay
    assert latest_opts[:data_source_id] == "managed_telemetry_replay"
    assert latest_opts[:source_binding_id] == "replay_telemetry"
    assert latest_opts[:dataset] == "replay"
    assert latest_opts[:replay_run_id] == "replay-run-1"
    assert latest_opts[:semantics_mode] == :compare

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:realm] == :replay
    assert interval_opts[:data_source_id] == "managed_limits_replay"
    assert interval_opts[:dataset] == "replay_limit_states"
    assert interval_opts[:replay_run_id] == "replay-run-1"
    assert interval_opts[:semantics_mode] == :compare

    assert_receive {:observed_latest, "org-1", "mission-1", "HK.counter", observed_opts}
    assert observed_opts[:realm] == :replay
    assert observed_opts[:data_source_id] == "managed_limits_replay"
    assert observed_opts[:dataset] == "replay_limit_states"
    assert observed_opts[:replay_run_id] == "replay-run-1"
    assert observed_opts[:semantics_mode] == :observed
  end

  test "resolves recomputed limit event history from telemetry samples and current definition" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:10:00Z]
    parent = self()

    sample_history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:sample_history, organization_id, mission_id, point_id, opts})

      [
        sample(point_id, "sample-1", 42, ~U[2026-06-17 12:01:00Z], "evidence-1"),
        sample(point_id, "sample-2", 96, ~U[2026-06-17 12:02:00Z], "evidence-2")
      ]
    end

    interval_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:intervals, organization_id, mission_id, point_id, opts})

      [
        definition_interval(point_id,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: nil,
          thresholds: %{
            "yellow_high" => 90,
            "red_high" => 100
          }
        )
      ]
    end

    forbidden_history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("observed limit events should not be read for recomputed analysis")
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :recomputed},
          sampling: %{mode: :event_history, products: [:event_history]},
          time_context: %{axis: :receipt_time, from: from_time, to: to_time}
        ),
        sample_history_fun: sample_history_fun,
        interval_fun: interval_fun,
        history_fun: forbidden_history_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    refute result.meta.degraded?
    assert result.meta.supported_capability == :recomputed_limit_analysis

    assert Enum.map(warnings, & &1.code) == [:watermark_unknown]
    assert frame.frame_id == "limits-request-1:HK.counter:recomputed"
    assert frame.meta.semantics_mode == :recomputed
    assert frame.meta.analysis_basis == :recomputed_analysis
    assert frame.meta.synthetic_limit_analysis?
    assert frame.meta.returned_events == 2
    assert frame.meta.source_sample_count == 2
    assert frame.meta.divergence_count == 0

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{name: "sample_id", values: ["sample-1", "sample-2"]},
             %Field{name: "limit_definition_id", values: ["limit-def-1", "limit-def-1"]},
             %Field{name: "limit_definition_version", values: [1, 1]},
             %Field{name: "normalized_state", values: [:green, :yellow]},
             %Field{name: "limit_state", values: [:green, :yellow_high]},
             %Field{name: "violation", values: [false, true]}
           ] = frame.fields

    assert [
             %EvidenceRef{kind: :raw_evidence, id: "evidence-1", source: :telemetry},
             %EvidenceRef{kind: :raw_evidence, id: "evidence-2", source: :telemetry},
             %EvidenceRef{
               kind: :limit_definition_interval,
               id: "effective_interval:limit_definition:limit-activation-1",
               source: :limits
             },
             %EvidenceRef{kind: :limit_definition_lifecycle_event, id: "limit-lifecycle-1"},
             %EvidenceRef{kind: :limit_definition, id: "limit-def-1", source: :limits}
           ] = frame.meta.evidence

    assert_receive {:sample_history, "org-1", "mission-1", "HK.counter", sample_opts}
    assert sample_opts[:semantics_mode] == :recomputed
    assert sample_opts[:from_receipt_time] == from_time
    assert sample_opts[:to_receipt_time] == to_time

    assert_receive {:intervals, "org-1", "mission-1", "HK.counter", interval_opts}
    assert interval_opts[:semantics_mode] == :recomputed
  end

  test "recomputed event history selects effective definition interval per sample receipt time" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:10:00Z]

    sample_history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-v1", 45, ~U[2026-06-17 12:01:00Z], "evidence-v1"),
        sample(point_id, "sample-v2", 45, ~U[2026-06-17 12:06:00Z], "evidence-v2")
      ]
    end

    interval_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        definition_interval(point_id,
          definition_activation_key: "limit-activation-v1",
          limit_definition_lifecycle_event_id: "limit-lifecycle-v1",
          limit_definition_id: "limit-def-v1",
          limit_definition_version: 1,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: ~U[2026-06-17 12:05:00Z],
          thresholds: %{"yellow_high" => 40, "red_high" => 90}
        ),
        definition_interval(point_id,
          definition_activation_key: "limit-activation-v2",
          limit_definition_lifecycle_event_id: "limit-lifecycle-v2",
          limit_definition_id: "limit-def-v2",
          limit_definition_version: 2,
          active_from: ~U[2026-06-17 12:05:00Z],
          active_to: nil,
          thresholds: %{"yellow_high" => 90, "red_high" => 100}
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :recomputed},
          sampling: %{mode: :event_history, products: [:event_history]},
          time_context: %{axis: :receipt_time, from: from_time, to: to_time}
        ),
        sample_history_fun: sample_history_fun,
        interval_fun: interval_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    refute result.meta.degraded?
    assert Enum.map(warnings, & &1.code) == [:watermark_unknown]
    assert frame.meta.returned_events == 2
    assert frame.meta.source_sample_count == 2
    assert frame.meta.selected_limit_clock.observed == :limit_event_receipt_time

    assert [
             %{definition_activation_key: "limit-activation-v1"},
             %{definition_activation_key: "limit-activation-v2"}
           ] = frame.meta.selected_limit_definition_intervals

    assert %Field{name: "sample_id", values: ["sample-v1", "sample-v2"]} =
             Enum.find(frame.fields, &(&1.name == "sample_id"))

    assert %Field{name: "limit_definition_id", values: ["limit-def-v1", "limit-def-v2"]} =
             Enum.find(frame.fields, &(&1.name == "limit_definition_id"))

    assert %Field{name: "limit_definition_version", values: [1, 2]} =
             Enum.find(frame.fields, &(&1.name == "limit_definition_version"))

    assert %Field{name: "normalized_state", values: [:yellow, :green]} =
             Enum.find(frame.fields, &(&1.name == "normalized_state"))

    assert %Field{name: "limit_state", values: [:yellow_high, :green]} =
             Enum.find(frame.fields, &(&1.name == "limit_state"))
  end

  test "recomputed event history warns when samples lack active complete definition intervals" do
    sample_history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-covered", 45, ~U[2026-06-17 12:01:00Z], "evidence-covered"),
        sample(point_id, "sample-missing", 45, ~U[2026-06-17 12:09:00Z], "evidence-missing")
      ]
    end

    interval_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        definition_interval(point_id,
          active_from: ~U[2026-06-17 11:00:00Z],
          active_to: ~U[2026-06-17 12:05:00Z],
          thresholds: %{"yellow_high" => 40}
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :recomputed},
          sampling: %{mode: :event_history, products: [:event_history]},
          time_context: %{
            axis: :receipt_time,
            from: ~U[2026-06-17 12:00:00Z],
            to: ~U[2026-06-17 12:10:00Z]
          }
        ),
        sample_history_fun: sample_history_fun,
        interval_fun: interval_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    assert result.meta.degraded?
    assert frame.meta.returned_events == 1
    assert frame.meta.source_sample_count == 2
    assert :incomplete_limit_evaluation in frame.meta.warning_codes

    assert %Field{name: "sample_id", values: ["sample-covered"]} =
             Enum.find(frame.fields, &(&1.name == "sample_id"))

    assert %ResolveWarning{
             details: %{
               requested_semantics_mode: :recomputed,
               selected_limit_clock: %{observed: :limit_event_receipt_time},
               missing_sample_ids: ["sample-missing"]
             }
           } = Enum.find(warnings, &(&1.code == :incomplete_limit_evaluation))
  end

  test "compares recomputed limit analysis with observed limit events and warns on divergence" do
    receipt_time = ~U[2026-06-17 12:02:00Z]

    sample_history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [sample(point_id, "sample-1", 96, receipt_time, "evidence-1")]
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
          normalized_state: :green,
          limit_state: :green,
          violation: false,
          receipt_time: receipt_time
        )
      ]
    end

    result =
      Limits.resolve(
        source_request(
          limit_context: %{semantics_mode: :compare},
          sampling: %{mode: :event_history, products: [:event_history]},
          time_context: %{axis: :receipt_time, from: receipt_time, to: receipt_time}
        ),
        sample_history_fun: sample_history_fun,
        interval_fun: interval_fun,
        history_fun: history_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = frame], warnings: warnings} = result
    assert result.meta.degraded?
    assert frame.meta.semantics_mode == :compare
    assert frame.meta.analysis_basis == :limit_comparison_analysis
    assert frame.meta.observed_event_count == 1
    assert frame.meta.divergence_count == 1

    assert Enum.map(warnings, & &1.code) == [
             :watermark_unknown,
             :limit_analysis_diverged
           ]

    assert %ResolveWarning{
             details: %{
               requested_semantics_mode: :compare,
               divergent_sample_ids: ["sample-1"],
               divergent_count: 1
             }
           } = Enum.find(warnings, &(&1.code == :limit_analysis_diverged))

    assert %Field{name: "normalized_state", values: [:yellow]} =
             Enum.find(frame.fields, &(&1.name == "normalized_state"))

    assert %Field{name: "observed_normalized_state", values: [:green]} =
             Enum.find(frame.fields, &(&1.name == "observed_normalized_state"))

    assert %Field{name: "limit_state_diverged", values: [true]} =
             Enum.find(frame.fields, &(&1.name == "limit_state_diverged"))

    assert %EvidenceRef{kind: :limit_event, id: "observed-limit-event-1"} =
             Enum.find(frame.meta.evidence, &(&1.kind == :limit_event))
  end

  defp source_request(overrides \\ []) do
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

  defp replay_source_binding(capabilities \\ %{}) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay_limits",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :replay,
        logical_source: :limits,
        data_source_id: "managed_limits_replay",
        dataset: "replay_limit_states"
      },
      data_source: %DataSource{
        data_source_id: "managed_limits_replay",
        owner: :cadence,
        kind: :projection,
        isolation_level: :mission,
        adapter: Limits,
        capabilities: capabilities
      },
      realm: :replay,
      dataset: "replay_limit_states"
    }
  end
end
