defmodule Cadence.OperationalEvents.ObservableFamiliesTest do
  use Cadence.DataCase, async: true

  import Cadence.OperationalEventsFixtures

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  setup do
    organization_id =
      "org-operational-events-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "operational-events-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "projects antenna pointing state events as generic operational observable intervals",
       %{organization_id: organization_id, mission_id: mission_id} do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "antenna-pointing-1",
               :slewing,
               ~U[2026-06-30 12:00:00Z],
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "antenna-pointing-2",
               :tracking,
               ~U[2026-06-30 12:05:00Z],
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station
             )
             |> OperationalEvents.persist_event()

    [slewing, tracking] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "ground.station.antenna_pointing_state",
        resource_id: "dss-14",
        order: :asc
      )

    assert slewing.kind == :operational_observable_state
    assert slewing.subject_kind == :ground_station
    assert slewing.subject_id == "dss-14"
    assert DateTime.compare(slewing.starts_at, ~U[2026-06-30 12:00:00Z]) == :eq
    assert DateTime.compare(slewing.ends_at, ~U[2026-06-30 12:05:00Z]) == :eq
    assert slewing.payload["observable_id"] == "ground.station.antenna_pointing_state"
    assert slewing.payload["state"] == "slewing"

    assert DateTime.compare(tracking.starts_at, ~U[2026-06-30 12:05:00Z]) == :eq
    assert tracking.ends_at == nil
    assert tracking.payload["state"] == "tracking"
  end

  test "scopes operational observable state intervals by replay run without mixing live events",
       %{
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

    [live_interval] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        order: :asc
      )

    assert live_interval.kind == :operational_observable_state
    assert live_interval.subject_kind == :transport
    assert live_interval.subject_id == "transport-alpha"

    assert live_interval.source_event_id ==
             "operational_event:connection_state_snapshot:connection-live-1"

    assert live_interval.payload["connection_state"] == "connected"
    assert live_interval.payload["replay_run_id"] == nil

    [replay_first, replay_second] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:connection-replay-1"

    assert replay_first.payload["connection_state"] == "connecting"
    assert replay_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_first.ends_at, ~U[2026-06-30 12:03:00Z]) == :eq
    assert replay_first.superseded_by_event_id == replay_second.source_event_id

    assert replay_second.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:connection-replay-2"

    assert replay_second.payload["connection_state"] == "connected"
    assert replay_second.payload["replay_run_id"] == "replay-run-1"
    assert replay_second.ends_at == nil

    [other_replay_interval] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_interval.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-2:connection-other-replay"

    assert other_replay_interval.payload["connection_state"] == "disconnected"
  end

  test "segregates typed operational observable state source-record families", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    observed_at = ~U[2026-06-30 12:20:00Z]

    events = [
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        connection_state: :connected,
        observed_at: observed_at
      }),
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        link_id: "link-alpha",
        state: :locked,
        observed_at: DateTime.add(observed_at, 1, :second)
      }),
      Event.from_operational_observable_state_snapshot(%{
        snapshot_id: "shared-state-snapshot",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        link_id: "link-alpha",
        state: :synchronized,
        observed_at: DateTime.add(observed_at, 2, :second)
      })
    ]

    for event <- events do
      assert {:ok, _event} = OperationalEvents.persist_event(event)
    end

    assert [connection_event] =
             Cadence.OperationalEvents.list_events(organization_id, mission_id,
               source_record_kind: :connection_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert [rf_lock_event] =
             Cadence.OperationalEvents.list_events(organization_id, mission_id,
               source_record_kind: :link_rf_lock_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert [frame_sync_event] =
             Cadence.OperationalEvents.list_events(organization_id, mission_id,
               source_record_kind: :link_frame_sync_state_snapshot,
               source_record_id: "shared-state-snapshot"
             )

    assert connection_event.event_id ==
             "operational_event:connection_state_snapshot:shared-state-snapshot"

    assert rf_lock_event.event_id ==
             "operational_event:link_rf_lock_state_snapshot:shared-state-snapshot"

    assert frame_sync_event.event_id ==
             "operational_event:link_frame_sync_state_snapshot:shared-state-snapshot"

    [rf_lock_interval] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha"
      )

    assert rf_lock_interval.source_event_id == rf_lock_event.event_id
    assert rf_lock_interval.metadata["source_record_kind"] == :link_rf_lock_state_snapshot

    [frame_sync_interval] =
      Cadence.OperationalEvents.operational_observable_state_intervals(
        organization_id,
        mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha"
      )

    assert frame_sync_interval.source_event_id == frame_sync_event.event_id
    assert frame_sync_interval.metadata["source_record_kind"] == :link_frame_sync_state_snapshot
  end

  test "projects typed RF state facts into native link RF intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "rf-lock-live-1",
               :acquiring,
               ~U[2026-06-30 12:30:00Z],
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
               :locked,
               ~U[2026-06-30 12:31:00Z],
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
               ~U[2026-06-30 12:32:00Z],
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
               :degraded,
               ~U[2026-06-30 12:33:00Z],
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
               "frame-sync-replay-1",
               :synchronized,
               ~U[2026-06-30 12:31:30Z],
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_lock] =
      Cadence.OperationalEvents.link_rf_state_intervals(organization_id, mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        order: :asc
      )

    assert live_lock.kind == :link_rf_lock_state
    assert live_lock.subject_kind == :link
    assert live_lock.subject_id == "link-alpha"

    assert live_lock.source_event_id ==
             "operational_event:link_rf_lock_state_snapshot:rf-lock-live-1"

    assert live_lock.payload["rf_state_family"] == :rf_lock
    assert live_lock.payload["rf_lock_state"] == "acquiring"
    assert live_lock.payload["frame_sync_state"] == nil
    assert live_lock.payload["replay_run_id"] == nil
    assert live_lock.metadata["source_record_kind"] == :link_rf_lock_state_snapshot

    [replay_lock_first, replay_frame_sync, replay_lock_second] =
      Cadence.OperationalEvents.link_rf_state_intervals(organization_id, mission_id,
        resource_id: "link-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_lock_first.kind == :link_rf_lock_state
    assert replay_lock_first.payload["rf_lock_state"] == "locked"
    assert replay_lock_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_lock_first.ends_at, ~U[2026-06-30 12:33:00Z]) == :eq
    assert replay_lock_first.superseded_by_event_id == replay_lock_second.source_event_id

    assert replay_frame_sync.kind == :link_frame_sync_state

    assert replay_frame_sync.source_event_id ==
             "operational_event:link_frame_sync_state_snapshot:replay-run-1:frame-sync-replay-1"

    assert replay_frame_sync.payload["rf_state_family"] == :frame_sync
    assert replay_frame_sync.payload["frame_sync_state"] == "synchronized"
    assert replay_frame_sync.payload["rf_lock_state"] == nil

    assert replay_lock_second.kind == :link_rf_lock_state
    assert replay_lock_second.payload["rf_lock_state"] == "degraded"
    assert replay_lock_second.ends_at == nil

    [other_replay_lock] =
      Cadence.OperationalEvents.link_rf_state_intervals(organization_id, mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_lock.payload["rf_lock_state"] == "unlocked"

    [family_filtered] =
      Cadence.OperationalEvents.link_rf_state_intervals(organization_id, mission_id,
        rf_state_family: :frame_sync,
        replay_run_id: "replay-run-1"
      )

    assert family_filtered.kind == :link_frame_sync_state
  end

  test "projects typed connection state facts into native connection intervals", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-live-1",
               :connecting,
               ~U[2026-06-30 12:40:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-replay-1",
               :connected,
               ~U[2026-06-30 12:41:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-other-replay",
               :disconnected,
               ~U[2026-06-30 12:42:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "transport-connection-replay-2",
               :degraded,
               ~U[2026-06-30 12:43:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_state_event(
               organization_id,
               mission_id,
               "ground-connection-replay-1",
               :connected,
               ~U[2026-06-30 12:41:30Z],
               observable_id: "ground.station.connection_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_transport] =
      Cadence.OperationalEvents.connection_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        order: :asc
      )

    assert live_transport.kind == :transport_connection_state
    assert live_transport.subject_kind == :transport
    assert live_transport.subject_id == "transport-alpha"

    assert live_transport.source_event_id ==
             "operational_event:connection_state_snapshot:transport-connection-live-1"

    assert live_transport.payload["connection_state_family"] == :transport
    assert live_transport.payload["transport_connection_state"] == "connecting"
    assert live_transport.payload["ground_station_connection_state"] == nil
    assert live_transport.payload["replay_run_id"] == nil
    assert live_transport.metadata["source_record_kind"] == :connection_state_snapshot

    [replay_transport_first, replay_ground_station, replay_transport_second] =
      Cadence.OperationalEvents.connection_state_intervals(organization_id, mission_id,
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_transport_first.kind == :transport_connection_state
    assert replay_transport_first.payload["connection_state"] == "connected"
    assert replay_transport_first.payload["transport_connection_state"] == "connected"
    assert replay_transport_first.payload["replay_run_id"] == "replay-run-1"
    assert DateTime.compare(replay_transport_first.ends_at, ~U[2026-06-30 12:43:00Z]) == :eq

    assert replay_transport_first.superseded_by_event_id ==
             replay_transport_second.source_event_id

    assert replay_ground_station.kind == :ground_station_connection_state
    assert replay_ground_station.subject_kind == :ground_station
    assert replay_ground_station.subject_id == "dss-14"

    assert replay_ground_station.source_event_id ==
             "operational_event:connection_state_snapshot:replay-run-1:ground-connection-replay-1"

    assert replay_ground_station.payload["connection_state_family"] == :ground_station
    assert replay_ground_station.payload["ground_station_connection_state"] == "connected"
    assert replay_ground_station.payload["transport_connection_state"] == nil

    assert replay_transport_second.kind == :transport_connection_state
    assert replay_transport_second.payload["connection_state"] == "degraded"
    assert replay_transport_second.ends_at == nil

    [other_replay_transport] =
      Cadence.OperationalEvents.connection_state_intervals(organization_id, mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: "transport-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_transport.payload["connection_state"] == "disconnected"

    [family_filtered] =
      Cadence.OperationalEvents.connection_state_intervals(organization_id, mission_id,
        connection_state_family: :ground_station,
        replay_run_id: "replay-run-1"
      )

    assert family_filtered.kind == :ground_station_connection_state
  end

  test "scopes operational observable metric samples by replay run without mixing live events",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-live-1",
               11.5,
               ~U[2026-06-30 12:00:00Z]
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-replay-1",
               12.25,
               ~U[2026-06-30 12:01:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-other-replay",
               7.5,
               ~U[2026-06-30 12:02:00Z],
               replay_run_id: "replay-run-2"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _event} =
             operational_observable_metric_event(
               organization_id,
               mission_id,
               "rf-snr-replay-2",
               14.0,
               ~U[2026-06-30 12:03:00Z],
               replay_run_id: "replay-run-1"
             )
             |> OperationalEvents.persist_event()

    [live_sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        order: :asc
      )

    assert live_sample.observable_id == "link.snr_db"
    assert live_sample.resource_id == "link-alpha"
    assert live_sample.scope_kind == "link"
    assert live_sample.snr_db == 11.5
    assert Map.get(live_sample, :replay_run_id) == nil

    [replay_first, replay_second] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-1",
        order: :asc
      )

    assert replay_first.snr_db == 12.25
    assert replay_first.replay_run_id == "replay-run-1"
    assert replay_first.observed_at == ~U[2026-06-30 12:01:00Z]

    assert replay_second.snr_db == 14.0
    assert replay_second.replay_run_id == "replay-run-1"
    assert replay_second.observed_at == ~U[2026-06-30 12:03:00Z]

    [other_replay_sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        replay_run_id: "replay-run-2",
        order: :asc
      )

    assert other_replay_sample.snr_db == 7.5
  end

  test "preserves uplink bitrate fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "uplink-bitrate-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        uplink_bitrate: 4_800.0,
        uplink_bitrate_bps: 4_800.0,
        unit: "bit/s",
        observed_at: ~U[2026-06-30 12:04:00Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: "transport-alpha"
      )

    assert sample.observable_id == "comms.transport.uplink_bitrate"
    assert sample.resource_id == "transport-alpha"
    assert sample.scope_kind == "transport"
    assert sample.uplink_bitrate == 4_800.0
    assert sample.uplink_bitrate_bps == 4_800.0
    assert sample.unit == "bit/s"
  end

  test "preserves RF Eb/N0 fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-ebn0-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        eb_n0_db: 8.25,
        ebn0_db: 8.25,
        energy_per_bit_to_noise_density_db: 8.25,
        unit: "dB",
        observed_at: ~U[2026-06-30 12:04:30Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.eb_n0_db"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.eb_n0_db == 8.25
    assert sample.ebn0_db == 8.25
    assert sample.energy_per_bit_to_noise_density_db == 8.25
    assert sample.unit == "dB"
  end

  test "preserves RF symbol-rate fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-symbol-rate-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        symbol_rate_sps: 1_024_000.0,
        symbol_rate: 1_024_000.0,
        symbols_per_second: 1_024_000.0,
        unit: "sym/s",
        observed_at: ~U[2026-06-30 12:04:45Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.symbol_rate_sps"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.symbol_rate_sps == 1_024_000.0
    assert sample.symbol_rate == 1_024_000.0
    assert sample.symbols_per_second == 1_024_000.0
    assert sample.unit == "sym/s"
  end

  test "preserves RF Doppler fields in operational observable metric samples", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    event =
      Event.from_operational_observable_metric_sample(%{
        sample_id: "rf-doppler-live-1",
        organization_id: organization_id,
        mission_id: mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        doppler_hz: -42.5,
        frequency_offset_hz: -42.5,
        carrier_frequency_offset_hz: -42.5,
        unit: "Hz",
        observed_at: ~U[2026-06-30 12:05:00Z]
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    [sample] =
      Cadence.OperationalEvents.operational_observable_metric_samples(organization_id, mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha"
      )

    assert sample.observable_id == "link.doppler_hz"
    assert sample.resource_id == "link-alpha"
    assert sample.scope_kind == "link"
    assert sample.doppler_hz == -42.5
    assert sample.frequency_offset_hz == -42.5
    assert sample.carrier_frequency_offset_hz == -42.5
    assert sample.unit == "Hz"
  end
end
