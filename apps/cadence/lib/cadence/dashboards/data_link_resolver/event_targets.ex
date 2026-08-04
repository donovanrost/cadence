defmodule Cadence.Dashboards.DataLinkResolver.EventTargets do
  @moduledoc """
  Resolves mission and operational events into inspector payloads.

  Mission-event fallback projection stays beside operational-event semantic
  rows so persisted and projected event inspection share one boundary.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.Dashboards.DataLinkResolver.TransportRuntimeTargets
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias Cadence.Reads.OperationalEvidence

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(%DataLink{target: :mission_event} = link, organization_id, mission_id) do
    case MissionEventReads.fetch_for_mission(organization_id, mission_id, link.target_id) do
      {:ok, event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           mission_event_rows(event),
           mission_event_related_links(link, event)
         )}

      {:error, :mission_event_not_found} ->
        resolve_projected_mission_event(link, organization_id, mission_id)
    end
  end

  def resolve(%DataLink{target: :operational_event} = link, organization_id, mission_id) do
    case OperationalEvidence.fetch_operational_event(organization_id, mission_id, link.target_id) do
      {:ok, %OperationalEvent{} = event} ->
        {:ok, inspector(link, :resolved, nil, operational_event_rows(event))}

      {:error, :not_found} ->
        {:error,
         inspector(link, :missing, "Operational event was not found in this mission.", [])}
    end
  end

  defp resolve_projected_mission_event(
         %DataLink{target_id: "mission_event:" <> operational_event_id} = link,
         organization_id,
         mission_id
       ) do
    case OperationalEvidence.fetch_operational_event(
           organization_id,
           mission_id,
           operational_event_id
         ) do
      {:ok, %OperationalEvent{} = event} ->
        event
        |> MissionEventProjection.project()
        |> Enum.find(&(&1.mission_event_id == link.target_id))
        |> case do
          nil ->
            missing_mission_event(link)

          projected_event ->
            {:ok,
             inspector(
               link,
               :resolved,
               nil,
               mission_event_rows(projected_event),
               mission_event_related_links(link, projected_event)
             )}
        end

      {:error, :not_found} ->
        missing_mission_event(link)
    end
  end

  defp resolve_projected_mission_event(%DataLink{} = link, _organization_id, _mission_id),
    do: missing_mission_event(link)

  defp missing_mission_event(%DataLink{} = link) do
    {:error, inspector(link, :missing, "Mission event was not found in this mission.", [])}
  end

  defp mission_event_rows(event) do
    [
      row("Mission event", event.mission_event_id),
      row("Occurred", event.occurred_at),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Status", event.status),
      row("Title", event.title),
      row("Summary", event.summary),
      row("Source record kind", event.source_record_kind),
      row("Source record", event.source_record_id),
      row("Subject kind", event.subject_kind),
      row("Subject", event.subject_id),
      row("Spacecraft", event.spacecraft_id),
      row("Source endpoint", event.source_endpoint_ref),
      row("Scheduled contact", event.scheduled_contact_id),
      row("Realized contact", event.realized_contact_id),
      row("Path", event.path_id),
      row("Capability instance", event.capability_instance_id),
      row("Activation", event.activation_id),
      row("Correlation", event.correlation_key),
      row("Actor", event.actor),
      row("Metadata", event.metadata)
    ]
  end

  defp operational_event_rows(event) do
    base_rows = [
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Recorded", event.recorded_at),
      row("Effective", event.effective_at),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Organization", event.organization_id),
      row("Mission", event.mission_id),
      row("Actor", event.actor),
      row("Subject", event.subject),
      row("Scope", event.scope),
      row("Causality", event.causality),
      row("Payload", event.payload),
      row("Current", event.current),
      row("Metadata", event.metadata)
    ]

    base_rows ++ operational_event_semantic_rows(event)
  end

  defp operational_event_semantic_rows(%{causality: causality} = event) do
    causality
    |> state_value(:source_record_kind)
    |> operational_event_semantic_rows_for(event)
  end

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_action_request, "transport_action_request"],
       do: TransportRuntimeTargets.action_request_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_capability_record, "transport_capability_record"],
       do: TransportRuntimeTargets.capability_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_timer_event, "transport_timer_event"],
       do: transport_timer_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_timer_event, "managed_timer_event"],
       do: managed_timer_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_action_request, "managed_action_request"],
       do: managed_action_request_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_capability_record, "managed_capability_record"],
       do: managed_capability_record_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:source_capability_posture, "source_capability_posture"],
       do: source_capability_posture_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:source_health_event, "source_health_event"],
       do: source_health_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:connection_state_snapshot, "connection_state_snapshot"],
       do: connection_state_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [
              :link_rf_lock_state_snapshot,
              "link_rf_lock_state_snapshot",
              :link_frame_sync_state_snapshot,
              "link_frame_sync_state_snapshot"
            ],
       do: link_rf_state_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:operational_observable_snapshot, "operational_observable_snapshot"],
       do: operational_observable_snapshot_operational_event_rows(event)

  defp operational_event_semantic_rows_for(_kind, _event), do: []

  defp operational_observable_snapshot_operational_event_rows(event) do
    case event.kind do
      kind
      when kind in [
             :operational_observable_metric_sampled,
             "operational_observable_metric_sampled"
           ] ->
        operational_observable_metric_operational_event_rows(event)

      _other ->
        operational_observable_state_operational_event_rows(event)
    end
  end

  defp operational_observable_metric_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Operational metric sample", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("Value", operational_metric_value(current, payload)),
      row("Unit", state_value(payload, :unit)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp operational_metric_value(current, payload) do
    [
      :value,
      :downlink_bitrate,
      :downlink_bitrate_bps,
      :uplink_bitrate,
      :uplink_bitrate_bps,
      :bitrate,
      :snr_db,
      :snr,
      :signal_to_noise_ratio_db,
      :eb_n0_db,
      :ebn0_db,
      :energy_per_bit_to_noise_density_db,
      :symbol_rate_sps,
      :symbol_rate,
      :symbols_per_second,
      :doppler_hz,
      :doppler,
      :frequency_offset_hz,
      :carrier_frequency_offset_hz
    ]
    |> Enum.find_value(fn field ->
      state_value(current, field) || state_value(payload, field)
    end)
  end

  defp operational_observable_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Operational observable snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("State", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp link_rf_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("RF state snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("RF state", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp connection_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Connection state snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Spacecraft", state_value(payload, :spacecraft_id)),
      row("Contact", state_value(payload, :contact_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("Adapter", state_value(payload, :adapter_key)),
      row(
        "Connection state",
        state_value(current, :connection_state) || state_value(payload, :connection_state)
      ),
      row(
        "Normalized state",
        state_value(current, :normalized_state) || state_value(payload, :normalized_state)
      ),
      row("State", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp source_health_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}

    [
      row("Source health event", state_value(payload, :source_health_event_id)),
      row("Observed", event.occurred_at),
      row("Logical source", state_value(payload, :logical_source)),
      row("Data source", state_value(payload, :data_source_id)),
      row("Source binding", state_value(payload, :source_binding_id)),
      row("Realm", state_value(payload, :data_realm)),
      row("Dataset", state_value(payload, :dataset)),
      row("Replay run", state_value(payload, :replay_run_id)),
      row("Event type", state_value(payload, :event_type)),
      row(
        "Source health",
        state_value(current, :source_health) || state_value(payload, :source_health)
      ),
      row("Previous source health", state_value(payload, :previous_source_health)),
      row("Reason", state_value(current, :reason) || state_value(payload, :reason)),
      row("Source payload", state_value(payload, :source_payload))
    ]
  end

  defp source_capability_posture_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}

    [
      row("Source capability posture", state_value(payload, :source_capability_posture_id)),
      row("Dashboard", state_value(payload, :dashboard_id)),
      row("Dashboard version", state_value(payload, :dashboard_version)),
      row("Resolve", state_value(payload, :resolve_id)),
      row("Source request", state_value(payload, :source_request_id)),
      row("Logical source", state_value(payload, :logical_source)),
      row("Data source", state_value(payload, :data_source_id)),
      row("Source binding", state_value(payload, :source_binding_id)),
      row("Realm", state_value(payload, :realm)),
      row("Dataset", state_value(payload, :dataset)),
      row("Replay run", state_value(payload, :replay_run_id)),
      row(
        "Capability status",
        state_value(current, :capability_status) || state_value(payload, :status)
      ),
      row("Requested sampling", state_value(payload, :requested_sampling)),
      row("Supported sampling", state_value(payload, :supported_sampling)),
      row("Requested products", state_value(payload, :requested_products)),
      row("Supported products", state_value(payload, :supported_products)),
      row("Requested time axis", state_value(payload, :requested_time_axis)),
      row("Executed time axis", state_value(payload, :executed_time_axis)),
      row("Supported time axes", state_value(payload, :supported_time_axes)),
      row("Fallbacks", state_value(payload, :fallbacks)),
      row("Unsupported", state_value(payload, :unsupported)),
      row("Source execution status", state_value(payload, :source_execution_status)),
      row("Source execution cache status", state_value(payload, :source_execution_cache_status)),
      row(
        "Source execution operator action",
        state_value(payload, :source_execution_operator_action)
      ),
      row(
        "Source execution runtime action",
        state_value(payload, :source_execution_runtime_action)
      ),
      row("Source execution warnings", state_value(payload, :source_execution_warning_codes))
    ]
  end

  defp transport_timer_event_rows(event) do
    payload = event.payload || %{}

    [
      row("Transport timer event", state_value(payload, :timer_event_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Contact", state_value(payload, :contact_id)),
      row("Path", state_value(payload, :path_id)),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Due", state_value(payload, :due_at)),
      row("Timer metadata", state_value(payload, :timer_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_timer_event_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed timer event", state_value(payload, :timer_event_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Due", state_value(payload, :due_at)),
      row("Timer metadata", state_value(payload, :timer_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_action_request_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed action request", state_value(payload, :action_request_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Action kind", state_value(payload, :action_kind)),
      row("Request document", state_value(payload, :request_document)),
      row("Requested", state_value(payload, :requested_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_capability_record_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed capability record", state_value(payload, :capability_record_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Emitted record kinds", state_value(payload, :emitted_record_kinds)),
      row("Emitted record count", state_value(payload, :emitted_record_count)),
      row("Action request count", state_value(payload, :action_request_count)),
      row("State snapshot", state_value(payload, :state_snapshot)),
      row("Record metadata", state_value(payload, :record_metadata)),
      row("Recorded", state_value(payload, :recorded_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp mission_event_related_links(%DataLink{} = link, event) do
    [
      mission_event_source_link(link, event),
      mission_event_subject_link(link, event),
      contact_related_link(link, event.scheduled_contact_id, event.realized_contact_id)
    ]
  end

  defp mission_event_source_link(
         %DataLink{} = link,
         %{source_record_kind: :limit_event, source_record_id: source_record_id}
       ) do
    related_link(link, :limit_event, source_record_id, "Limit event")
  end

  defp mission_event_source_link(
         %DataLink{} = link,
         %{source_record_kind: :operational_event, source_record_id: source_record_id}
       ) do
    related_link(link, :operational_event, source_record_id, "Operational event", :source_event)
  end

  defp mission_event_source_link(_link, _event), do: nil

  defp mission_event_subject_link(
         %DataLink{} = link,
         %{subject_kind: :telemetry_point, subject_id: subject_id}
       ) do
    related_link(link, :telemetry_point, subject_id, "Telemetry point")
  end

  defp mission_event_subject_link(_link, _event), do: nil

  defp contact_related_link(%DataLink{} = link, scheduled_contact_id, realized_contact_id) do
    related_link(link, :contact, realized_contact_id || scheduled_contact_id, "Contact")
  end
end
