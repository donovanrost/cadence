defmodule Cadence.Dashboards.Sources.OperationalObservablesReplayIntegrationTest do
  use Cadence.RuntimeCase, async: false

  @moduletag :integration

  import Cadence.Dashboards.Sources.OperationalObservablesReplayFixtures

  alias Cadence.Dashboards.{Frame, SourceResult}

  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

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
    persist_default_metric_samples!(organization_id, mission_id)

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

    assert operational_event_link_ids(replay_eb_n0_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-ebn0-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-ebn0-replay-2"
           ]

    assert operational_event_evidence_ids(replay_eb_n0_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-ebn0-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-ebn0-replay-2"
           ]

    live_doppler_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_doppler_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_doppler_frame], warnings: []} =
             live_doppler_result

    assert live_doppler_frame.meta.realm == :flight
    assert live_doppler_frame.meta.replay_run_id == nil
    assert field_values(live_doppler_frame, "link.doppler_hz") == [-42.5]

    replay_doppler_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_doppler_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_doppler_frame], warnings: []} =
             replay_doppler_result

    assert replay_doppler_frame.meta.realm == :replay
    assert replay_doppler_frame.meta.data_source_id == "managed_operational_observables_replay"
    assert replay_doppler_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_doppler_frame.meta.dataset == "operational_observables_replay"
    assert replay_doppler_frame.meta.replay_run_id == "replay-run-1"
    assert field_values(replay_doppler_frame, "link.doppler_hz") == [-40.25, -38.0]

    assert operational_event_link_ids(replay_doppler_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-doppler-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-doppler-replay-2"
           ]

    assert operational_event_evidence_ids(replay_doppler_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-doppler-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-doppler-replay-2"
           ]

    live_symbol_rate_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_symbol_rate_history_request()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = live_symbol_rate_frame], warnings: []} =
             live_symbol_rate_result

    assert live_symbol_rate_frame.meta.realm == :flight
    assert live_symbol_rate_frame.meta.replay_run_id == nil
    assert field_values(live_symbol_rate_frame, "link.symbol_rate_sps") == [1_024_000.0]

    replay_symbol_rate_result =
      organization_id
      |> source_request(mission_id)
      |> link_rf_symbol_rate_history_request()
      |> replay_request_context()
      |> OperationalObservables.resolve(
        transports_fun: transports_fun(organization_id, mission_id),
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [%Frame{} = replay_symbol_rate_frame], warnings: []} =
             replay_symbol_rate_result

    assert replay_symbol_rate_frame.meta.realm == :replay

    assert replay_symbol_rate_frame.meta.data_source_id ==
             "managed_operational_observables_replay"

    assert replay_symbol_rate_frame.meta.source_binding_id == "replay-operational-observables"
    assert replay_symbol_rate_frame.meta.dataset == "operational_observables_replay"
    assert replay_symbol_rate_frame.meta.replay_run_id == "replay-run-1"

    assert field_values(replay_symbol_rate_frame, "link.symbol_rate_sps") == [
             1_048_000.0,
             2_048_000.0
           ]

    assert operational_event_link_ids(replay_symbol_rate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-symbol-rate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-symbol-rate-replay-2"
           ]

    assert operational_event_evidence_ids(replay_symbol_rate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:rf-symbol-rate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:rf-symbol-rate-replay-2"
           ]

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

    assert operational_event_link_ids(replay_uplink_bitrate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:uplink-bitrate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:uplink-bitrate-replay-2"
           ]

    assert operational_event_evidence_ids(replay_uplink_bitrate_frame) == [
             "operational_event:operational_observable_snapshot:replay-run-1:uplink-bitrate-replay-1",
             "operational_event:operational_observable_snapshot:replay-run-1:uplink-bitrate-replay-2"
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
end
