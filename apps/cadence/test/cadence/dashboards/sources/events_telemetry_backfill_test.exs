defmodule Cadence.Dashboards.Sources.EventsTelemetryBackfillTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    DataBinding,
    DataLink,
    DataSource,
    EvidenceRef,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceResult
  }

  alias Cadence.Dashboards.Sources.Events
  alias Cadence.Jobs.Job
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent

  test "resolves telemetry backfill lifecycle events by affected source window" do
    from_time = ~U[2026-06-22 11:30:00Z]
    to_time = ~U[2026-06-22 11:45:00Z]
    parent = self()

    telemetry_backfill_lifecycle_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_backfill_lifecycle_events, organization_id, mission_id, opts})

      [
        BackfillLifecycleEvent.new(%{
          backfill_lifecycle_event_id: "backfill-event-1",
          backfill_run_id: "backfill-run-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :flight,
          data_source_id: "flight-questdb",
          binding_id: "flight-telemetry",
          observable_id: "HK.counter",
          point_id: "HK.counter",
          spacecraft_id: "sc-1",
          event_type: :late_data_accepted,
          source_from: ~U[2026-06-22 11:00:00Z],
          source_to: ~U[2026-06-22 12:00:00Z],
          receipt_from: ~U[2026-06-22 12:10:00Z],
          receipt_to: ~U[2026-06-22 12:20:00Z],
          sample_count: 42,
          authority: :authoritative,
          reason: :late_arrival_policy,
          actor_id: "ops-1",
          actor_kind: "operator",
          occurred_at: ~U[2026-06-22 12:21:00Z],
          payload: %{
            selected_sample_count: 2,
            projection_effect: :canonical_history_and_current_projection,
            write_validity_state: :canonical,
            record_current_values: true,
            refresh_latest_value: true
          }
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_backfills],
            telemetry_backfill: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              observable_id: "HK.counter",
              authority: :authoritative
            },
            limit: 10
          }
        ),
        telemetry_backfill_lifecycle_events_fun: telemetry_backfill_lifecycle_events_fun,
        telemetry_backfill_workflow_job_fun: fn _event ->
          Job.new(%{
            mission_id: "mission-1",
            job_type: :telemetry_historical_data_workflow,
            run_id: "backfill-run-1",
            status: :failed,
            failure_reason: "dispatcher unavailable"
          })
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:telemetry_backfill_lifecycle"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert Enum.map(fields["occurred_at"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:21:00.000000Z"
           ]

    assert fields["category"].values == [:telemetry_backfill]
    assert fields["kind"].values == [:late_data_accepted]
    assert fields["severity"].values == [:info]
    assert fields["title"].values == ["HK.counter late data accepted"]
    assert fields["source_record_id"].values == ["backfill-event-1"]
    assert fields["backfill_run_id"].values == ["backfill-run-1"]
    assert fields["workflow_run_id"].values == ["backfill-run-1"]
    assert Enum.all?(fields["workflow_job_id"].values, &is_binary/1)
    assert fields["workflow_job_status"].values == [:failed]
    assert fields["workflow_job_failure"].values == ["dispatcher unavailable"]
    assert fields["realm"].values == [:flight]
    assert fields["data_source_id"].values == ["flight-questdb"]
    assert fields["source_binding_id"].values == ["flight-telemetry"]
    assert fields["observable_id"].values == ["HK.counter"]
    assert fields["point_id"].values == ["HK.counter"]
    assert fields["spacecraft_id"].values == ["sc-1"]

    assert Enum.map(fields["source_from"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T11:00:00.000000Z"
           ]

    assert Enum.map(fields["source_to"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:00:00.000000Z"
           ]

    assert Enum.map(fields["receipt_from"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:10:00.000000Z"
           ]

    assert Enum.map(fields["receipt_to"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:20:00.000000Z"
           ]

    assert fields["sample_count"].values == [42]
    assert fields["selected_sample_count"].values == [2]
    assert fields["projection_effect"].values == [:canonical_history_and_current_projection]
    assert fields["write_validity_state"].values == [:canonical]
    assert fields["record_current_values"].values == [true]
    assert fields["refresh_latest_value"].values == [true]
    assert fields["authority"].values == [:authoritative]
    assert fields["reason"].values == [:late_arrival_policy]
    assert fields["actor_id"].values == ["ops-1"]
    assert fields["actor_kind"].values == ["operator"]

    assert frame.meta.family == :telemetry_backfill
    assert frame.meta.product == :telemetry_backfill_lifecycle
    assert frame.meta.projection == :telemetry_backfill_lifecycle_events
    assert frame.meta.returned_events == 1
    assert frame.meta.cursor.backfill_lifecycle_event_id == "backfill-event-1"
    assert frame.meta.cursor.backfill_run_id == "backfill-run-1"

    assert_evidence_ref(
      frame.meta.evidence,
      :telemetry_backfill_lifecycle_event,
      "backfill-event-1"
    )

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:telemetry_backfill_lifecycle_event:backfill-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :telemetry_backfill_lifecycle_event,
      "backfill-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:telemetry_backfill_lifecycle_event:backfill-event-1"
    )

    assert hd(frame.meta.links).context.data.data_source_id == "managed_events_projection"
    assert hd(frame.meta.links).context.data.source_binding_id == "default_flight_events"
    assert result.meta.supported_capability == [:telemetry_backfill_lifecycle]

    assert_receive {:telemetry_backfill_lifecycle_events, "org-1", "mission-1", opts}
    assert opts[:source_from] == from_time
    assert opts[:source_to] == to_time
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "flight-questdb"
    assert opts[:binding_id] == "flight-telemetry"
    assert opts[:observable_id] == "HK.counter"
    assert opts[:authority] == :authoritative
    assert opts[:limit] == 10
    refute Keyword.has_key?(opts, :from_occurred_at)
    refute Keyword.has_key?(opts, :source_binding_id)
  end

  test "resolves telemetry backfill lifecycle events with replay run context" do
    parent = self()

    telemetry_backfill_lifecycle_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_backfill_lifecycle_events, organization_id, mission_id, opts})

      [
        BackfillLifecycleEvent.new(%{
          backfill_lifecycle_event_id: "replay-backfill-event-1",
          backfill_run_id: "replay-backfill-run-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :replay,
          replay_run_id: "replay-run-1",
          data_source_id: "replay-questdb",
          binding_id: "replay-telemetry",
          observable_id: "HK.counter",
          event_type: :backfill_completed,
          source_from: ~U[2026-06-22 11:00:00Z],
          source_to: ~U[2026-06-22 12:00:00Z],
          authority: :authoritative,
          occurred_at: ~U[2026-06-22 12:21:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_backfills],
            telemetry_backfill: %{
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              observable_id: "HK.counter"
            }
          }
        ),
        telemetry_backfill_lifecycle_events_fun: telemetry_backfill_lifecycle_events_fun,
        telemetry_backfill_workflow_job_fun: fn _event -> nil end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:telemetry_backfill_lifecycle_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:binding_id] == "replay-telemetry"
  end

  defp assert_evidence_ref(evidence_refs, kind, id) do
    assert Enum.any?(evidence_refs, &match?(%EvidenceRef{kind: ^kind, id: ^id}, &1))
  end

  defp assert_data_link(links, target, target_id) do
    assert Enum.any?(links, &match?(%DataLink{target: ^target, target_id: ^target_id}, &1))
  end

  defp source_request(overrides) do
    attrs =
      %{
        request_id: "events-request-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :events,
        observables: ["HK.battery_voltage"],
        scope_context: %{
          organization_id: "org-1",
          mission_id: "mission-1",
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time_context: %{axis: :occurred_at},
        data_context: %{realm: :flight},
        sampling: %{mode: :event_history},
        overlays: []
      }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "default_flight_events",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        logical_source: :events,
        data_source_id: "managed_events_projection",
        dataset: "mission_events"
      },
      data_source: %DataSource{
        data_source_id: "managed_events_projection",
        owner: :cadence,
        kind: :projection,
        isolation_level: :shared,
        adapter: Events,
        capabilities: %{
          contact_intervals?: true,
          mission_timeline?: true,
          source_health_transitions?: true,
          source_watermark_events?: true,
          source_capability_postures?: true,
          telemetry_backfill_lifecycle?: true,
          telemetry_revision_decisions?: true
        }
      },
      realm: :flight,
      dataset: "mission_events"
    }
  end
end
