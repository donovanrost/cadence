defmodule Cadence.Dashboards.WidgetFrameContractTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{OperationalObservable, WidgetFrameContract, WidgetRegistry}

  test "uses telemetry frame contract by default for value tiles" do
    widget_type = fetch_type!("cadence.value_tile")

    assert WidgetFrameContract.primary_supported_sources(widget_type) == [
             :telemetry,
             :operational_observables
           ]

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling: :latest
             })

    assert frame_spec.source == :telemetry
    assert frame_spec.accepted_shapes == [:scalar]
    assert frame_spec.sampling == :latest
  end

  test "applies declared operational source override for value tiles" do
    widget_type = fetch_type!("cadence.value_tile")
    bitrate = fetch_operational_observable!("comms.transport.downlink_bitrate")
    snr = fetch_operational_observable!("link.snr_db")
    command_queue_depth = fetch_operational_observable!("commanding.queue_depth")
    ingress_latency = fetch_operational_observable!("ingress.processing_latency_ms")
    contact_phase = fetch_operational_observable!("contacts.phase")

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["comms.transport.downlink_bitrate"],
               sampling: :latest
             })

    assert frame_spec.source == :operational_observables
    assert frame_spec.contract_source == :telemetry
    assert frame_spec.accepted_shapes == [:matrix]
    assert frame_spec.products == [:transport_bitrate, :link_rf, :commanding, :runtime_ingress]
    assert frame_spec.observable_value_kinds == [:metric]
    assert WidgetFrameContract.operational_observable_supported?(widget_type, bitrate)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, snr)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, command_queue_depth)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, ingress_latency)
    refute WidgetFrameContract.operational_observable_supported?(widget_type, contact_phase)
  end

  test "rejects operational observables outside effective frame products" do
    widget_type = fetch_type!("cadence.value_tile")

    assert {:error, details} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["comms.transport.connection_state"],
               sampling: :latest
             })

    assert details.widget_type_id == "cadence.value_tile"
    assert details.requested_source == :operational_observables
    assert details.unsupported_observables == ["comms.transport.connection_state"]

    assert details.supported_products == [
             :transport_bitrate,
             :link_rf,
             :commanding,
             :runtime_ingress
           ]

    assert details.supported_value_kinds == [:metric]
    assert details.requested_products == [:connection_state]
    assert details.requested_value_kinds == [:state]
  end

  test "reports operational observable scope support" do
    assert WidgetFrameContract.operational_observable_scopes("comms.transport.downlink_bitrate") ==
             [:transport, :spacecraft, :contact, :ground_station, :source_endpoint, :link]

    assert WidgetFrameContract.supported_operational_observable_scopes([
             "comms.transport.downlink_bitrate",
             "commanding.queue_depth"
           ]) == %{
             "comms.transport.downlink_bitrate" => [
               :transport,
               :spacecraft,
               :contact,
               :ground_station,
               :source_endpoint,
               :link
             ],
             "commanding.queue_depth" => [:mission, :spacecraft, :contact, :source_endpoint]
           }

    assert WidgetFrameContract.operational_observable_scopes("comms.transport.execution_state") ==
             [
               :transport,
               :spacecraft,
               :contact,
               :source_endpoint,
               :ground_station,
               :link
             ]

    assert WidgetFrameContract.unsupported_operational_observable_scope_ids(
             ["comms.transport.downlink_bitrate", "commanding.queue_depth"],
             :mission
           ) == ["comms.transport.downlink_bitrate"]

    assert WidgetFrameContract.unsupported_operational_observable_scope_ids(
             ["comms.transport.downlink_bitrate", "commanding.queue_depth"],
             "source-endpoint"
           ) == []

    assert WidgetFrameContract.unsupported_operational_observable_scope_ids(
             ["comms.transport.connection_state", "ground.station.connection_state"],
             :mission
           ) == []
  end

  test "applies declared operational source override for status matrices" do
    widget_type = fetch_type!("cadence.status_matrix")
    bitrate = fetch_operational_observable!("comms.transport.downlink_bitrate")
    snr = fetch_operational_observable!("link.snr_db")
    command_queue_depth = fetch_operational_observable!("commanding.queue_depth")
    ingress_latency = fetch_operational_observable!("ingress.processing_latency_ms")
    contact_phase = fetch_operational_observable!("contacts.phase")
    connection_state = fetch_operational_observable!("ground.station.connection_state")

    antenna_pointing_state =
      fetch_operational_observable!("ground.station.antenna_pointing_state")

    rf_lock_state = fetch_operational_observable!("link.rf_lock_state")
    frame_sync_state = fetch_operational_observable!("link.frame_sync_state")

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling: :latest
             })

    assert frame_spec.source == :operational_observables
    assert frame_spec.accepted_shapes == [:matrix]

    assert frame_spec.products == [
             :contacts_phase,
             :connection_state,
             :ground_station,
             :link_rf,
             :transport_bitrate,
             :commanding,
             :runtime_ingress
           ]

    assert frame_spec.observable_value_kinds == [:metric, :state]
    assert WidgetFrameContract.operational_observable_supported?(widget_type, bitrate)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, snr)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, command_queue_depth)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, ingress_latency)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, contact_phase)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, connection_state)

    assert WidgetFrameContract.operational_observable_supported?(
             widget_type,
             antenna_pointing_state
           )

    assert WidgetFrameContract.operational_observable_supported?(widget_type, rf_lock_state)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, frame_sync_state)
  end

  test "applies declared operational source override for data tables" do
    widget_type = fetch_type!("cadence.data_table")
    bitrate = fetch_operational_observable!("comms.transport.downlink_bitrate")
    snr = fetch_operational_observable!("link.snr_db")
    command_queue_depth = fetch_operational_observable!("commanding.queue_depth")
    ingress_latency = fetch_operational_observable!("ingress.processing_latency_ms")
    contact_phase = fetch_operational_observable!("contacts.phase")
    connection_state = fetch_operational_observable!("ground.station.connection_state")

    antenna_pointing_state =
      fetch_operational_observable!("ground.station.antenna_pointing_state")

    rf_lock_state = fetch_operational_observable!("link.rf_lock_state")

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling: :latest
             })

    assert frame_spec.source == :operational_observables
    assert frame_spec.accepted_shapes == [:matrix]

    assert frame_spec.products == [
             :contacts_phase,
             :connection_state,
             :ground_station,
             :link_rf,
             :transport_bitrate,
             :commanding,
             :runtime_ingress
           ]

    assert frame_spec.observable_value_kinds == [:metric, :state]
    assert WidgetFrameContract.operational_observable_supported?(widget_type, bitrate)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, snr)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, command_queue_depth)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, ingress_latency)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, contact_phase)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, connection_state)

    assert WidgetFrameContract.operational_observable_supported?(
             widget_type,
             antenna_pointing_state
           )

    assert WidgetFrameContract.operational_observable_supported?(widget_type, rf_lock_state)
  end

  test "declares an events primary frame contract for event timelines" do
    widget_type = fetch_type!("cadence.event_timeline")

    assert WidgetFrameContract.primary_supported_sources(widget_type) == [:events]
    assert WidgetFrameContract.supports_primary_source?(widget_type, :events)
    assert :source_watermark_event in widget_type.drilldown_contract.supported_targets

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :events,
               observables: [],
               sampling: :event_history
             })

    assert frame_spec.source == :events
    assert frame_spec.accepted_shapes == [:events, :intervals]

    assert frame_spec.products == [
             :contact_intervals,
             :mission_timeline,
             :source_health_transitions,
             :source_watermark_events,
             :source_capability_postures,
             :telemetry_backfill_lifecycle,
             :telemetry_revision_decisions
           ]

    assert frame_spec.families == [
             :contacts,
             :mission_timeline,
             :source_health,
             :source_watermarks,
             :source_capabilities,
             :telemetry_backfills,
             :telemetry_revisions
           ]

    assert frame_spec.sampling == :event_history
    assert frame_spec.temporal?
  end

  test "declares limits and operational event-history primary frame contracts for state timelines" do
    widget_type = fetch_type!("cadence.state_timeline")
    contact_phase = fetch_operational_observable!("contacts.phase")
    connection_state = fetch_operational_observable!("ground.station.connection_state")

    antenna_pointing_state =
      fetch_operational_observable!("ground.station.antenna_pointing_state")

    rf_lock_state = fetch_operational_observable!("link.rf_lock_state")
    frame_sync_state = fetch_operational_observable!("link.frame_sync_state")
    transport_execution_state = fetch_operational_observable!("comms.transport.execution_state")
    bitrate = fetch_operational_observable!("comms.transport.downlink_bitrate")

    assert WidgetFrameContract.primary_supported_sources(widget_type) == [
             :operational_observables,
             :limits
           ]

    assert WidgetFrameContract.supports_primary_source?(widget_type, :limits)
    assert WidgetFrameContract.supports_primary_source?(widget_type, :operational_observables)

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :limits,
               observables: ["tlm.hk.battery_voltage"],
               sampling: :event_history
             })

    assert frame_spec.source == :limits
    assert frame_spec.accepted_shapes == [:events, :scalar]
    assert frame_spec.products == [:event_history]
    assert frame_spec.sampling == :event_history
    assert frame_spec.temporal?

    assert {:ok, [operational_frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["contacts.phase", "ground.station.connection_state"],
               sampling: :event_history
             })

    assert operational_frame_spec.source == :operational_observables
    assert operational_frame_spec.contract_source == :limits
    assert operational_frame_spec.accepted_shapes == [:events]

    assert operational_frame_spec.products == [
             :contacts_phase,
             :connection_state,
             :ground_station,
             :link_rf,
             :runtime_managed,
             :runtime_transport,
             :transport_execution_state
           ]

    assert operational_frame_spec.observable_value_kinds == [:state]
    assert operational_frame_spec.sampling == :event_history
    assert operational_frame_spec.temporal?

    assert WidgetFrameContract.operational_observable_supported?(widget_type, contact_phase)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, connection_state)

    assert WidgetFrameContract.operational_observable_supported?(
             widget_type,
             antenna_pointing_state
           )

    assert WidgetFrameContract.operational_observable_supported?(widget_type, rf_lock_state)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, frame_sync_state)

    assert WidgetFrameContract.operational_observable_supported?(
             widget_type,
             transport_execution_state
           )

    refute WidgetFrameContract.operational_observable_supported?(widget_type, bitrate)
  end

  test "declares metric-only operational source override for time series" do
    widget_type = fetch_type!("cadence.time_series")
    bitrate = fetch_operational_observable!("comms.transport.downlink_bitrate")
    snr = fetch_operational_observable!("link.snr_db")
    ingress_latency = fetch_operational_observable!("ingress.processing_latency_ms")
    contact_phase = fetch_operational_observable!("contacts.phase")

    assert WidgetFrameContract.primary_supported_sources(widget_type) == [
             :telemetry,
             :operational_observables
           ]

    assert WidgetFrameContract.supports_primary_source?(widget_type, :telemetry)
    assert WidgetFrameContract.supports_primary_source?(widget_type, :operational_observables)

    assert {:ok, [frame_spec]} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: [
                 "comms.transport.downlink_bitrate",
                 "link.snr_db",
                 "ingress.processing_latency_ms"
               ],
               sampling: :raw_series
             })

    assert frame_spec.source == :operational_observables
    assert frame_spec.contract_source == :telemetry
    assert frame_spec.accepted_shapes == [:wide]
    assert frame_spec.products == [:transport_bitrate, :link_rf, :runtime_ingress]
    assert frame_spec.observable_value_kinds == [:metric]
    assert frame_spec.sampling == :raw_series
    assert frame_spec.temporal?

    assert WidgetFrameContract.operational_observable_supported?(widget_type, bitrate)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, snr)
    assert WidgetFrameContract.operational_observable_supported?(widget_type, ingress_latency)
    refute WidgetFrameContract.operational_observable_supported?(widget_type, contact_phase)

    assert {:error, details} =
             WidgetFrameContract.primary_frame_specs(widget_type, %{
               source: :operational_observables,
               observables: ["contacts.phase"],
               sampling: :raw_series
             })

    assert details.widget_type_id == "cadence.time_series"
    assert details.requested_source == :operational_observables
    assert details.supported_products == [:transport_bitrate, :link_rf, :runtime_ingress]
    assert details.supported_value_kinds == [:metric]
    assert details.requested_products == [:contacts_phase]
    assert details.requested_value_kinds == [:state]
    assert details.accepted_shapes == [:wide]
  end

  defp fetch_type!(widget_type_id) do
    assert {:ok, widget_type} = WidgetRegistry.fetch_type(widget_type_id, :latest)
    widget_type
  end

  defp fetch_operational_observable!(observable_id) do
    assert {:ok, observable} = OperationalObservable.fetch(observable_id)
    observable
  end
end
