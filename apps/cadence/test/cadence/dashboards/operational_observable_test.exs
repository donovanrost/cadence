defmodule Cadence.Dashboards.OperationalObservableTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    OperationalObservable,
    WidgetFrameContract,
    WidgetRegistry
  }

  alias Cadence.Dashboards.Sources.OperationalObservables

  test "publishes stable first-party operational observable definitions" do
    ids = OperationalObservable.ids()

    assert "comms.transport.downlink_bitrate" in ids
    assert "comms.transport.uplink_bitrate" in ids
    assert "comms.transport.connection_state" in ids
    assert "comms.transport.execution_state" in ids
    assert "ground.station.connection_state" in ids
    assert "ground.station.antenna_pointing_state" in ids
    assert "link.rf_lock_state" in ids
    assert "link.frame_sync_state" in ids
    assert "link.snr_db" in ids
    assert "link.eb_n0_db" in ids
    assert "link.symbol_rate_sps" in ids
    assert "link.doppler_hz" in ids
    assert "contacts.phase" in ids
    assert "commanding.queue_depth" in ids
    assert "runtime.managed_activity" in ids
    assert "runtime.transport_activity" in ids
    assert "ingress.processing_latency_ms" in ids
  end

  test "defines bit-rate and connection-state semantics without telemetry dictionary binding" do
    assert {:ok, downlink_bitrate} =
             OperationalObservable.fetch("comms.transport.downlink_bitrate")

    assert downlink_bitrate.logical_source == :operational_observables
    assert downlink_bitrate.value_kind == :metric
    assert downlink_bitrate.value_type == :float
    assert downlink_bitrate.unit == "bit/s"
    assert downlink_bitrate.primary_scope == :transport
    assert :ground_station in downlink_bitrate.optional_scopes
    assert :link in downlink_bitrate.optional_scopes

    assert {:ok, uplink_bitrate} =
             OperationalObservable.fetch("comms.transport.uplink_bitrate")

    assert uplink_bitrate.value_kind == :metric
    assert uplink_bitrate.value_type == :float
    assert uplink_bitrate.unit == "bit/s"
    assert uplink_bitrate.primary_scope == :transport
    assert uplink_bitrate.product == :comms_transport

    assert {:ok, connection_state} =
             OperationalObservable.fetch("ground.station.connection_state")

    assert connection_state.value_kind == :state
    assert connection_state.value_type == :enum
    assert connection_state.state_color_policy == :connection_state
    assert connection_state.primary_scope == :ground_station
    assert :connected in connection_state.enum_values
    assert :disconnected in connection_state.enum_values

    assert {:ok, antenna_pointing_state} =
             OperationalObservable.fetch("ground.station.antenna_pointing_state")

    assert antenna_pointing_state.value_kind == :state
    assert antenna_pointing_state.value_type == :enum
    assert antenna_pointing_state.state_color_policy == :antenna_pointing_state
    assert antenna_pointing_state.primary_scope == :ground_station
    assert antenna_pointing_state.product == :ground_station
    assert :tracking in antenna_pointing_state.enum_values
    assert :slewing in antenna_pointing_state.enum_values

    assert {:ok, rf_lock_state} = OperationalObservable.fetch("link.rf_lock_state")

    assert rf_lock_state.value_kind == :state
    assert rf_lock_state.value_type == :enum
    assert rf_lock_state.state_color_policy == :lock_state
    assert rf_lock_state.primary_scope == :link
    assert rf_lock_state.product == :link_rf
    assert :locked in rf_lock_state.enum_values
    assert :unlocked in rf_lock_state.enum_values

    assert {:ok, frame_sync_state} = OperationalObservable.fetch("link.frame_sync_state")

    assert frame_sync_state.value_kind == :state
    assert frame_sync_state.value_type == :enum
    assert frame_sync_state.state_color_policy == :frame_sync_state
    assert frame_sync_state.primary_scope == :link
    assert frame_sync_state.product == :link_rf
    assert :synchronized in frame_sync_state.enum_values
    assert :lost in frame_sync_state.enum_values

    assert {:ok, snr} = OperationalObservable.fetch("link.snr_db")

    assert snr.value_kind == :metric
    assert snr.value_type == :float
    assert snr.unit == "dB"
    assert snr.primary_scope == :link
    assert snr.product == :link_rf

    assert {:ok, eb_n0} = OperationalObservable.fetch("link.eb_n0_db")

    assert eb_n0.value_kind == :metric
    assert eb_n0.value_type == :float
    assert eb_n0.unit == "dB"
    assert eb_n0.primary_scope == :link
    assert eb_n0.product == :link_rf

    assert {:ok, symbol_rate} = OperationalObservable.fetch("link.symbol_rate_sps")

    assert symbol_rate.value_kind == :metric
    assert symbol_rate.value_type == :float
    assert symbol_rate.unit == "sym/s"
    assert symbol_rate.primary_scope == :link
    assert symbol_rate.product == :link_rf

    assert {:ok, doppler} = OperationalObservable.fetch("link.doppler_hz")

    assert doppler.value_kind == :metric
    assert doppler.value_type == :float
    assert doppler.unit == "Hz"
    assert doppler.primary_scope == :link
    assert doppler.product == :link_rf

    assert {:ok, execution_state} =
             OperationalObservable.fetch("comms.transport.execution_state")

    assert execution_state.value_kind == :state
    assert execution_state.value_type == :enum
    assert execution_state.state_color_policy == :transport_execution_state
    assert execution_state.primary_scope == :transport
    assert :ground_station in execution_state.optional_scopes
    assert :link in execution_state.optional_scopes
    assert execution_state.product == :comms_transport
    assert :control_input_handled in execution_state.enum_values

    assert {:ok, managed_activity} = OperationalObservable.fetch("runtime.managed_activity")

    assert managed_activity.value_kind == :state
    assert managed_activity.value_type == :enum
    assert managed_activity.state_color_policy == :managed_runtime_activity
    assert managed_activity.primary_scope == :mission
    assert :spacecraft in managed_activity.optional_scopes
    assert managed_activity.product == :runtime_managed
    assert :managed_action_requested in managed_activity.enum_values
    assert :managed_timer_fired in managed_activity.enum_values

    assert {:ok, transport_activity} = OperationalObservable.fetch("runtime.transport_activity")

    assert transport_activity.value_kind == :state
    assert transport_activity.value_type == :enum
    assert transport_activity.state_color_policy == :transport_runtime_activity
    assert transport_activity.primary_scope == :mission
    assert :transport in transport_activity.optional_scopes
    assert :contact in transport_activity.optional_scopes
    assert transport_activity.product == :runtime_transport
    assert :transport_action_requested in transport_activity.enum_values
    assert :transport_timer_fired in transport_activity.enum_values
  end

  test "exports serializable registry metadata for source capabilities" do
    metadata = OperationalObservable.metadata()

    assert metadata.registry_version == 1
    assert "contacts.phase" in metadata.observable_ids

    assert metadata.backed_observable_ids == [
             "comms.transport.downlink_bitrate",
             "comms.transport.uplink_bitrate",
             "comms.transport.execution_state",
             "comms.transport.connection_state",
             "ground.station.connection_state",
             "ground.station.antenna_pointing_state",
             "link.rf_lock_state",
             "link.frame_sync_state",
             "link.snr_db",
             "link.eb_n0_db",
             "link.symbol_rate_sps",
             "link.doppler_hz",
             "contacts.phase",
             "commanding.queue_depth",
             "runtime.managed_activity",
             "runtime.transport_activity",
             "ingress.processing_latency_ms"
           ]

    assert Enum.any?(metadata.definitions, fn definition ->
             definition.observable_id == "commanding.queue_depth" and
               definition.primary_scope == :mission and
               definition.unit == "commands"
           end)
  end

  test "returns unknown for unsupported operational observable ids" do
    refute OperationalObservable.known?("HK.counter")
    assert {:error, :unknown_operational_observable} = OperationalObservable.fetch("HK.counter")
  end

  test "tracks which semantic definitions are currently source-backed" do
    assert OperationalObservable.backed?("contacts.phase")
    assert OperationalObservable.backed?("comms.transport.downlink_bitrate")
    assert OperationalObservable.backed?("comms.transport.uplink_bitrate")
    assert OperationalObservable.backed?("comms.transport.execution_state")
    assert OperationalObservable.backed?("comms.transport.connection_state")
    assert OperationalObservable.backed?("ground.station.connection_state")
    assert OperationalObservable.backed?("ground.station.antenna_pointing_state")
    assert OperationalObservable.backed?("link.rf_lock_state")
    assert OperationalObservable.backed?("link.frame_sync_state")
    assert OperationalObservable.backed?("link.snr_db")
    assert OperationalObservable.backed?("link.eb_n0_db")
    assert OperationalObservable.backed?("link.symbol_rate_sps")
    assert OperationalObservable.backed?("link.doppler_hz")
    assert OperationalObservable.backed?("commanding.queue_depth")
    assert OperationalObservable.backed?("runtime.managed_activity")
    assert OperationalObservable.backed?("runtime.transport_activity")
    assert OperationalObservable.backed?("ingress.processing_latency_ms")
    refute OperationalObservable.backed?("HK.counter")
  end

  test "keeps source-backed operational observable contract aligned with registry metadata" do
    registry_backed_ids = OperationalObservable.backed_ids()
    source_backed_ids = OperationalObservables.backed_observable_ids()

    assert MapSet.new(source_backed_ids) == MapSet.new(registry_backed_ids)

    metadata = OperationalObservables.capabilities().metadata
    assert MapSet.new(metadata.source_backed_observable_ids) == MapSet.new(registry_backed_ids)

    assert Enum.all?(registry_backed_ids, &OperationalObservables.backed_observable?/1)
  end

  test "every source-backed operational observable has widget and scope support" do
    widgets = WidgetRegistry.list_types()

    for observable_id <- OperationalObservable.backed_ids() do
      assert {:ok, observable} = OperationalObservable.fetch(observable_id)

      supported_widgets =
        Enum.filter(
          widgets,
          &WidgetFrameContract.operational_observable_supported?(&1, observable)
        )

      assert supported_widgets != [],
             "#{observable_id} is source-backed but has no widget contract support"

      assert WidgetFrameContract.operational_observable_scopes(observable) != [],
             "#{observable_id} is source-backed but has no runtime scope support"
    end
  end
end
