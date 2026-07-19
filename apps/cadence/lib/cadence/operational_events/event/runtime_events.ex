defmodule Cadence.OperationalEvents.Event.RuntimeEvents do
  @moduledoc false

  import Cadence.OperationalEvents.Event.Normalization

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

  def from_operational_observable_state_snapshot(attrs, build_event) when is_map(attrs) do
    snapshot_id =
      attrs
      |> Map.get(:snapshot_id, Map.get(attrs, "snapshot_id", Map.get(attrs, :source_record_id)))
      |> text_value!()

    observed_at = operational_observable_observed_at(attrs)

    replay_run_id = text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    payload = operational_observable_state_payload(attrs, observed_at)
    scope_kind = Map.fetch!(payload, :scope_kind)
    resource_id = Map.fetch!(payload, :resource_id)
    source_record_kind = operational_observable_state_source_record_kind(payload.observable_id)

    build_event.(%{
      event_id: scoped_event_id(source_record_kind, snapshot_id, replay_run_id),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: observed_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", observed_at)),
      effective_at: observed_at,
      category: Map.get(attrs, :category, Map.get(attrs, "category", :comms)),
      kind: Map.get(attrs, :kind, Map.get(attrs, "kind", :operational_observable_state_changed)),
      severity: Map.get(attrs, :severity, Map.get(attrs, "severity", :info)),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: %{kind: operational_observable_subject_kind(scope_kind), id: resource_id},
      scope: operational_observable_scope(payload, replay_run_id),
      causality:
        %{
          correlation_id: "#{payload.observable_id}:#{resource_id}",
          source_record_kind: source_record_kind,
          source_record_id: snapshot_id,
          replay_run_id: replay_run_id
        }
        |> compact(),
      payload: payload,
      current: payload,
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  def from_operational_observable_metric_sample(attrs, build_event) when is_map(attrs) do
    sample_id =
      attrs
      |> Map.get(:sample_id, Map.get(attrs, "sample_id", Map.get(attrs, :source_record_id)))
      |> text_value!()

    observed_at = operational_observable_observed_at(attrs)

    replay_run_id = text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    payload = operational_observable_metric_payload(attrs, observed_at)
    scope_kind = Map.fetch!(payload, :scope_kind)
    resource_id = Map.fetch!(payload, :resource_id)

    build_event.(%{
      event_id: scoped_event_id(:operational_observable_snapshot, sample_id, replay_run_id),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_required(attrs, :mission_id),
      occurred_at: observed_at,
      recorded_at: Map.get(attrs, :recorded_at, Map.get(attrs, "recorded_at", observed_at)),
      effective_at: observed_at,
      category: Map.get(attrs, :category, Map.get(attrs, "category", :comms)),
      kind: Map.get(attrs, :kind, Map.get(attrs, "kind", :operational_observable_metric_sampled)),
      severity: Map.get(attrs, :severity, Map.get(attrs, "severity", :info)),
      actor: Map.get(attrs, :actor, Map.get(attrs, "actor", %{kind: :system})),
      subject: %{kind: operational_observable_subject_kind(scope_kind), id: resource_id},
      scope: operational_observable_scope(payload, replay_run_id),
      causality:
        %{
          correlation_id: "#{payload.observable_id}:#{resource_id}",
          source_record_kind: :operational_observable_snapshot,
          source_record_id: sample_id,
          replay_run_id: replay_run_id
        }
        |> compact(),
      payload: payload,
      current: payload,
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    })
  end

  def from_transport_capability_record(
        %TransportCapabilityRecord{} = capability_record,
        replay_run_id,
        build_event
      ) do
    scope = maybe_put_replay_run_id(transport_capability_scope(capability_record), replay_run_id)

    payload =
      maybe_put_replay_run_id(transport_capability_payload(capability_record), replay_run_id)

    build_event.(%{
      event_id:
        scoped_event_id(
          :transport_capability_record,
          capability_record.transport_record_id,
          replay_run_id
        ),
      mission_id: capability_record.mission_id,
      occurred_at: capability_record.recorded_at,
      recorded_at: capability_record.recorded_at,
      effective_at: capability_record.recorded_at,
      category: :comms,
      kind: transport_capability_record_kind(capability_record.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: capability_record.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: capability_record.capability_instance_id,
            source_record_kind: :transport_capability_record,
            source_record_id: capability_record.transport_record_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(capability_record.metadata, replay_run_id)
    })
  end

  def from_transport_action_request(
        %TransportActionRequest{} = action_request,
        replay_run_id,
        build_event
      ) do
    scope = maybe_put_replay_run_id(transport_action_scope(action_request), replay_run_id)
    payload = maybe_put_replay_run_id(transport_action_payload(action_request), replay_run_id)

    build_event.(%{
      event_id:
        scoped_event_id(
          :transport_action_request,
          action_request.action_request_id,
          replay_run_id
        ),
      mission_id: action_request.mission_id,
      occurred_at: action_request.requested_at,
      recorded_at: action_request.requested_at,
      effective_at: action_request.requested_at,
      category: :comms,
      kind: :transport_action_requested,
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: action_request.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id:
              action_request.command_release_attempt_id ||
                action_request.command_request_id ||
                action_request.action_request_id,
            causation_event_id: action_request.command_release_attempt_id,
            source_record_kind: :transport_action_request,
            source_record_id: action_request.action_request_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(action_request.metadata, replay_run_id)
    })
  end

  def from_transport_timer_event(%TransportTimerEvent{} = timer_event, replay_run_id, build_event) do
    scope = maybe_put_replay_run_id(transport_timer_scope(timer_event), replay_run_id)
    payload = maybe_put_replay_run_id(transport_timer_payload(timer_event), replay_run_id)

    build_event.(%{
      event_id:
        scoped_event_id(:transport_timer_event, timer_event.timer_event_id, replay_run_id),
      mission_id: timer_event.mission_id,
      occurred_at: timer_event.occurred_at,
      recorded_at: timer_event.occurred_at,
      effective_at: timer_event.occurred_at,
      category: :comms,
      kind: transport_timer_event_kind(timer_event.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :transport, id: timer_event.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: "#{timer_event.capability_instance_id}:#{timer_event.timer_key}",
            source_record_kind: :transport_timer_event,
            source_record_id: timer_event.timer_event_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(timer_event.metadata, replay_run_id)
    })
  end

  def from_managed_capability_record(
        %ManagedCapabilityRecord{} = capability_record,
        replay_run_id,
        build_event
      ) do
    scope = maybe_put_replay_run_id(managed_capability_scope(capability_record), replay_run_id)

    payload =
      maybe_put_replay_run_id(managed_capability_payload(capability_record), replay_run_id)

    build_event.(%{
      event_id:
        scoped_event_id(
          "managed_capability_record",
          capability_record.capability_record_id,
          replay_run_id
        ),
      mission_id: capability_record.mission_id,
      occurred_at: capability_record.recorded_at,
      recorded_at: capability_record.recorded_at,
      effective_at: capability_record.recorded_at,
      category: :runtime,
      kind: managed_capability_record_kind(capability_record.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: capability_record.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: capability_record.capability_instance_id,
            source_record_kind: :managed_capability_record,
            source_record_id: capability_record.capability_record_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(capability_record.metadata, replay_run_id)
    })
  end

  def from_managed_action_request(
        %ManagedActionRequest{} = action_request,
        replay_run_id,
        build_event
      ) do
    scope = maybe_put_replay_run_id(managed_action_scope(action_request), replay_run_id)
    payload = maybe_put_replay_run_id(managed_action_payload(action_request), replay_run_id)

    build_event.(%{
      event_id:
        scoped_event_id("managed_action_request", action_request.action_request_id, replay_run_id),
      mission_id: action_request.mission_id,
      occurred_at: action_request.requested_at,
      recorded_at: action_request.requested_at,
      effective_at: action_request.requested_at,
      category: :runtime,
      kind: :managed_action_requested,
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: action_request.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: action_request.capability_instance_id,
            source_record_kind: :managed_action_request,
            source_record_id: action_request.action_request_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: action_request.request_document
    })
  end

  def from_managed_timer_event(%ManagedTimerEvent{} = timer_event, replay_run_id, build_event) do
    scope = maybe_put_replay_run_id(managed_timer_scope(timer_event), replay_run_id)
    payload = maybe_put_replay_run_id(managed_timer_payload(timer_event), replay_run_id)

    build_event.(%{
      event_id: scoped_event_id("managed_timer_event", timer_event.timer_event_id, replay_run_id),
      mission_id: timer_event.mission_id,
      occurred_at: timer_event.occurred_at,
      recorded_at: timer_event.occurred_at,
      effective_at: timer_event.occurred_at,
      category: :runtime,
      kind: managed_timer_event_kind(timer_event.event_kind),
      severity: :info,
      actor: replay_actor(replay_run_id),
      subject: %{kind: :capability_instance, id: timer_event.capability_instance_id},
      scope: scope,
      causality:
        maybe_put_replay_run_id(
          %{
            correlation_id: "#{timer_event.capability_instance_id}:#{timer_event.timer_key}",
            source_record_kind: :managed_timer_event,
            source_record_id: timer_event.timer_event_id
          },
          replay_run_id
        ),
      payload: payload,
      current: payload,
      metadata: maybe_put_replay_run_id(timer_event.metadata, replay_run_id)
    })
  end

  defp operational_observable_observed_at(attrs) do
    Map.get(attrs, :observed_at) ||
      Map.get(attrs, "observed_at") ||
      Map.get(attrs, :occurred_at) ||
      Map.fetch!(attrs, "occurred_at")
  end

  defp operational_observable_state_payload(attrs, observed_at) do
    observable_id =
      attrs
      |> Map.get(:observable_id, Map.get(attrs, "observable_id"))
      |> text_value!()

    resource_id =
      attrs
      |> Map.get(:resource_id, Map.get(attrs, "resource_id"))
      |> text_value!()

    scope_kind =
      attrs
      |> Map.get(:scope_kind, Map.get(attrs, "scope_kind", :transport))
      |> normalize_kind()

    %{
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: text_value(Map.get(attrs, :transport_id, Map.get(attrs, "transport_id"))),
      spacecraft_id: text_value(Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id"))),
      contact_id:
        text_value(
          Map.get(
            attrs,
            :contact_id,
            Map.get(
              attrs,
              "contact_id",
              Map.get(attrs, :scheduled_contact_id, Map.get(attrs, :realized_contact_id))
            )
          )
        ),
      scheduled_contact_id:
        text_value(Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id"))),
      realized_contact_id:
        text_value(Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id"))),
      source_endpoint_id:
        text_value(
          Map.get(
            attrs,
            :source_endpoint_id,
            Map.get(attrs, "source_endpoint_id", Map.get(attrs, :source_endpoint_ref))
          )
        ),
      ground_station_id:
        text_value(
          Map.get(
            attrs,
            :ground_station_id,
            Map.get(attrs, "ground_station_id", Map.get(attrs, :antenna_id))
          )
        ),
      link_id:
        text_value(
          Map.get(
            attrs,
            :link_id,
            Map.get(attrs, "link_id", Map.get(attrs, :link_assignment_id))
          )
        ),
      adapter_key: Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key")),
      connection_state: Map.get(attrs, :connection_state, Map.get(attrs, "connection_state")),
      state: Map.get(attrs, :state, Map.get(attrs, "state")),
      normalized_state: Map.get(attrs, :normalized_state, Map.get(attrs, "normalized_state")),
      observed_at: observed_at,
      replay_run_id: text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    }
    |> compact()
  end

  defp operational_observable_metric_payload(attrs, observed_at) do
    observable_id =
      attrs
      |> Map.get(:observable_id, Map.get(attrs, "observable_id"))
      |> text_value!()

    resource_id =
      attrs
      |> Map.get(:resource_id, Map.get(attrs, "resource_id"))
      |> text_value!()

    scope_kind =
      attrs
      |> Map.get(:scope_kind, Map.get(attrs, "scope_kind", :transport))
      |> normalize_kind()

    %{
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: text_value(Map.get(attrs, :transport_id, Map.get(attrs, "transport_id"))),
      spacecraft_id: text_value(Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id"))),
      contact_id:
        text_value(
          Map.get(
            attrs,
            :contact_id,
            Map.get(
              attrs,
              "contact_id",
              Map.get(attrs, :scheduled_contact_id, Map.get(attrs, :realized_contact_id))
            )
          )
        ),
      scheduled_contact_id:
        text_value(Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id"))),
      realized_contact_id:
        text_value(Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id"))),
      source_endpoint_id:
        text_value(
          Map.get(
            attrs,
            :source_endpoint_id,
            Map.get(attrs, "source_endpoint_id", Map.get(attrs, :source_endpoint_ref))
          )
        ),
      ground_station_id:
        text_value(
          Map.get(
            attrs,
            :ground_station_id,
            Map.get(attrs, "ground_station_id", Map.get(attrs, :antenna_id))
          )
        ),
      link_id:
        text_value(
          Map.get(
            attrs,
            :link_id,
            Map.get(attrs, "link_id", Map.get(attrs, :link_assignment_id))
          )
        ),
      adapter_key: Map.get(attrs, :adapter_key, Map.get(attrs, "adapter_key")),
      value: Map.get(attrs, :value, Map.get(attrs, "value")),
      unit: Map.get(attrs, :unit, Map.get(attrs, "unit", Map.get(attrs, :value_unit))),
      downlink_bitrate: Map.get(attrs, :downlink_bitrate, Map.get(attrs, "downlink_bitrate")),
      downlink_bitrate_bps:
        Map.get(attrs, :downlink_bitrate_bps, Map.get(attrs, "downlink_bitrate_bps")),
      uplink_bitrate: Map.get(attrs, :uplink_bitrate, Map.get(attrs, "uplink_bitrate")),
      uplink_bitrate_bps:
        Map.get(attrs, :uplink_bitrate_bps, Map.get(attrs, "uplink_bitrate_bps")),
      bitrate: Map.get(attrs, :bitrate, Map.get(attrs, "bitrate")),
      snr_db: Map.get(attrs, :snr_db, Map.get(attrs, "snr_db")),
      snr: Map.get(attrs, :snr, Map.get(attrs, "snr")),
      signal_to_noise_ratio_db:
        Map.get(attrs, :signal_to_noise_ratio_db, Map.get(attrs, "signal_to_noise_ratio_db")),
      eb_n0_db: Map.get(attrs, :eb_n0_db, Map.get(attrs, "eb_n0_db")),
      ebn0_db: Map.get(attrs, :ebn0_db, Map.get(attrs, "ebn0_db")),
      energy_per_bit_to_noise_density_db:
        Map.get(
          attrs,
          :energy_per_bit_to_noise_density_db,
          Map.get(attrs, "energy_per_bit_to_noise_density_db")
        ),
      symbol_rate_sps: Map.get(attrs, :symbol_rate_sps, Map.get(attrs, "symbol_rate_sps")),
      symbol_rate: Map.get(attrs, :symbol_rate, Map.get(attrs, "symbol_rate")),
      symbols_per_second:
        Map.get(attrs, :symbols_per_second, Map.get(attrs, "symbols_per_second")),
      doppler_hz: Map.get(attrs, :doppler_hz, Map.get(attrs, "doppler_hz")),
      doppler: Map.get(attrs, :doppler, Map.get(attrs, "doppler")),
      frequency_offset_hz:
        Map.get(attrs, :frequency_offset_hz, Map.get(attrs, "frequency_offset_hz")),
      carrier_frequency_offset_hz:
        Map.get(
          attrs,
          :carrier_frequency_offset_hz,
          Map.get(attrs, "carrier_frequency_offset_hz")
        ),
      observed_at: observed_at,
      replay_run_id: text_value(Map.get(attrs, :replay_run_id, Map.get(attrs, "replay_run_id")))
    }
    |> compact()
  end

  defp operational_observable_state_source_record_kind("comms.transport.connection_state"),
    do: :connection_state_snapshot

  defp operational_observable_state_source_record_kind("ground.station.connection_state"),
    do: :connection_state_snapshot

  defp operational_observable_state_source_record_kind("link.rf_lock_state"),
    do: :link_rf_lock_state_snapshot

  defp operational_observable_state_source_record_kind("link.frame_sync_state"),
    do: :link_frame_sync_state_snapshot

  defp operational_observable_state_source_record_kind(_observable_id),
    do: :operational_observable_snapshot

  defp operational_observable_scope(payload, replay_run_id) do
    %{
      logical_source: :operational_observables,
      scope_type: payload.scope_kind,
      scope_ref: payload.resource_id,
      transport_id: Map.get(payload, :transport_id),
      spacecraft_id: Map.get(payload, :spacecraft_id),
      contact_id: Map.get(payload, :contact_id),
      scheduled_contact_id: Map.get(payload, :scheduled_contact_id),
      realized_contact_id: Map.get(payload, :realized_contact_id),
      source_endpoint_id: Map.get(payload, :source_endpoint_id),
      ground_station_id: Map.get(payload, :ground_station_id),
      link_id: Map.get(payload, :link_id),
      replay_run_id: replay_run_id
    }
    |> compact()
  end

  defp operational_observable_subject_kind(kind)
       when kind in [:ground_station, :transport, :link, :spacecraft, :contact, :source_endpoint],
       do: kind

  defp operational_observable_subject_kind(_kind), do: :capability_instance

  defp transport_capability_record_kind(:initialized), do: :transport_initialized

  defp transport_capability_record_kind(:transport_event_handled),
    do: :transport_event_handled

  defp transport_capability_record_kind(:control_input_handled),
    do: :transport_control_input_handled

  defp transport_capability_record_kind(:timer_handled), do: :transport_timer_handled

  defp transport_capability_scope(%TransportCapabilityRecord{} = capability_record) do
    %{
      contact_id: capability_record.realized_contact_id,
      realized_contact_id: capability_record.realized_contact_id,
      path_id: capability_record.path_id,
      capability_instance_id: capability_record.capability_instance_id,
      binding_set_id: capability_record.binding_set_id,
      activation_id: capability_record.activation_id,
      timer_key: capability_record.timer_key
    }
    |> compact()
  end

  defp transport_capability_payload(%TransportCapabilityRecord{} = capability_record) do
    Map.merge(transport_capability_scope(capability_record), %{
      transport_record_id: capability_record.transport_record_id,
      family_key: capability_record.family_key,
      binding_set_version: capability_record.binding_set_version,
      partition_affinity: capability_record.partition_affinity,
      partition_value: capability_record.partition_value,
      event_kind: capability_record.event_kind,
      emitted_record_kinds: capability_record.emitted_record_kinds,
      emitted_record_count: capability_record.emitted_record_count,
      action_request_count: capability_record.action_request_count,
      state_snapshot: capability_record.state_snapshot,
      recorded_at: capability_record.recorded_at,
      record_metadata: capability_record.metadata
    })
  end

  defp transport_action_scope(%TransportActionRequest{} = action_request) do
    %{
      contact_id: action_request.realized_contact_id,
      realized_contact_id: action_request.realized_contact_id,
      path_id: action_request.path_id,
      capability_instance_id: action_request.capability_instance_id,
      source_endpoint_ref: action_request.source_endpoint_ref,
      binding_set_id: action_request.binding_set_id,
      activation_id: action_request.activation_id
    }
    |> compact()
  end

  defp transport_action_payload(%TransportActionRequest{} = action_request) do
    Map.merge(transport_action_scope(action_request), %{
      action_request_id: action_request.action_request_id,
      family_key: action_request.family_key,
      binding_set_version: action_request.binding_set_version,
      partition_affinity: action_request.partition_affinity,
      partition_value: action_request.partition_value,
      command_release_attempt_id: action_request.command_release_attempt_id,
      command_request_id: action_request.command_request_id,
      command_name: action_request.command_name,
      signal_phase: action_request.signal_phase,
      action_kind: action_request.action_kind,
      request_document: action_request.request_document,
      requested_at: action_request.requested_at,
      action_metadata: action_request.metadata
    })
  end

  defp transport_timer_event_kind(:scheduled), do: :transport_timer_scheduled
  defp transport_timer_event_kind(:fired), do: :transport_timer_fired
  defp transport_timer_event_kind(:canceled), do: :transport_timer_canceled

  defp transport_timer_scope(%TransportTimerEvent{} = timer_event) do
    %{
      contact_id: timer_event.realized_contact_id,
      realized_contact_id: timer_event.realized_contact_id,
      path_id: timer_event.path_id,
      capability_instance_id: timer_event.capability_instance_id,
      binding_set_id: timer_event.binding_set_id,
      activation_id: timer_event.activation_id,
      timer_key: timer_event.timer_key
    }
    |> compact()
  end

  defp transport_timer_payload(%TransportTimerEvent{} = timer_event) do
    Map.merge(transport_timer_scope(timer_event), %{
      timer_event_id: timer_event.timer_event_id,
      family_key: timer_event.family_key,
      binding_set_version: timer_event.binding_set_version,
      partition_affinity: timer_event.partition_affinity,
      partition_value: timer_event.partition_value,
      event_kind: timer_event.event_kind,
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      timer_metadata: timer_event.metadata
    })
  end

  defp managed_capability_record_kind(:initialized), do: :managed_capability_initialized
  defp managed_capability_record_kind(:record_handled), do: :managed_capability_record_handled
  defp managed_capability_record_kind(:timer_handled), do: :managed_capability_timer_handled

  defp managed_capability_scope(%ManagedCapabilityRecord{} = capability_record) do
    %{
      capability_instance_id: capability_record.capability_instance_id,
      binding_set_id: capability_record.binding_set_id,
      activation_id: capability_record.activation_id,
      partition_affinity: capability_record.partition_affinity,
      partition_value: capability_record.partition_value,
      packet_id: capability_record.packet_id,
      evidence_id: capability_record.evidence_id,
      timer_key: capability_record.timer_key
    }
    |> compact()
  end

  defp managed_capability_payload(%ManagedCapabilityRecord{} = capability_record) do
    Map.merge(managed_capability_scope(capability_record), %{
      capability_record_id: capability_record.capability_record_id,
      family_key: capability_record.family_key,
      binding_set_version: capability_record.binding_set_version,
      event_kind: capability_record.event_kind,
      emitted_record_kinds: capability_record.emitted_record_kinds,
      emitted_record_count: capability_record.emitted_record_count,
      action_request_count: capability_record.action_request_count,
      state_snapshot: capability_record.state_snapshot,
      recorded_at: capability_record.recorded_at,
      record_metadata: capability_record.metadata
    })
  end

  defp managed_action_scope(%ManagedActionRequest{} = action_request) do
    %{
      capability_instance_id: action_request.capability_instance_id,
      binding_set_id: action_request.binding_set_id,
      activation_id: action_request.activation_id,
      partition_affinity: action_request.partition_affinity,
      partition_value: action_request.partition_value,
      packet_id: action_request.packet_id,
      evidence_id: action_request.evidence_id
    }
    |> compact()
  end

  defp managed_action_payload(%ManagedActionRequest{} = action_request) do
    Map.merge(managed_action_scope(action_request), %{
      action_request_id: action_request.action_request_id,
      family_key: action_request.family_key,
      binding_set_version: action_request.binding_set_version,
      action_kind: action_request.action_kind,
      request_document: action_request.request_document,
      requested_at: action_request.requested_at
    })
  end

  defp managed_timer_event_kind(:scheduled), do: :managed_timer_scheduled
  defp managed_timer_event_kind(:fired), do: :managed_timer_fired
  defp managed_timer_event_kind(:canceled), do: :managed_timer_canceled

  defp managed_timer_scope(%ManagedTimerEvent{} = timer_event) do
    %{
      capability_instance_id: timer_event.capability_instance_id,
      binding_set_id: timer_event.binding_set_id,
      activation_id: timer_event.activation_id,
      partition_affinity: timer_event.partition_affinity,
      partition_value: timer_event.partition_value,
      packet_id: timer_event.packet_id,
      evidence_id: timer_event.evidence_id,
      timer_key: timer_event.timer_key
    }
    |> compact()
  end

  defp managed_timer_payload(%ManagedTimerEvent{} = timer_event) do
    Map.merge(managed_timer_scope(timer_event), %{
      timer_event_id: timer_event.timer_event_id,
      family_key: timer_event.family_key,
      binding_set_version: timer_event.binding_set_version,
      event_kind: timer_event.event_kind,
      due_at: timer_event.due_at,
      occurred_at: timer_event.occurred_at,
      timer_metadata: timer_event.metadata
    })
  end

  defp replay_actor(replay_run_id) when is_binary(replay_run_id) and replay_run_id != "" do
    %{kind: :replay, id: replay_run_id}
  end

  defp replay_actor(_replay_run_id), do: %{kind: :system}

  defp maybe_put_replay_run_id(map, replay_run_id)
       when is_map(map) and is_binary(replay_run_id) and replay_run_id != "" do
    Map.put(map, :replay_run_id, replay_run_id)
  end

  defp maybe_put_replay_run_id(map, _replay_run_id), do: map
end
