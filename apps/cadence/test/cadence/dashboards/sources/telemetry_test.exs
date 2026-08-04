defmodule Cadence.Dashboards.Sources.TelemetryTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.TelemetryFixtures

  alias Cadence.Dashboards.{
    DashboardAction,
    DataLink,
    EvidenceRef,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceResult
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.Dashboards.Sources.Telemetry

  test "resolves bounded receipt-time history into telemetry frames" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})

      [
        sample(point_id, "sample-1", 41, from_time, "evidence-1"),
        sample(point_id, "sample-2", 42, to_time, "evidence-2")
      ]
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :raw_series, max_raw_points: 250}
        ),
        history_fun: history_fun
      )

    assert %SourceResult{request_id: "source-request-1", frames: [frame]} = result
    assert %Frame{source: :telemetry, shape: :wide, time_axis: :receipt_time} = frame
    assert frame.frame_id == "source-request-1:HK.counter"
    assert frame.scope.primary.ids == ["sc-1"]

    assert [
             %Field{name: "time", kind: :time, values: [^from_time, ^to_time]},
             %Field{name: "HK.counter", kind: :number, values: [41, 42]} = value_field
           ] = frame.fields

    assert value_field.metadata.observable_id == "HK.counter"
    assert value_field.metadata.point_id == "HK.counter"
    assert value_field.metadata.value_type == :engineering
    assert value_field.metadata.quality_states == [:good]
    assert value_field.metadata.sample_ids == ["sample-1", "sample-2"]
    assert value_field.metadata.evidence_ids == ["evidence-1", "evidence-2"]

    assert [
             %EvidenceRef{kind: :raw_evidence, id: "evidence-1", source: :telemetry},
             %EvidenceRef{kind: :raw_evidence, id: "evidence-2", source: :telemetry}
           ] = value_field.metadata.evidence

    assert [
             %DataLink{target: :telemetry_point, target_id: "HK.counter", source: :field} =
               point_link,
             %DataLink{target: :telemetry_sample, target_id: "sample-1", source: :field},
             %DataLink{target: :telemetry_sample, target_id: "sample-2", source: :field}
           ] = value_field.metadata.links

    assert point_link.context.time.axis == :receipt_time
    assert point_link.context.scope.primary.ids == ["sc-1"]

    assert Enum.any?(value_field.metadata.actions, fn
             %DashboardAction{
               target: :telemetry_explore,
               kind: :invoke,
               query: %{
                 "point_id" => "HK.counter",
                 "sample_id" => "sample-1",
                 "from" => "2026-06-17T12:00:00Z",
                 "to" => "2026-06-17T12:05:00Z",
                 "realm" => "flight",
                 "data_source_id" => "managed_questdb_primary"
               },
               source: :field
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(value_field.metadata.actions, fn
             %DashboardAction{target: :source_inventory, source: :field} -> true
             _other -> false
           end)

    assert frame.meta.returned_points == 2
    refute frame.meta.truncated?
    assert frame.meta.realm == :flight
    assert frame.meta.data_source_id == "managed_questdb_primary"
    assert frame.meta.data_view == :canonical
    assert frame.meta.analysis_basis == :observed_fact
    assert value_field.metadata.analysis_basis == :observed_fact
    assert frame.meta.evidence == value_field.metadata.evidence
    assert Enum.map(frame.meta.links, & &1.source) == [:frame, :frame, :frame]

    assert Enum.any?(frame.meta.actions, fn
             %DashboardAction{target: :telemetry_explore, source: :frame} -> true
             _other -> false
           end)

    assert Enum.any?(frame.meta.actions, fn
             %DashboardAction{target: :source_inventory, source: :frame} -> true
             _other -> false
           end)

    assert :watermark_unknown in frame.meta.warning_codes
    refute result.meta.degraded?

    assert [%SourceWatermark{confidence: :unknown, logical_source: :telemetry}] =
             result.watermarks

    assert [
             %ResolveWarning{
               code: :watermark_unknown,
               severity: :info,
               details: %{
                 actions: [
                   %DashboardAction{
                     target: :telemetry_explore,
                     kind: :invoke,
                     query: %{"point_id" => "HK.counter"},
                     source: :warning
                   }
                 ]
               },
               links: [
                 %DataLink{target: :telemetry_point, target_id: "HK.counter", source: :warning}
               ]
             }
           ] = result.warnings

    assert_receive {:history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "managed_questdb_primary"
    assert opts[:validity_state] == :canonical
    assert opts[:spacecraft_id] == "sc-1"
    assert opts[:from_receipt_time] == from_time
    assert opts[:to_receipt_time] == to_time
    assert opts[:limit] == 250
    assert opts[:order] == :asc
  end

  test "bounds live telemetry history to the configured moving window" do
    now = ~U[2026-06-17 12:05:00Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:live_history, organization_id, mission_id, point_id, opts})
      []
    end

    Telemetry.resolve(
      source_request(
        time_context: %{
          mode: :live,
          axis: :generation_time,
          window_seconds: 60
        },
        sampling: %{mode: :raw_series, max_raw_points: 250}
      ),
      history_fun: history_fun,
      now: now
    )

    assert_receive {:live_history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:from_observed_at] == ~U[2026-06-17 12:04:00Z]
    assert opts[:to_observed_at] == now
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "marks bounded receipt-time history partial when one requested observable is empty" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn
      _organization_id, _mission_id, "HK.counter", _opts ->
        [sample("HK.counter", "sample-1", 41, from_time, "evidence-1")]

      _organization_id, _mission_id, "HK.voltage", _opts ->
        []
    end

    result =
      Telemetry.resolve(
        source_request(
          observables: ["HK.counter", "HK.voltage"],
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :raw_series, max_raw_points: 250}
        ),
        history_fun: history_fun,
        source_binding: source_binding(%{bounded_history?: true, range_scan?: true})
      )

    assert %SourceResult{
             frames: [
               %Frame{meta: %{observable_id: "HK.counter", returned_points: 1}},
               %Frame{meta: %{observable_id: "HK.voltage", returned_points: 0}}
             ],
             warnings: warnings
           } = result

    assert [%ResolveWarning{code: :partial_data, severity: :warning} = warning] =
             Enum.filter(warnings, &(&1.code == :partial_data))

    assert warning.details.requested_observables == ["HK.counter", "HK.voltage"]
    assert warning.details.returned_observables == ["HK.counter"]
    assert warning.details.empty_observables == ["HK.voltage"]
    assert warning.details.data_source_id == "customer-questdb-rehearsal"
    assert warning.details.source_binding_id == "binding-rehearsal"
    assert warning.details.time_axis == :receipt_time
    assert result.meta.degraded?
  end

  test "marks latest telemetry partial when one requested observable is empty" do
    receipt_time = ~U[2026-06-17 12:00:00Z]

    latest_fun = fn
      _organization_id, _mission_id, "HK.counter", _opts ->
        sample("HK.counter", "sample-1", 41, receipt_time, "evidence-1")

      _organization_id, _mission_id, "HK.voltage", _opts ->
        nil
    end

    result =
      Telemetry.resolve(
        source_request(
          observables: ["HK.counter", "HK.voltage"],
          sampling: %{mode: :latest}
        ),
        latest_fun: latest_fun,
        source_binding: source_binding(%{latest?: true})
      )

    assert %SourceResult{
             frames: [
               %Frame{meta: %{observable_id: "HK.counter", returned_points: 1} = counter_meta},
               %Frame{meta: %{observable_id: "HK.voltage", returned_points: 0} = voltage_meta}
             ],
             warnings: warnings
           } = result

    assert :partial_data in counter_meta.warning_codes
    assert :partial_data in voltage_meta.warning_codes

    assert [%ResolveWarning{code: :partial_data, severity: :warning} = warning] =
             Enum.filter(warnings, &(&1.code == :partial_data))

    assert warning.details.requested_observables == ["HK.counter", "HK.voltage"]
    assert warning.details.returned_observables == ["HK.counter"]
    assert warning.details.empty_observables == ["HK.voltage"]
    assert warning.details.data_source_id == "customer-questdb-rehearsal"
    assert warning.details.source_binding_id == "binding-rehearsal"
    assert result.meta.degraded?
  end

  test "resolves bounded generation-time history into telemetry frames" do
    from_generation_time = ~U[2026-06-17 12:00:00Z]
    to_generation_time = ~U[2026-06-17 12:05:00Z]
    first_receipt_time = ~U[2026-06-17 12:30:00Z]
    second_receipt_time = ~U[2026-06-17 12:31:00Z]
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})

      [
        sample(point_id, "sample-1", 41, first_receipt_time, "evidence-1",
          generation_time: from_generation_time
        ),
        sample(point_id, "sample-2", 42, second_receipt_time, "evidence-2",
          generation_time: to_generation_time
        )
      ]
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :generation_time,
            replay_run_id: "replay-run-1",
            from: from_generation_time,
            to: to_generation_time
          },
          sampling: %{mode: :raw_series, max_raw_points: 250}
        ),
        history_fun: history_fun
      )

    assert %SourceResult{
             frames: [
               %Frame{source: :telemetry, shape: :wide, time_axis: :generation_time} = frame
             ],
             warnings: warnings
           } = result

    refute Enum.any?(warnings, &(&1.code == :unsupported_time_axis))

    assert [
             %Field{
               name: "time",
               kind: :time,
               values: [^from_generation_time, ^to_generation_time],
               metadata: %{axis: :generation_time}
             },
             %Field{name: "HK.counter", kind: :number, values: [41, 42]}
           ] = frame.fields

    assert frame.meta.replay_run_id == "replay-run-1"
    assert result.meta.supported_capability == :bounded_generation_time_history

    assert_receive {:history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:time_axis] == :generation_time
    assert opts[:from_observed_at] == from_generation_time
    assert opts[:to_observed_at] == to_generation_time
    refute Keyword.has_key?(opts, :from_receipt_time)
    refute Keyword.has_key?(opts, :to_receipt_time)
  end

  test "attaches selected source-binding interval evidence to telemetry frames and fields" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-1", 41, from_time, "evidence-1"),
        sample(point_id, "sample-2", 42, to_time, "evidence-2")
      ]
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :raw_series}
        ),
        history_fun: history_fun,
        source_binding: source_binding_with_interval()
      )

    assert %SourceResult{frames: [frame]} = result
    assert [%Field{name: "time"}, %Field{name: "HK.counter"} = value_field] = frame.fields

    assert [
             %EvidenceRef{kind: :raw_evidence, id: "evidence-1", source: :telemetry},
             %EvidenceRef{kind: :raw_evidence, id: "evidence-2", source: :telemetry},
             %EvidenceRef{
               kind: :source_binding_interval,
               id: "effective_interval:source_binding:binding-event-rehearsal-1",
               source: :telemetry,
               confidence: :projected
             },
             %EvidenceRef{
               kind: :source_binding_event,
               id: "binding-event-rehearsal-1",
               source: :telemetry,
               confidence: :direct
             },
             %EvidenceRef{
               kind: :source_binding,
               id: "binding-rehearsal",
               source: :telemetry,
               confidence: :direct
             }
           ] = frame.meta.evidence

    assert value_field.metadata.evidence == frame.meta.evidence
  end

  test "uses data-management view to choose telemetry selection policy" do
    parent = self()

    history_fun = fn _organization_id, _mission_id, _point_id, opts ->
      send(parent, {:history_opts, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(
          data_context: %{
            realm: :flight,
            data_source_id: "managed_questdb_primary",
            view: :all_revisions
          }
        ),
        history_fun: history_fun
      )

    assert [%Frame{}] = result.frames
    assert [frame] = result.frames
    assert frame.meta.data_view == :all_revisions
    assert frame.meta.analysis_basis == :observed_fact
    assert :all_revisions_view in frame.meta.warning_codes

    assert %ResolveWarning{
             code: :all_revisions_view,
             severity: :warning,
             details: %{
               data_view: :all_revisions,
               canonical_default?: false,
               point_id: "HK.counter",
               observable_id: "HK.counter"
             }
           } = Enum.find(result.warnings, &(&1.code == :all_revisions_view))

    assert Enum.any?(frame.meta.actions, fn
             %DashboardAction{
               target: :telemetry_explore,
               source: :frame,
               query: %{"point_id" => "HK.counter", "data_view" => "all_revisions"}
             } ->
               true

             _other ->
               false
           end)

    assert_receive {:history_opts, opts}
    refute Keyword.has_key?(opts, :validity_state)

    result =
      Telemetry.resolve(
        source_request(
          data_context: %{
            realm: :flight,
            data_source_id: "managed_questdb_primary",
            view: :all_revisions,
            validity_state: :conflict
          }
        ),
        history_fun: history_fun
      )

    assert [%Frame{}] = result.frames
    assert_receive {:history_opts, opts}
    assert opts[:validity_state] == :conflict
  end

  test "uses source-specific data-management view overrides for telemetry reads" do
    parent = self()

    history_fun = fn _organization_id, _mission_id, _point_id, opts ->
      send(parent, {:history_opts, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(
          data_context: %{
            realm: :flight,
            data_source_id: "managed_questdb_primary",
            view: :canonical,
            source_contexts: %{
              telemetry: %{view: :as_recorded}
            }
          }
        ),
        history_fun: history_fun
      )

    assert [%Frame{}] = result.frames
    assert [frame] = result.frames
    assert frame.meta.data_view == :as_recorded
    assert frame.meta.analysis_basis == :observed_fact
    assert :as_recorded_view in frame.meta.warning_codes

    assert %ResolveWarning{code: :as_recorded_view, severity: :info} =
             Enum.find(result.warnings, &(&1.code == :as_recorded_view))

    assert_receive {:history_opts, opts}
    refute Keyword.has_key?(opts, :validity_state)
  end

  test "classifies recomputed telemetry frames as recomputed analysis" do
    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [sample(point_id, "sample-recomputed", 41, ~U[2026-06-17 12:00:00Z], "evidence-1")]
    end

    result =
      Telemetry.resolve(
        source_request(
          data_context: %{
            realm: :flight,
            data_source_id: "managed_questdb_primary",
            view: :recomputed
          }
        ),
        history_fun: history_fun
      )

    assert %SourceResult{frames: [%Frame{} = frame]} = result
    assert frame.meta.data_view == :recomputed
    assert frame.meta.analysis_basis == :recomputed_analysis
    assert :recomputed_values in frame.meta.warning_codes

    assert [
             %Field{name: "time"},
             %Field{name: "HK.counter", metadata: %{analysis_basis: :recomputed_analysis}}
           ] = frame.fields
  end

  test "adds observation identity revision metadata and warnings to telemetry frames" do
    parent = self()
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-canonical", 41, from_time, "evidence-canonical",
          provenance: storage_provenance("identity-canonical")
        ),
        sample(point_id, "sample-conflict", 42, to_time, "evidence-conflict",
          provenance: storage_provenance("identity-conflict")
        )
      ]
    end

    identity_states_fun = fn identity_ids, lookup_opts ->
      send(parent, {:identity_states, identity_ids, lookup_opts})

      [
        identity_state("identity-canonical"),
        identity_state("identity-conflict",
          validity_state: :conflict,
          conflict_count: 1,
          decision_event_id: "decision-conflict",
          decided_at: ~U[2026-06-17 12:06:00Z]
        )
      ]
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :raw_series}
        ),
        history_fun: history_fun,
        identity_states_fun: identity_states_fun
      )

    assert [%Frame{} = frame] = result.frames

    assert_receive {:identity_states, ["identity-canonical", "identity-conflict"], lookup_opts}
    assert lookup_opts[:organization_id] == "org-1"
    assert lookup_opts[:mission_id] == "mission-1"
    assert lookup_opts[:realm] == :flight
    assert lookup_opts[:data_source_id] == "managed_questdb_primary"
    refute Keyword.has_key?(lookup_opts, :binding_id)

    assert frame.meta.revision_state.identity_count == 2
    assert frame.meta.revision_state.conflict_count == 1
    assert frame.meta.revision_state.has_conflicts?
    refute frame.meta.revision_state.has_duplicates?

    assert String.starts_with?(
             frame.meta.revision_state.dependency_fingerprint,
             "telemetry-revision:"
           )

    assert frame.meta.telemetry_revision_dependency == frame.meta.revision_state.dependency

    assert frame.meta.telemetry_revision_dependency.observation_identity_ids == [
             "identity-canonical",
             "identity-conflict"
           ]

    assert result.meta.telemetry_revision_dependency == frame.meta.telemetry_revision_dependency
    assert :conflicting_observations in frame.meta.warning_codes
    assert :mixed_revisions in frame.meta.warning_codes

    assert %EvidenceRef{
             kind: :telemetry_revision_decision_event,
             id: "decision-conflict",
             observed_at: ~U[2026-06-17 12:06:00Z],
             source: :events,
             confidence: :direct
           } in frame.meta.evidence

    assert Enum.map(result.warnings, & &1.code) == [
             :watermark_unknown,
             :conflicting_observations,
             :mixed_revisions
           ]

    assert %ResolveWarning{
             scope: :frame,
             frame_id: "source-request-1:HK.counter",
             details: %{identity_count: 2, conflict_count: 1, point_id: "HK.counter"}
           } = Enum.find(result.warnings, &(&1.code == :conflicting_observations))

    assert result.meta.degraded?
  end

  test "adds active historical workflow metadata to matching telemetry frames" do
    parent = self()
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [
        sample(point_id, "sample-1", 41, from_time, "evidence-1"),
        sample(point_id, "sample-2", 42, to_time, "evidence-2")
      ]
    end

    backfill_lifecycle_events_fun = fn mission_id, lookup_opts ->
      send(parent, {:backfill_lifecycle_events, mission_id, lookup_opts})

      [
        backfill_lifecycle_event("completed-run", :backfill_started,
          backfill_lifecycle_event_id: "completed-started",
          occurred_at: ~U[2026-06-17 11:59:00Z]
        ),
        backfill_lifecycle_event("completed-run", :backfill_completed,
          backfill_lifecycle_event_id: "completed-finished",
          occurred_at: ~U[2026-06-17 12:01:00Z]
        ),
        backfill_lifecycle_event("late-data-run", :late_data_rejected,
          backfill_lifecycle_event_id: "late-data-rejected",
          occurred_at: ~U[2026-06-17 12:04:00Z]
        ),
        backfill_lifecycle_event("active-run", :backfill_started,
          backfill_lifecycle_event_id: "active-started",
          occurred_at: ~U[2026-06-17 12:02:00Z]
        ),
        backfill_lifecycle_event("other-point-run", :import_started,
          backfill_lifecycle_event_id: "other-point-started",
          point_id: "HK.voltage",
          occurred_at: ~U[2026-06-17 12:03:00Z]
        ),
        backfill_lifecycle_event("other-point-run", :import_completed,
          backfill_lifecycle_event_id: "other-point-finished",
          point_id: "HK.voltage",
          occurred_at: ~U[2026-06-17 12:04:00Z]
        )
      ]
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :raw_series}
        ),
        history_fun: history_fun,
        backfill_lifecycle_events_fun: backfill_lifecycle_events_fun
      )

    assert [%Frame{} = frame] = result.frames

    assert_receive {:backfill_lifecycle_events, "mission-1", lookup_opts}
    assert lookup_opts[:organization_id] == "org-1"
    assert lookup_opts[:realm] == :flight
    assert lookup_opts[:data_source_id] == "managed_questdb_primary"
    assert lookup_opts[:source_from] == from_time
    assert lookup_opts[:source_to] == to_time

    assert [
             %{
               category: :telemetry_backfill,
               kind: :backfill_started,
               source_record_id: "active-started",
               run_id: "active-run",
               point_id: "HK.counter",
               occurred_at: ~U[2026-06-17 12:02:00Z]
             }
           ] = frame.meta.active_historical_workflows

    assert [
             %{
               category: :telemetry_backfill,
               kind: :backfill_completed,
               source_record_id: "completed-finished",
               run_id: "completed-run",
               point_id: "HK.counter",
               occurred_at: ~U[2026-06-17 12:01:00Z]
             },
             %{
               category: :telemetry_backfill,
               kind: :late_data_rejected,
               source_record_id: "late-data-rejected",
               run_id: "late-data-run",
               point_id: "HK.counter",
               occurred_at: ~U[2026-06-17 12:04:00Z]
             }
           ] = Enum.sort_by(frame.meta.historical_workflow_outcomes, & &1.source_record_id)

    assert %EvidenceRef{
             kind: :telemetry_backfill_lifecycle_event,
             id: "active-started",
             observed_at: ~U[2026-06-17 12:02:00Z],
             source: :events,
             confidence: :direct
           } in frame.meta.evidence

    assert %EvidenceRef{
             kind: :telemetry_backfill_lifecycle_event,
             id: "completed-finished",
             observed_at: ~U[2026-06-17 12:01:00Z],
             source: :events,
             confidence: :direct
           } in frame.meta.evidence

    assert %EvidenceRef{
             kind: :telemetry_backfill_lifecycle_event,
             id: "late-data-rejected",
             observed_at: ~U[2026-06-17 12:04:00Z],
             source: :events,
             confidence: :direct
           } in frame.meta.evidence

    refute Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :telemetry_backfill_lifecycle_event, id: "completed-started"} ->
               true

             %EvidenceRef{kind: :telemetry_backfill_lifecycle_event, id: "other-point-started"} ->
               true

             %EvidenceRef{kind: :telemetry_backfill_lifecycle_event, id: "other-point-finished"} ->
               true

             _ref ->
               false
           end)
  end

  test "scopes active historical workflow lookup to replay run" do
    parent = self()
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:history_opts, opts})
      [sample(point_id, "sample-1", 41, from_time, "evidence-1")]
    end

    backfill_lifecycle_events_fun = fn mission_id, lookup_opts ->
      send(parent, {:backfill_lifecycle_events, mission_id, lookup_opts})
      []
    end

    Telemetry.resolve(
      source_request(
        time_context: %{
          mode: :replay_run,
          axis: :receipt_time,
          from: from_time,
          to: to_time,
          replay_run_id: "replay-run-1"
        },
        data_context: %{
          realm: :replay,
          data_source_id: "managed_questdb_replay",
          replay_run_id: "replay-run-1"
        },
        sampling: %{mode: :raw_series}
      ),
      history_fun: history_fun,
      backfill_lifecycle_events_fun: backfill_lifecycle_events_fun
    )

    assert_receive {:history_opts, history_opts}
    assert_receive {:backfill_lifecycle_events, "mission-1", lookup_opts}
    assert history_opts[:replay_run_id] == "replay-run-1"
    assert lookup_opts[:organization_id] == "org-1"
    assert lookup_opts[:realm] == :replay
    assert lookup_opts[:replay_run_id] == "replay-run-1"
    assert lookup_opts[:data_source_id] == "managed_questdb_replay"
    assert lookup_opts[:source_from] == from_time
    assert lookup_opts[:source_to] == to_time
  end

  test "surfaces exhausted telemetry history candidate windows as frame warnings" do
    diagnostics = %{
      effective_selection?: true,
      physical_candidate_count: 2,
      logical_selected_count: 0,
      requested_logical_limit: 1,
      physical_candidate_limit: 2,
      candidate_window_exhausted?: true
    }

    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:ok, %{samples: [], diagnostics: diagnostics}}
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{
            axis: :receipt_time,
            from: ~U[2026-06-17 12:00:00Z],
            to: ~U[2026-06-17 12:05:00Z]
          },
          sampling: %{mode: :raw_series, max_raw_points: 1}
        ),
        history_fun: history_fun
      )

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.history_diagnostics == diagnostics
    assert :candidate_window_exhausted in frame.meta.warning_codes

    assert %ResolveWarning{
             severity: :warning,
             scope: :frame,
             frame_id: "source-request-1:HK.counter",
             details: %{
               physical_candidate_count: 2,
               logical_selected_count: 0,
               requested_logical_limit: 1,
               physical_candidate_limit: 2,
               candidate_window_exhausted?: true
             }
           } = Enum.find(result.warnings, &(&1.code == :candidate_window_exhausted))

    assert result.meta.degraded?
  end

  test "degrades bounded history query failures with source health actions" do
    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:error, {:http_error, 400, %{"error" => "Invalid column: observation_identity_id"}}}
    end

    result =
      Telemetry.resolve(
        source_request([]),
        history_fun: history_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [], warnings: warnings} = result
    assert result.meta.degraded?

    assert %ResolveWarning{
             code: :source_unavailable,
             severity: :error,
             details: details
           } = Enum.find(warnings, &(&1.code == :source_unavailable))

    assert details.source_query_kind == :bounded_history
    assert details.unresolved_capability == :bounded_receipt_time_history
    assert details.reason =~ "observation_identity_id"
    assert details.source_empty_reason == :source_query_failed
    assert details.data_source_id == "customer-questdb-rehearsal"
    assert details.source_binding_id == "binding-rehearsal"
    assert details.realm == :rehearsal
    assert details.dataset == "rehearsal-12"
    assert details.requested_sampling == :raw_series

    assert Enum.any?(details.actions, fn
             %DashboardAction{
               target: :source_health,
               kind: :invoke,
               query: %{
                 "data_source_id" => "customer-questdb-rehearsal",
                 "source_binding_id" => "binding-rehearsal",
                 "source_empty_reason" => "source_query_failed"
               },
               source: :warning
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(details.actions, fn
             %DashboardAction{target: :telemetry_explore, source: :warning} -> true
             _other -> false
           end)
  end

  test "uses explicit tenant and mission fields before scope context fallback" do
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(
          organization_id: "org-direct",
          mission_id: "mission-direct",
          scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}}
        ),
        history_fun: history_fun
      )

    assert [%Frame{}] = result.frames
    assert_receive {:history, "org-direct", "mission-direct", "HK.counter", _opts}
  end

  test "does not treat non-spacecraft primary scope ids as spacecraft filters" do
    parent = self()

    history_fun = fn _organization_id, _mission_id, _point_id, opts ->
      send(parent, {:history_opts, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(
          scope_context: %{
            primary: %{kind: "contact", mode: "one", ids: ["contact-1"]}
          }
        ),
        history_fun: history_fun,
        fetch_scheduled_contact: fn _organization_id, _mission_id, _contact_id ->
          {:error, :scheduled_contact_not_found}
        end,
        fetch_realized_contact: fn _organization_id, _mission_id, _contact_id ->
          {:error, :realized_contact_not_found}
        end
      )

    assert [%Frame{}] = result.frames
    assert_receive {:history_opts, opts}
    refute Keyword.has_key?(opts, :spacecraft_id)
  end

  test "resolves contact scope into telemetry source endpoint filters" do
    parent = self()

    history_fun = fn _organization_id, _mission_id, _point_id, opts ->
      send(parent, {:history_opts, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(
          scope_context: %{
            primary: %{kind: "contact", mode: "one", ids: ["contact-1"]}
          }
        ),
        history_fun: history_fun,
        fetch_scheduled_contact: fn "org-1", "mission-1", "contact-1" ->
          {:ok, %{scheduled_contact_id: "contact-1", source_endpoint_refs: ["endpoint-a"]}}
        end
      )

    assert [%Frame{}] = result.frames
    assert_receive {:history_opts, opts}
    assert opts[:source_endpoint_ids] == ["endpoint-a"]
  end

  test "applies contact source endpoint filters to latest telemetry reads" do
    parent = self()

    latest_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:latest_opts, opts})
      sample(point_id, "sample-1", 5, ~U[2026-06-17 12:00:00Z], "evidence-1")
    end

    result =
      Telemetry.resolve(
        source_request(
          scope_context: %{
            primary: %{kind: "contact", mode: "one", ids: ["contact-1"]}
          },
          sampling: %{mode: :latest}
        ),
        latest_fun: latest_fun,
        fetch_scheduled_contact: fn "org-1", "mission-1", "contact-1" ->
          {:ok, %{scheduled_contact_id: "contact-1", source_endpoint_refs: ["endpoint-a"]}}
        end
      )

    assert [%Frame{}] = result.frames
    assert_receive {:latest_opts, opts}
    assert opts[:source_endpoint_ids] == ["endpoint-a"]
  end

  test "uses resolved source binding for realm, data source, and dataset" do
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})
      [sample(point_id, "sample-1", 5, ~U[2026-06-17 12:00:00Z], "evidence-1")]
    end

    source_binding = source_binding()

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
          data_context: %{
            realm: :flight,
            data_source_id: "ignored-context-source",
            replay_run_id: "replay-run-1"
          }
        ),
        history_fun: history_fun,
        source_binding: source_binding
      )

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.source_binding_id == "binding-rehearsal"
    assert frame.meta.realm == :rehearsal
    assert frame.meta.data_source_id == "customer-questdb-rehearsal"
    assert frame.meta.dataset == "rehearsal-12"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert [%{context: link_context} | _rest] = frame.meta.links
    assert link_context.data.replay_run_id == "replay-run-1"
    assert link_context.time.replay_run_id == "replay-run-1"

    assert [%{query: explore_query} | _source_actions] =
             Enum.filter(frame.meta.actions, &(&1.target == :telemetry_explore))

    assert explore_query["replay_run_id"] == "replay-run-1"

    assert [
             %SourceWatermark{
               realm: :rehearsal,
               data_source_id: "customer-questdb-rehearsal",
               source_binding_id: "binding-rehearsal",
               dataset: "rehearsal-12",
               replay_run_id: "replay-run-1",
               confidence: :unknown
             }
           ] =
             result.watermarks

    assert_receive {:history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :rehearsal
    assert opts[:data_source_id] == "customer-questdb-rehearsal"
    assert opts[:dataset] == "rehearsal-12"
    assert opts[:replay_run_id] == "replay-run-1"
  end

  test "uses source watermark when resolved data source supports watermarks" do
    parent = self()
    latest_receipt_time = ~U[2026-06-17 12:05:00Z]
    retention_starts_at = ~U[2026-06-17 11:00:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [sample(point_id, "sample-1", 5, latest_receipt_time, "evidence-1")]
    end

    watermark_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:watermark, organization_id, mission_id, point_id, opts})

      {:ok,
       %{
         complete_through: latest_receipt_time,
         latest_receipt_time: latest_receipt_time,
         retention_starts_at: retention_starts_at,
         sample_count: 42,
         confidence: :best_effort
       }}
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{mode: :replay_run, axis: :receipt_time, replay_run_id: "replay-run-1"},
          data_context: %{
            realm: :flight,
            data_source_id: "ignored-context-source",
            replay_run_id: "replay-run-1"
          }
        ),
        history_fun: history_fun,
        watermark_fun: watermark_fun,
        source_binding: source_binding(%{watermarks?: true})
      )

    assert [
             %SourceWatermark{
               confidence: :best_effort,
               complete_through: ^latest_receipt_time,
               latest_receipt_time: ^latest_receipt_time,
               retention_starts_at: ^retention_starts_at,
               data_source_id: "customer-questdb-rehearsal",
               source_binding_id: "binding-rehearsal",
               replay_run_id: "replay-run-1"
             } = watermark
           ] = result.watermarks

    assert watermark.meta.point_watermarks["HK.counter"].sample_count == 42
    refute Enum.any?(result.warnings, &(&1.code == :watermark_unknown))
    assert [%Frame{} = frame] = result.frames
    refute :watermark_unknown in frame.meta.warning_codes

    assert_receive {:watermark, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :rehearsal
    assert opts[:data_source_id] == "customer-questdb-rehearsal"
    assert opts[:dataset] == "rehearsal-12"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:validity_state] == :canonical
    assert opts[:spacecraft_id] == "sc-1"
  end

  test "surfaces watermark query failures with source health actions" do
    latest_receipt_time = ~U[2026-06-17 12:05:00Z]

    history_fun = fn _organization_id, _mission_id, point_id, _opts ->
      [sample(point_id, "sample-1", 5, latest_receipt_time, "evidence-1")]
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:error, {:http_error, 400, %{"error" => "table does not exist"}}}
    end

    result =
      Telemetry.resolve(
        source_request([]),
        history_fun: history_fun,
        watermark_fun: watermark_fun,
        source_binding: source_binding(%{watermarks?: true})
      )

    assert [%Frame{} = frame] = result.frames
    refute result.meta.degraded?
    assert :watermark_unknown in frame.meta.warning_codes

    assert %ResolveWarning{
             code: :watermark_unknown,
             severity: :info,
             details: details
           } = Enum.find(result.warnings, &(&1.code == :watermark_unknown))

    assert details.source_query_kind == :watermark
    assert details.unresolved_capability == :source_watermark
    assert details.reason =~ "table does not exist"
    assert details.source_empty_reason == :source_query_failed

    assert Enum.any?(details.actions, fn
             %DashboardAction{
               target: :source_health,
               query: %{"source_empty_reason" => "source_query_failed"}
             } ->
               true

             _other ->
               false
           end)
  end

  test "returns one coherent frame per observable" do
    parent = self()

    history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:history, organization_id, mission_id, point_id, opts})
      [sample(point_id, "sample-#{point_id}", point_id, ~U[2026-06-17 12:00:00Z], nil)]
    end

    result =
      Telemetry.resolve(
        source_request(observables: ["HK.counter", "radio.bit_rate"]),
        history_fun: history_fun
      )

    assert Enum.map(result.frames, & &1.frame_id) == [
             "source-request-1:HK.counter",
             "source-request-1:radio.bit_rate"
           ]

    assert [
             %Field{name: "time"},
             %Field{name: "HK.counter", kind: :string, values: ["HK.counter"]}
           ] = Enum.at(result.frames, 0).fields

    assert [
             %Field{name: "time"},
             %Field{name: "radio.bit_rate", kind: :string, values: ["radio.bit_rate"]}
           ] = Enum.at(result.frames, 1).fields

    assert_receive {:history, "org-1", "mission-1", "HK.counter", _opts}
    assert_receive {:history, "org-1", "mission-1", "radio.bit_rate", _opts}
  end

  test "falls back to receipt-time bounds with an unsupported time axis warning" do
    history_fun = fn _organization_id, _mission_id, _point_id, _opts -> [] end

    result =
      Telemetry.resolve(
        source_request(time_context: %{axis: :occurred_at, from: ~U[2026-06-17 12:00:00Z]}),
        history_fun: history_fun
      )

    assert [%Frame{time_axis: :receipt_time, fields: [_time_field, value_field]}] = result.frames
    assert value_field.values == []

    assert Enum.map(result.warnings, & &1.code) == [
             :watermark_unknown,
             :unsupported_time_axis
           ]

    assert %ResolveWarning{
             code: :unsupported_time_axis,
             details: %{
               requested_axis: :occurred_at,
               fallback_axis: :receipt_time,
               actions: [
                 %DashboardAction{
                   target: :telemetry_explore,
                   kind: :invoke,
                   query: %{"point_id" => "HK.counter"},
                   source: :warning
                 }
               ]
             }
           } = Enum.find(result.warnings, &(&1.code == :unsupported_time_axis))
  end

  test "falls back to receipt-time bounds when source capabilities exclude generation time" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:05:00Z]
    parent = self()

    history_fun = fn _organization_id, _mission_id, _point_id, opts ->
      send(parent, {:history_opts, opts})
      []
    end

    result =
      Telemetry.resolve(
        source_request(time_context: %{axis: :generation_time, from: from_time, to: to_time}),
        history_fun: history_fun,
        supported_time_axes: [:receipt_time]
      )

    assert_receive {:history_opts, opts}
    assert Keyword.fetch!(opts, :time_axis) == :receipt_time
    assert Keyword.fetch!(opts, :from_receipt_time) == from_time
    assert Keyword.fetch!(opts, :to_receipt_time) == to_time
    refute Keyword.has_key?(opts, :from_observed_at)
    refute Keyword.has_key?(opts, :to_observed_at)

    assert [%Frame{time_axis: :receipt_time}] = result.frames

    assert %ResolveWarning{
             code: :unsupported_time_axis,
             details: %{
               requested_time_axis: :generation_time,
               executed_time_axis: :receipt_time,
               supported_time_axes: [:receipt_time]
             }
           } = Enum.find(result.warnings, &(&1.code == :unsupported_time_axis))
  end

  test "resolves native decimated envelope history into bucket frames" do
    from_time = ~U[2026-06-17 12:00:00Z]
    mid_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:02:00Z]
    parent = self()

    decimated_history_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:decimated_history, organization_id, mission_id, point_id, opts})

      {:ok,
       %{
         buckets: [
           %{
             bucket_start: from_time,
             bucket_end: mid_time,
             min: 40,
             max: 44,
             mean: 42,
             unit: "counts",
             sample_count: 12,
             worst_quality_state: :good,
             worst_validity_state: :canonical
           },
           %{
             bucket_start: mid_time,
             bucket_end: to_time,
             min: 41,
             max: 45,
             value: 43,
             unit: "counts",
             sample_count: 15,
             worst_quality_state: :suspect,
             worst_validity_state: :canonical
           }
         ],
         diagnostics: %{
           canonical_mode: :physical,
           aggregate_semantics: :physical_as_recorded,
           bucket_count: 2,
           bucket_width_ms: 60_000
         }
       }}
    end

    result =
      Telemetry.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{mode: :decimated_envelope, target_points: 320, bucket_width_ms: 60_000}
        ),
        decimated_history_fun: decimated_history_fun,
        source_binding: source_binding(%{native_decimation?: true})
      )

    assert %SourceResult{request_id: "source-request-1", frames: [frame]} = result
    assert %Frame{source: :telemetry, shape: :wide, time_axis: :receipt_time} = frame
    assert frame.meta.sampling == :decimated_envelope
    assert frame.meta.decimation == :native_min_max_envelope
    assert frame.meta.canonical_mode == :physical
    assert frame.meta.aggregate_semantics == :physical_as_recorded
    assert frame.meta.target_points == 320
    assert frame.meta.bucket_width_ms == 60_000
    assert frame.meta.returned_points == 2
    assert frame.meta.decimated_diagnostics.bucket_count == 2
    assert frame.meta.decimated_diagnostics.bucket_width_ms == 60_000
    assert :physical_aggregate_semantics in frame.meta.warning_codes
    assert result.meta.supported_capability == :native_decimated_envelope
    refute result.meta.degraded?

    assert [
             %Field{name: "bucket_start", values: [^from_time, ^mid_time]},
             %Field{name: "bucket_end", values: [^mid_time, ^to_time]},
             %Field{name: "HK.counter_min", values: [40, 41]} = min_field,
             %Field{name: "HK.counter_max", values: [44, 45]},
             %Field{name: "HK.counter_value", values: [42, 43]},
             %Field{name: "HK.counter_sample_count", values: [12, 15]}
           ] = frame.fields

    assert min_field.metadata.decimated?
    assert min_field.metadata.decimation == :native_min_max_envelope
    assert min_field.metadata.canonical_mode == :physical
    assert min_field.metadata.aggregate_semantics == :physical_as_recorded
    assert min_field.metadata.unit == "counts"
    assert min_field.metadata.quality_states == [:good, :suspect]

    assert %ResolveWarning{
             severity: :info,
             details: %{
               canonical_mode: :physical,
               aggregate_semantics: :physical_as_recorded,
               affected_products: [:native_decimated_envelope, :source_watermark]
             }
           } = Enum.find(result.warnings, &(&1.code == :physical_aggregate_semantics))

    assert Enum.find(result.warnings, &(&1.code == :watermark_unknown))

    assert [%DataLink{target: :telemetry_point, target_id: "HK.counter", source: :field}] =
             min_field.metadata.links

    assert_receive {:decimated_history, "org-1", "mission-1", "HK.counter", opts}
    assert opts[:realm] == :rehearsal
    assert opts[:data_source_id] == "customer-questdb-rehearsal"
    assert opts[:dataset] == "rehearsal-12"
    assert opts[:from_receipt_time] == from_time
    assert opts[:to_receipt_time] == to_time
    assert opts[:target_points] == 320
    assert opts[:bucket_width_ms] == 60_000
    assert opts[:decimation] == :native_min_max_envelope
  end

  test "rejects decimated sampling when the source binding lacks native decimation" do
    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("history should not be read for unsupported sampling")
    end

    decimated_history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      flunk("decimated history should not be read for unsupported sampling")
    end

    result =
      Telemetry.resolve(
        source_request(sampling: %{mode: :decimated_envelope}),
        history_fun: history_fun,
        decimated_history_fun: decimated_history_fun,
        source_binding: source_binding(%{native_decimation?: false})
      )

    assert %SourceResult{frames: [], warnings: warnings} = result
    assert result.meta.degraded?
    assert Enum.map(warnings, & &1.code) == [:watermark_unknown, :unsupported_sampling]

    assert %ResolveWarning{
             severity: :warning,
             details: %{requested_mode: :decimated_envelope}
           } = Enum.find(warnings, &(&1.code == :unsupported_sampling))
  end

  test "degrades native decimated history query failures with source health actions" do
    decimated_history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:error, {:http_error, 400, %{"error" => "SAMPLE BY failed"}}}
    end

    result =
      Telemetry.resolve(
        source_request(sampling: %{mode: :decimated_envelope}),
        decimated_history_fun: decimated_history_fun,
        source_binding: source_binding(%{native_decimation?: true})
      )

    assert %SourceResult{frames: [], warnings: warnings} = result
    assert result.meta.degraded?

    assert %ResolveWarning{
             code: :source_unavailable,
             severity: :error,
             details: details
           } = Enum.find(warnings, &(&1.code == :source_unavailable))

    assert details.source_query_kind == :native_decimated_history
    assert details.unresolved_capability == :native_decimation
    assert details.reason =~ "SAMPLE BY failed"
    assert details.requested_sampling == :decimated_envelope

    assert Enum.any?(details.actions, fn
             %DashboardAction{
               target: :source_health,
               query: %{
                 "data_source_id" => "customer-questdb-rehearsal",
                 "source_empty_reason" => "source_query_failed"
               }
             } ->
               true

             _other ->
               false
           end)
  end

  test "requires tenant and mission context" do
    result =
      Telemetry.resolve(%PlannedSourceRequest{
        request_id: "source-request-1",
        organization_id: nil,
        mission_id: nil,
        logical_source: :telemetry,
        observables: ["HK.counter"],
        scope_context: %{mission_id: "mission-1"},
        sampling: %{mode: :raw_series}
      })

    assert %SourceResult{frames: [], warnings: warnings} = result
    assert Enum.map(warnings, & &1.code) == [:watermark_unknown, :missing_tenant_context]
  end
end
