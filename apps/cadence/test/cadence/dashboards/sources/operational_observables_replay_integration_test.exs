defmodule Cadence.Dashboards.Sources.OperationalObservablesReplayIntegrationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceResult
  }

  alias Cadence.Comms.Transport
  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.TransportCapabilityRecord

  setup do
    organization_id =
      "org-ops-observables-replay-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "ops-observables-replay-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "default transport execution source reader keeps live and replay timelines isolated", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             mission_id
             |> transport_capability_record(
               "transport-live-record",
               "uplink-heartbeat",
               :initialized,
               ~U[2026-06-30 12:00:00Z],
               state_snapshot: %{active?: true, source: :live}
             )
             |> Event.from_transport_capability_record()
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             mission_id
             |> transport_capability_record(
               "transport-replay-record-1",
               "uplink-heartbeat",
               :initialized,
               ~U[2026-06-30 12:01:00Z],
               state_snapshot: %{active?: true, source: :replay}
             )
             |> replay_scoped_event("replay-run-1")
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             mission_id
             |> transport_capability_record(
               "transport-other-replay-record",
               "uplink-heartbeat",
               :control_input_handled,
               ~U[2026-06-30 12:02:00Z],
               state_snapshot: %{active?: false, source: :other_replay}
             )
             |> replay_scoped_event("replay-run-2")
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             mission_id
             |> transport_capability_record(
               "transport-replay-record-2",
               "uplink-heartbeat",
               :timer_handled,
               ~U[2026-06-30 12:03:00Z],
               timer_key: "health-check",
               state_snapshot: %{active?: true, source: :replay}
             )
             |> replay_scoped_event("replay-run-1")
             |> OperationalEvents.persist_event()

    live_result =
      organization_id
      |> source_request(mission_id)
      |> transport_execution_request()
      |> OperationalObservables.resolve(source_binding: source_binding())

    assert %SourceResult{frames: [%Frame{} = live_frame], warnings: []} = live_result
    assert live_frame.meta.realm == :flight
    assert live_frame.meta.replay_run_id == nil
    assert field_values(live_frame, "transport_record_id") == ["transport-live-record"]
    assert field_values(live_frame, "state") == [:initialized]

    replay_result =
      organization_id
      |> source_request(mission_id)
      |> transport_execution_request()
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: ~U[2026-06-30 11:59:00Z],
        to: ~U[2026-06-30 12:05:00Z],
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(source_binding: replay_source_binding())

    assert %SourceResult{frames: [%Frame{} = replay_frame], warnings: []} = replay_result
    assert replay_frame.meta.realm == :replay
    assert replay_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_frame.meta.dataset == "operational_observables_replay"
    assert replay_frame.meta.replay_run_id == "replay-run-1"

    assert field_values(replay_frame, "transport_record_id") == [
             "transport-replay-record-1",
             "transport-replay-record-2"
           ]

    assert field_values(replay_frame, "state") == [:initialized, :timer_handled]

    refute "transport-live-record" in field_values(replay_frame, "transport_record_id")
    refute "transport-other-replay-record" in field_values(replay_frame, "transport_record_id")
  end

  test "default connection state source reader keeps live and replay timelines isolated", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-live-1",
               :connected,
               ~U[2026-06-30 12:00:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-replay-1",
               :connecting,
               ~U[2026-06-30 12:01:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-other-replay",
               :disconnected,
               ~U[2026-06-30 12:02:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "connection-replay-2",
               :connected,
               ~U[2026-06-30 12:03:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    live_result =
      organization_id
      |> source_request(mission_id)
      |> connection_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_frame], warnings: []} = live_result
    assert live_frame.meta.realm == :flight
    assert live_frame.meta.replay_run_id == nil
    assert field_values(live_frame, "connection_state") == [:connected]
    assert field_values(live_frame, "resource_id") == ["transport-alpha"]

    replay_result =
      organization_id
      |> source_request(mission_id)
      |> connection_history_request()
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: ~U[2026-06-30 11:59:00Z],
        to: ~U[2026-06-30 12:05:00Z],
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, replay_data_context())
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_frame], warnings: []} = replay_result
    assert replay_frame.meta.realm == :replay
    assert replay_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_frame.meta.dataset == "operational_observables_replay"
    assert replay_frame.meta.replay_run_id == "replay-run-1"

    assert field_values(replay_frame, "connection_state") == [:connecting, :connected]
    assert field_values(replay_frame, "resource_id") == ["transport-alpha", "transport-alpha"]

    assert Enum.all?(
             field_values(replay_frame, "interval_id"),
             &String.starts_with?(&1, "effective_interval:transport_connection_state:")
           )

    assert Enum.all?(field_values(replay_frame, "source_event_id"), &is_binary/1)

    assert :transport_connection_state_interval in evidence_ref_kinds(replay_frame)
    assert :operational_interval in evidence_ref_kinds(replay_frame)
  end

  test "default RF state source readers keep live and replay timelines isolated", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-live-1",
               :locked,
               ~U[2026-06-30 12:00:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-replay-1",
               :acquiring,
               ~U[2026-06-30 12:01:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-other-replay",
               :unlocked,
               ~U[2026-06-30 12:02:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-replay-2",
               :locked,
               ~U[2026-06-30 12:03:00Z],
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "frame-sync-live-1",
               :synchronized,
               ~U[2026-06-30 12:00:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "frame-sync-replay-1",
               :acquiring,
               ~U[2026-06-30 12:01:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "frame-sync-other-replay",
               :lost,
               ~U[2026-06-30 12:02:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "frame-sync-replay-2",
               :synchronized,
               ~U[2026-06-30 12:03:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    live_rf_lock_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_lock_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_rf_lock_frame], warnings: []} =
             live_rf_lock_result

    assert live_rf_lock_frame.meta.realm == :flight
    assert live_rf_lock_frame.meta.replay_run_id == nil
    assert field_values(live_rf_lock_frame, "state") == [:locked]
    assert field_values(live_rf_lock_frame, "resource_id") == ["link-alpha"]

    replay_rf_lock_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_lock_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_rf_lock_frame], warnings: []} =
             replay_rf_lock_result

    assert replay_rf_lock_frame.meta.realm == :replay
    assert replay_rf_lock_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_rf_lock_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_rf_lock_frame.meta.dataset == "operational_observables_replay"
    assert replay_rf_lock_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_rf_lock_frame, "state") == [:acquiring, :locked]
    assert field_values(replay_rf_lock_frame, "resource_id") == ["link-alpha", "link-alpha"]

    assert Enum.all?(
             field_values(replay_rf_lock_frame, "interval_id"),
             &String.starts_with?(&1, "effective_interval:link_rf_lock_state:")
           )

    assert Enum.all?(field_values(replay_rf_lock_frame, "source_event_id"), &is_binary/1)

    assert :link_rf_lock_state_interval in evidence_ref_kinds(replay_rf_lock_frame)
    assert :operational_interval in evidence_ref_kinds(replay_rf_lock_frame)

    live_frame_sync_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_frame_sync_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_frame_sync_frame], warnings: []} =
             live_frame_sync_result

    assert live_frame_sync_frame.meta.realm == :flight
    assert live_frame_sync_frame.meta.replay_run_id == nil
    assert field_values(live_frame_sync_frame, "state") == [:synchronized]
    assert field_values(live_frame_sync_frame, "resource_id") == ["link-alpha"]

    replay_frame_sync_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_frame_sync_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_frame_sync_frame], warnings: []} =
             replay_frame_sync_result

    assert replay_frame_sync_frame.meta.realm == :replay
    assert replay_frame_sync_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_frame_sync_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_frame_sync_frame.meta.dataset == "operational_observables_replay"
    assert replay_frame_sync_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_frame_sync_frame, "state") == [:acquiring, :synchronized]
    assert field_values(replay_frame_sync_frame, "resource_id") == ["link-alpha", "link-alpha"]

    assert Enum.all?(
             field_values(replay_frame_sync_frame, "interval_id"),
             &String.starts_with?(&1, "effective_interval:link_frame_sync_state:")
           )

    assert Enum.all?(field_values(replay_frame_sync_frame, "source_event_id"), &is_binary/1)

    assert :link_frame_sync_state_interval in evidence_ref_kinds(replay_frame_sync_frame)
    assert :operational_interval in evidence_ref_kinds(replay_frame_sync_frame)
  end

  test "default antenna pointing state source reader keeps live and replay timelines isolated", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    for {snapshot_id, state, observed_at, opts} <- [
          {"antenna-pointing-live", :tracking, ~U[2026-06-30 12:00:00Z], []},
          {"antenna-pointing-replay-slewing", :slewing, ~U[2026-06-30 12:01:00Z],
           [replay_run_id: "replay-run-1"]},
          {"antenna-pointing-other-replay", :stowed, ~U[2026-06-30 12:02:00Z],
           [replay_run_id: "replay-run-2"]},
          {"antenna-pointing-replay-tracking", :tracking, ~U[2026-06-30 12:03:00Z],
           [replay_run_id: "replay-run-1"]}
        ] do
      assert {:ok, _event} =
               operational_observable_state_event(
                 organization_id,
                 mission_id,
                 snapshot_id,
                 state,
                 observed_at,
                 Keyword.merge(
                   [
                     observable_id: "ground.station.antenna_pointing_state",
                     resource_id: "dss-14",
                     scope_kind: :ground_station
                   ],
                   opts
                 )
               )
               |> OperationalEvents.persist_event()
    end

    live_result =
      organization_id
      |> source_request(mission_id)
      |> antenna_pointing_history_request()
      |> OperationalObservables.resolve(
        source_endpoints_fun: source_endpoints_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_frame], warnings: []} = live_result
    assert live_frame.meta.realm == :flight
    assert live_frame.meta.replay_run_id == nil
    assert field_values(live_frame, "state") == [:tracking]
    assert field_values(live_frame, "resource_id") == ["dss-14"]

    replay_result =
      organization_id
      |> source_request(mission_id)
      |> antenna_pointing_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        source_endpoints_fun: source_endpoints_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_frame], warnings: []} = replay_result
    assert replay_frame.meta.realm == :replay
    assert replay_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_frame.meta.dataset == "operational_observables_replay"
    assert replay_frame.meta.replay_run_id == "replay-run-1"
    assert replay_frame.meta.state_color_policy == :antenna_pointing_state
    assert field_values(replay_frame, "state") == [:slewing, :tracking]
    assert field_values(replay_frame, "resource_id") == ["dss-14", "dss-14"]

    assert field_values(replay_frame, "source_endpoint_id") == [
             "endpoint-alpha",
             "endpoint-alpha"
           ]

    assert Enum.all?(
             field_values(replay_frame, "interval_id"),
             &String.starts_with?(&1, "effective_interval:operational_observable_state:")
           )

    assert operational_event_link_ids(replay_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:antenna-pointing-replay-slewing",
             "operational_event:operational_observable_snapshot:replay-run-1:antenna-pointing-replay-tracking"
           ]

    assert :ground_station_antenna_pointing_state_interval in evidence_ref_kinds(replay_frame)
    assert :operational_interval in evidence_ref_kinds(replay_frame)
  end

  test "default metric source readers keep live and replay timelines isolated", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    for metric_attrs <-
          [
            metric_sample("rf-snr-live-1", "link.snr_db", 11.5, ~U[2026-06-30 12:00:00Z]),
            metric_sample("rf-snr-replay-1", "link.snr_db", 12.25, ~U[2026-06-30 12:01:00Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-snr-other-replay",
              "link.snr_db",
              7.5,
              ~U[2026-06-30 12:02:00Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample("rf-snr-replay-2", "link.snr_db", 14.0, ~U[2026-06-30 12:03:00Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample("rf-ebn0-live-1", "link.eb_n0_db", 8.75, ~U[2026-06-30 12:00:30Z]),
            metric_sample("rf-ebn0-replay-1", "link.eb_n0_db", 9.25, ~U[2026-06-30 12:01:30Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "rf-ebn0-other-replay",
              "link.eb_n0_db",
              5.5,
              ~U[2026-06-30 12:02:30Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample("rf-ebn0-replay-2", "link.eb_n0_db", 10.0, ~U[2026-06-30 12:03:30Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "bitrate-live-1",
              "comms.transport.downlink_bitrate",
              64_000.0,
              ~U[2026-06-30 12:00:15Z]
            ),
            metric_sample(
              "uplink-bitrate-live-1",
              "comms.transport.uplink_bitrate",
              4_800.0,
              ~U[2026-06-30 12:00:20Z]
            ),
            metric_sample(
              "bitrate-replay-1",
              "comms.transport.downlink_bitrate",
              72_000.0,
              ~U[2026-06-30 12:01:15Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "uplink-bitrate-replay-1",
              "comms.transport.uplink_bitrate",
              5_600.0,
              ~U[2026-06-30 12:01:20Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "bitrate-other-replay",
              "comms.transport.downlink_bitrate",
              48_000.0,
              ~U[2026-06-30 12:02:15Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "uplink-bitrate-other-replay",
              "comms.transport.uplink_bitrate",
              3_200.0,
              ~U[2026-06-30 12:02:20Z],
              replay_run_id: "replay-run-2"
            ),
            metric_sample(
              "bitrate-replay-2",
              "comms.transport.downlink_bitrate",
              96_000.0,
              ~U[2026-06-30 12:03:15Z],
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "uplink-bitrate-replay-2",
              "comms.transport.uplink_bitrate",
              8_400.0,
              ~U[2026-06-30 12:03:20Z],
              replay_run_id: "replay-run-1"
            )
          ] do
      assert {:ok, _event} =
               operational_observable_metric_event(organization_id, mission_id, metric_attrs)
               |> OperationalEvents.persist_event()
    end

    live_rf_metric_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_metric_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_rf_metric_frame], warnings: []} =
             live_rf_metric_result

    assert live_rf_metric_frame.meta.realm == :flight
    assert live_rf_metric_frame.meta.replay_run_id == nil
    assert field_values(live_rf_metric_frame, "link.snr_db") == [11.5]

    replay_rf_metric_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_metric_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_rf_metric_frame], warnings: []} =
             replay_rf_metric_result

    assert replay_rf_metric_frame.meta.realm == :replay
    assert replay_rf_metric_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_rf_metric_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_rf_metric_frame.meta.dataset == "operational_observables_replay"
    assert replay_rf_metric_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_rf_metric_frame, "link.snr_db") == [12.25, 14.0]

    assert operational_event_link_ids(replay_rf_metric_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-snr-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-snr-replay-2"
           ]

    assert operational_event_evidence_ids(replay_rf_metric_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-snr-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-snr-replay-2"
           ]

    live_eb_n0_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_eb_n0_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_eb_n0_frame], warnings: []} =
             live_eb_n0_result

    assert live_eb_n0_frame.meta.realm == :flight
    assert live_eb_n0_frame.meta.replay_run_id == nil
    assert field_values(live_eb_n0_frame, "link.eb_n0_db") == [8.75]

    replay_eb_n0_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_eb_n0_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_eb_n0_frame], warnings: []} =
             replay_eb_n0_result

    assert replay_eb_n0_frame.meta.realm == :replay
    assert replay_eb_n0_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_eb_n0_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_eb_n0_frame.meta.dataset == "operational_observables_replay"
    assert replay_eb_n0_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_eb_n0_frame, "link.eb_n0_db") == [9.25, 10.0]

    live_bitrate_result =
      organization_id
      |> source_request(mission_id)
      |> transport_bitrate_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: live_bitrate_frames, warnings: []} =
             live_bitrate_result

    live_downlink_bitrate_frame =
      frame_by_observable!(live_bitrate_frames, "comms.transport.downlink_bitrate")

    live_uplink_bitrate_frame =
      frame_by_observable!(live_bitrate_frames, "comms.transport.uplink_bitrate")

    assert live_downlink_bitrate_frame.meta.realm == :flight
    assert live_downlink_bitrate_frame.meta.replay_run_id == nil

    assert field_values(live_downlink_bitrate_frame, "comms.transport.downlink_bitrate") == [
             64_000.0
           ]

    assert live_uplink_bitrate_frame.meta.realm == :flight
    assert live_uplink_bitrate_frame.meta.replay_run_id == nil

    assert field_values(live_uplink_bitrate_frame, "comms.transport.uplink_bitrate") == [
             4_800.0
           ]

    replay_bitrate_result =
      organization_id
      |> source_request(mission_id)
      |> transport_bitrate_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: replay_bitrate_frames, warnings: []} =
             replay_bitrate_result

    replay_downlink_bitrate_frame =
      frame_by_observable!(replay_bitrate_frames, "comms.transport.downlink_bitrate")

    replay_uplink_bitrate_frame =
      frame_by_observable!(replay_bitrate_frames, "comms.transport.uplink_bitrate")

    for frame <- [replay_downlink_bitrate_frame, replay_uplink_bitrate_frame] do
      assert frame.meta.realm == :replay
      assert frame.meta.data_source_id == "managed_operational_observables_replay"
      assert frame.meta.source_binding_id == "replay-operational-observables"
      assert frame.meta.dataset == "operational_observables_replay"
      assert frame.meta.replay_run_id == "replay-run-1"
    end

    assert field_values(replay_downlink_bitrate_frame, "comms.transport.downlink_bitrate") == [
             72_000.0,
             96_000.0
           ]

    assert operational_event_link_ids(replay_downlink_bitrate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:bitrate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:bitrate-replay-2"
           ]

    assert operational_event_evidence_ids(replay_downlink_bitrate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:bitrate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:bitrate-replay-2"
           ]

    assert field_values(replay_uplink_bitrate_frame, "comms.transport.uplink_bitrate") == [
             5_600.0,
             8_400.0
           ]
  end

  test "default ingress latency reader uses durable metric samples and keeps replay scope isolated",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    for metric_attrs <-
          [
            metric_sample(
              "ingress-latency-live-alpha",
              "ingress.processing_latency_ms",
              4.5,
              ~U[2026-06-30 12:00:00Z],
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha"
            ),
            metric_sample(
              "ingress-latency-live-beta",
              "ingress.processing_latency_ms",
              9.0,
              ~U[2026-06-30 12:00:15Z],
              source_endpoint_id: "endpoint-beta",
              spacecraft_id: "spacecraft-beta"
            ),
            metric_sample(
              "ingress-latency-replay-alpha",
              "ingress.processing_latency_ms",
              8.75,
              ~U[2026-06-30 12:01:00Z],
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "ingress-latency-replay-beta",
              "ingress.processing_latency_ms",
              15.0,
              ~U[2026-06-30 12:01:15Z],
              source_endpoint_id: "endpoint-beta",
              spacecraft_id: "spacecraft-beta",
              replay_run_id: "replay-run-1"
            ),
            metric_sample(
              "ingress-latency-other-replay-alpha",
              "ingress.processing_latency_ms",
              2.0,
              ~U[2026-06-30 12:02:00Z],
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              replay_run_id: "replay-run-2"
            )
          ] do
      assert {:ok, _event} =
               operational_observable_metric_event(organization_id, mission_id, metric_attrs)
               |> OperationalEvents.persist_event()
    end

    live_result =
      organization_id
      |> source_request(mission_id)
      |> ingress_latency_request("endpoint-alpha")
      |> OperationalObservables.resolve(source_binding: source_binding())

    assert %SourceResult{frames: [%Frame{} = live_frame], warnings: []} = live_result
    assert live_frame.meta.realm == :flight
    assert live_frame.meta.replay_run_id == nil
    assert field_values(live_frame, "resource_id") == ["endpoint-alpha"]
    assert field_values(live_frame, "source_endpoint_id") == ["endpoint-alpha"]
    assert field_values(live_frame, "spacecraft_id") == ["spacecraft-alpha"]
    assert field_values(live_frame, "value") == [4.5]

    replay_result =
      organization_id
      |> source_request(mission_id)
      |> ingress_latency_request("endpoint-alpha")
      |> replay_request_context()
      |> OperationalObservables.resolve(source_binding: replay_source_binding())

    assert %SourceResult{frames: [%Frame{} = replay_frame], warnings: []} = replay_result
    assert replay_frame.meta.realm == :replay
    assert replay_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_frame.meta.dataset == "operational_observables_replay"
    assert replay_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_frame, "resource_id") == ["endpoint-alpha"]
    assert field_values(replay_frame, "source_endpoint_id") == ["endpoint-alpha"]
    assert field_values(replay_frame, "spacecraft_id") == ["spacecraft-alpha"]
    assert field_values(replay_frame, "value") == [8.75]

    assert operational_event_link_ids(replay_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:ingress-latency-replay-alpha"
           ]

    assert operational_event_evidence_ids(replay_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:ingress-latency-replay-alpha"
           ]
  end

  defp source_request(organization_id, mission_id) do
    %PlannedSourceRequest{
      request_id: "ops-request-1",
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :operational_observables,
      observables: [],
      data_context: %{realm: :flight},
      sampling: %{mode: :constellation_health}
    }
  end

  defp transport_execution_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["comms.transport.execution_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["uplink-heartbeat"]}
    })
  end

  defp ingress_latency_request(%PlannedSourceRequest{} = request, source_endpoint_id) do
    request
    |> Map.put(:observables, ["ingress.processing_latency_ms"])
    |> Map.put(:sampling, %{mode: :latest})
    |> Map.put(:scope_context, %{
      primary: %{kind: :source_endpoint, mode: :one, ids: [source_endpoint_id]}
    })
  end

  defp connection_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["comms.transport.connection_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
    })
  end

  defp link_rf_lock_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.rf_lock_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  defp link_rf_frame_sync_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.frame_sync_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  defp antenna_pointing_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
    |> Map.put(:sampling, %{mode: :event_history, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
    })
  end

  defp link_rf_metric_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.snr_db"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  defp link_rf_eb_n0_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, ["link.eb_n0_db"])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}
    })
  end

  defp transport_bitrate_history_request(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:observables, [
      "comms.transport.downlink_bitrate",
      "comms.transport.uplink_bitrate"
    ])
    |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
    |> Map.put(:time_context, %{
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z]
    })
    |> Map.put(:scope_context, %{
      primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
    })
  end

  defp replay_request_context(%PlannedSourceRequest{} = request) do
    request
    |> Map.put(:time_context, %{
      mode: :replay_run,
      from: ~U[2026-06-30 11:59:00Z],
      to: ~U[2026-06-30 12:05:00Z],
      replay_run_id: "replay-run-1"
    })
    |> Map.put(:data_context, replay_data_context())
  end

  defp replay_data_context do
    %{
      realm: :replay,
      replay_run_id: "replay-run-1",
      source_contexts: %{
        operational_observables: %{
          data_source_id: "managed_operational_observables_replay",
          source_binding_id: "replay-operational-observables",
          dataset: "operational_observables_replay"
        }
      }
    }
  end

  defp source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "flight-operational-observables",
        realm: :flight,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables",
        adapter: OperationalObservables
      },
      realm: :flight,
      dataset: "operational_observables"
    }
  end

  defp replay_source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-operational-observables",
        realm: :replay,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables_replay",
        dataset: "operational_observables_replay"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables_replay",
        adapter: OperationalObservables
      },
      realm: :replay,
      dataset: "operational_observables_replay"
    }
  end

  defp transports_fun(organization_id, mission_id) do
    fn ^organization_id, ^mission_id, _opts ->
      [
        Transport.new(%{
          transport_id: "transport-alpha",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "Lab TCP",
          adapter_key: :tcp_socket,
          metadata: %{
            source_endpoint_id: "endpoint-alpha",
            ground_station_id: "dss-14",
            link_assignment_id: "link-alpha"
          }
        })
      ]
    end
  end

  defp source_endpoints_fun(organization_id, mission_id) do
    fn ^organization_id, ^mission_id, _opts ->
      [
        %{
          source_endpoint_id: "endpoint-alpha",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "DSS-14 endpoint",
          metadata: %{
            "ground_station_id" => "dss-14",
            "transport_id" => "transport-alpha",
            "link_assignment_id" => "link-alpha"
          }
        }
      ]
    end
  end

  defp transport_capability_record(
         mission_id,
         transport_record_id,
         capability_instance_id,
         event_kind,
         recorded_at,
         opts
       ) do
    %TransportCapabilityRecord{
      transport_record_id: transport_record_id,
      mission_id: mission_id,
      realized_contact_id: "realized-contact-1",
      path_id: Keyword.get(opts, :path_id, "uplink-path-alpha"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 4,
      partition_affinity: :source_endpoint,
      partition_value: "source-endpoint-alpha",
      event_kind: event_kind,
      timer_key: Keyword.get(opts, :timer_key),
      emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
      emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
      action_request_count: Keyword.get(opts, :action_request_count, 0),
      state_snapshot: Keyword.fetch!(opts, :state_snapshot),
      recorded_at: recorded_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp operational_observable_state_event(
         organization_id,
         mission_id,
         snapshot_id,
         state,
         observed_at,
         opts \\ []
       ) do
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: Keyword.get(opts, :resource_id, "transport-alpha"),
      scope_kind: Keyword.get(opts, :scope_kind, :transport),
      transport_id: "transport-alpha",
      source_endpoint_id: "endpoint-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      connection_state: connection_state(observable_id, state),
      state: operational_observable_state(observable_id, state),
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  defp connection_state("comms.transport.connection_state", state), do: state
  defp connection_state(_observable_id, _state), do: nil

  defp operational_observable_state("comms.transport.connection_state", _state), do: nil
  defp operational_observable_state(_observable_id, state), do: state

  defp metric_sample(sample_id, observable_id, value, observed_at, opts \\ []) do
    source_endpoint_id = Keyword.get(opts, :source_endpoint_id, "endpoint-alpha")

    %{
      sample_id: sample_id,
      observable_id: observable_id,
      resource_id: operational_observable_metric_resource_id(observable_id, source_endpoint_id),
      scope_kind: operational_observable_metric_scope_kind(observable_id),
      value_key: operational_observable_metric_value_key(observable_id),
      value: value,
      source_endpoint_id: source_endpoint_id,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      observed_at: observed_at,
      replay_run_id: Keyword.get(opts, :replay_run_id)
    }
  end

  defp operational_observable_metric_event(organization_id, mission_id, metric_attrs) do
    attrs = %{
      sample_id: metric_attrs.sample_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: metric_attrs.observable_id,
      resource_id: metric_attrs.resource_id,
      scope_kind: metric_attrs.scope_kind,
      transport_id: "transport-alpha",
      spacecraft_id: metric_attrs.spacecraft_id,
      source_endpoint_id: metric_attrs.source_endpoint_id,
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      unit: operational_observable_metric_unit(metric_attrs.observable_id),
      replay_run_id: metric_attrs.replay_run_id,
      observed_at: metric_attrs.observed_at
    }

    attrs
    |> Map.put(metric_attrs.value_key, metric_attrs.value)
    |> Event.from_operational_observable_metric_sample()
  end

  defp operational_observable_metric_resource_id("link.snr_db", _source_endpoint_id),
    do: "link-alpha"

  defp operational_observable_metric_resource_id("link.eb_n0_db", _source_endpoint_id),
    do: "link-alpha"

  defp operational_observable_metric_resource_id(
         "ingress.processing_latency_ms",
         source_endpoint_id
       ),
       do: source_endpoint_id

  defp operational_observable_metric_resource_id(_observable_id, _source_endpoint_id),
    do: "transport-alpha"

  defp operational_observable_metric_scope_kind("link.snr_db"), do: :link
  defp operational_observable_metric_scope_kind("link.eb_n0_db"), do: :link

  defp operational_observable_metric_scope_kind("ingress.processing_latency_ms"),
    do: :source_endpoint

  defp operational_observable_metric_scope_kind(_observable_id), do: :transport

  defp operational_observable_metric_value_key("link.snr_db"), do: :snr_db
  defp operational_observable_metric_value_key("link.eb_n0_db"), do: :value
  defp operational_observable_metric_value_key("ingress.processing_latency_ms"), do: :value

  defp operational_observable_metric_value_key("comms.transport.uplink_bitrate"),
    do: :uplink_bitrate

  defp operational_observable_metric_value_key(_observable_id), do: :downlink_bitrate

  defp operational_observable_metric_unit("link.snr_db"), do: "dB"
  defp operational_observable_metric_unit("link.eb_n0_db"), do: "dB"
  defp operational_observable_metric_unit("comms.transport.downlink_bitrate"), do: "bit/s"
  defp operational_observable_metric_unit("comms.transport.uplink_bitrate"), do: "bit/s"
  defp operational_observable_metric_unit("ingress.processing_latency_ms"), do: "ms"
  defp operational_observable_metric_unit(_observable_id), do: nil

  defp replay_scoped_event(%TransportCapabilityRecord{} = record, replay_run_id) do
    Event.from_transport_capability_record(record, replay_run_id)
  end

  defp field_values(%Frame{} = frame, name) do
    frame.fields
    |> Enum.find(&match?(%Field{name: ^name}, &1))
    |> case do
      %Field{values: values} -> values
      nil -> flunk("expected frame field #{inspect(name)}")
    end
  end

  defp frame_by_observable!(frames, observable_id) when is_list(frames) do
    Enum.find(frames, &(&1.meta.observable_id == observable_id)) ||
      flunk("expected frame for observable #{inspect(observable_id)}")
  end

  defp operational_event_link_ids(%Frame{} = frame) do
    frame.meta
    |> Map.get(:links, [])
    |> Enum.filter(&(&1.target == :operational_event))
    |> Enum.map(& &1.target_id)
  end

  defp operational_event_evidence_ids(%Frame{} = frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.filter(&(&1.kind == :operational_event))
    |> Enum.map(& &1.id)
  end

  defp evidence_ref_kinds(%Frame{} = frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.map(& &1.kind)
  end
end
