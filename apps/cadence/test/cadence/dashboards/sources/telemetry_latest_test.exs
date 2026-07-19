defmodule Cadence.Dashboards.Sources.TelemetryLatestTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.TelemetryFixtures

  alias Cadence.Dashboards.{
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    ResolveWarning,
    SourceResult
  }

  alias Cadence.Dashboards.Sources.Telemetry

  test "resolves latest telemetry into a scalar frame" do
    generation_time = ~U[2026-06-17 12:00:00Z]
    receipt_time = ~U[2026-06-17 12:00:01Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})

      sample(point_id, "sample-1", 12.4, receipt_time, "evidence-1",
        generation_time: generation_time
      )
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :generation_time},
          sampling: %{mode: :latest}
        ),
        latest_fun: latest_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "source-request-1", frames: [frame]} = result
    assert %Frame{source: :telemetry, shape: :scalar, time_axis: :generation_time} = frame

    assert [
             %Field{name: "time", kind: :time, values: [^generation_time]},
             %Field{name: "HK.counter", kind: :number, values: [12.4]} = value_field
           ] = frame.fields

    assert value_field.metadata.sample_ids == ["sample-1"]
    assert value_field.metadata.evidence_ids == ["evidence-1"]

    assert [%EvidenceRef{kind: :raw_evidence, id: "evidence-1"}] =
             value_field.metadata.evidence

    assert [
             %DataLink{target: :telemetry_point, target_id: "HK.counter", source: :field},
             %DataLink{target: :telemetry_sample, target_id: "sample-1", source: :field}
           ] = value_field.metadata.links

    assert frame.meta.sampling == :latest
    assert frame.meta.latest?
    assert frame.meta.returned_points == 1
    assert frame.meta.realm == :rehearsal
    assert frame.meta.data_source_id == "customer-questdb-rehearsal"
    refute result.meta.degraded?
    assert result.meta.supported_capability == :latest_value

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :rehearsal
    assert opts[:data_source_id] == "customer-questdb-rehearsal"
    assert opts[:dataset] == "rehearsal-12"
    assert opts[:validity_state] == :canonical
    assert opts[:spacecraft_id] == "sc-1"
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "routes replay latest telemetry through replay source filters" do
    receipt_time = ~U[2026-06-17 12:00:01Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-replay", 99, receipt_time, "evidence-replay")
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :receipt_time,
            replay_run_id: "replay-run-1"
          },
          data_context: %{
            realm: :replay,
            data_source_id: "managed_questdb_replay",
            replay_run_id: "replay-run-1"
          },
          sampling: %{mode: :latest}
        ),
        latest_fun: latest_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{}]} = result
    refute result.meta.degraded?

    assert_receive {:latest, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_questdb_replay"
    assert opts[:source_binding_id] == "binding-replay"
    assert opts[:dataset] == "replay-run-1"
    assert opts[:replay_run_id] == "replay-run-1"
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "resolves latest telemetry as of an archive receipt-time upper bound" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-1", 12.4, to_time, "evidence-1")
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :receipt_time,
            from: from_time,
            to: to_time
          },
          sampling: %{mode: :latest}
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

  test "warns when latest telemetry archive request has no receipt-time upper bound" do
    from_time = ~U[2026-06-17 12:00:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-1", 12.4, from_time, "evidence-1")
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :receipt_time,
            from: from_time
          },
          sampling: %{mode: :latest}
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

  test "warns when latest telemetry archive request uses a non-receipt time axis" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:latest, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-1", 12.4, to_time, "evidence-1")
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            mode: :archive,
            axis: :generation_time,
            from: from_time,
            to: to_time
          },
          sampling: %{mode: :latest}
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

  test "latest telemetry falls back to receipt time when generation time is absent" do
    receipt_time = ~U[2026-06-17 12:00:01Z]

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-1", :locked, receipt_time, nil)
    end

    result =
      Telemetry.resolve(
        source_request(sampling: %{mode: :latest}),
        latest_fun: latest_fun
      )

    assert [%Frame{shape: :scalar, time_axis: :receipt_time, fields: [time_field, value_field]}] =
             result.frames

    assert time_field.values == [receipt_time]
    assert value_field.kind == :enum
    assert value_field.values == [:locked]
  end
end
