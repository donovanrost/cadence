defmodule Cadence.Dashboards.DataLinkResolver.SourceStateTargets do
  @moduledoc """
  Resolves source-state events and effective operational intervals.

  The module owns source health, watermark, and binding-event reads together
  with interval lookup, inspector rows, and related evidence links.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.DataSources.DataBindingInterval
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Reads.DataSources
  alias Cadence.Reads.OperationalEvidence

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(
        %DataLink{target: :source_binding_interval} = link,
        organization_id,
        mission_id
      ) do
    case find_effective_interval(link, organization_id, mission_id) do
      %EffectiveInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           effective_interval_rows(interval),
           effective_interval_related_links(link, interval)
         )}

      nil ->
        resolve_source_binding_data_interval(link, organization_id, mission_id)
    end
  end

  def resolve(%DataLink{target: :source_health_event} = link, organization_id, mission_id) do
    case DataSources.fetch_source_health_event(organization_id, mission_id, link.target_id) do
      {:ok, event} ->
        {:ok, inspector(link, :resolved, nil, source_health_event_rows(event))}

      {:error, _reason} ->
        {:error,
         inspector(link, :missing, "Source health event was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{target: :source_watermark_event} = link, organization_id, mission_id) do
    case DataSources.fetch_source_watermark_event(organization_id, mission_id, link.target_id) do
      {:ok, event} ->
        {:ok, inspector(link, :resolved, nil, source_watermark_event_rows(event))}

      {:error, _reason} ->
        {:error,
         inspector(link, :missing, "Source watermark event was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{target: :source_binding_event} = link, organization_id, mission_id) do
    case DataSources.fetch_data_binding_event(organization_id, mission_id, link.target_id) do
      {:ok, event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_binding_event_rows(event),
           source_binding_event_related_links(link, event)
         )}

      {:error, _reason} ->
        {:error,
         inspector(link, :missing, "Source binding event was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{} = link, organization_id, mission_id) do
    case find_effective_interval(link, organization_id, mission_id) do
      %EffectiveInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           effective_interval_rows(interval),
           effective_interval_related_links(link, interval)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Operational interval was not found in this mission.", [])}
    end
  end

  defp resolve_source_binding_data_interval(
         %DataLink{} = link,
         organization_id,
         mission_id
       ) do
    case find_source_binding_data_interval(link.target_id, organization_id, mission_id) do
      %DataBindingInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_binding_data_interval_rows(link.target_id, interval),
           source_binding_data_interval_related_links(link, interval)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Source binding interval was not found in this mission.", [])}
    end
  end

  defp source_health_event_rows(event) do
    [
      row("Source health event", event.source_health_event_id),
      row("Observed", event.observed_at),
      row("Logical source", event.logical_source),
      row("Data source", event.data_source_id),
      row("Source binding", event.source_binding_id),
      row("Realm", event.realm),
      row("Dataset", event.dataset),
      row("Replay run", event.replay_run_id),
      row("Event type", event.event_type),
      row("Source health", event.source_health),
      row("Previous source health", event.previous_source_health),
      row("Reason", event.reason),
      row("Payload", event.payload)
    ]
  end

  defp source_watermark_event_rows(event) do
    [
      row("Source watermark event", event.source_watermark_event_id),
      row("Source watermark key", event.source_watermark_key),
      row("Observed", event.observed_at),
      row("Logical source", event.logical_source),
      row("Data source", event.data_source_id),
      row("Source binding", event.source_binding_id),
      row("Realm", event.realm),
      row("Dataset", event.dataset),
      row("Replay run", event.replay_run_id),
      row("Event type", event.event_type),
      row("Complete through", event.complete_through),
      row("Previous complete through", event.previous_complete_through),
      row("Latest receipt time", event.latest_receipt_time),
      row("Previous latest receipt time", event.previous_latest_receipt_time),
      row("Retention starts at", event.retention_starts_at),
      row("Previous retention starts at", event.previous_retention_starts_at),
      row("Sample count", event.sample_count),
      row("Confidence", event.confidence),
      row("Reason", event.reason),
      row("Payload", event.payload)
    ]
  end

  defp source_binding_event_rows(event) do
    [
      row("Source binding event", event.data_binding_event_id),
      row("Binding", event.binding_id),
      row("Event type", event.event_type),
      row("Previous status", event.previous_status),
      row("Current status", event.current_status),
      row("Previous binding version", event.previous_binding_version),
      row("Current binding version", event.current_binding_version),
      row("Previous logical source", event.previous_logical_source),
      row("Current logical source", event.current_logical_source),
      row("Previous realm", event.previous_realm),
      row("Current realm", event.current_realm),
      row("Previous data source", event.previous_data_source_id),
      row("Current data source", event.current_data_source_id),
      row("Previous dataset", event.previous_dataset),
      row("Current dataset", event.current_dataset),
      row("Previous priority", event.previous_priority),
      row("Current priority", event.current_priority),
      row("Previous active from", event.previous_active_from),
      row("Current active from", event.current_active_from),
      row("Previous active to", event.previous_active_to),
      row("Current active to", event.current_active_to),
      row("Actor", event.actor_id),
      row("Occurred", event.occurred_at),
      row("Payload", event.payload)
    ]
  end

  defp effective_interval_rows(%EffectiveInterval{} = interval) do
    [
      row("Operational interval", interval.interval_id),
      row("Kind", interval.kind),
      row("Subject kind", interval.subject_kind),
      row("Subject", interval.subject_id),
      row("Starts", interval.starts_at),
      row("Ends", interval.ends_at),
      row("Source event", interval.source_event_id),
      row("Superseded by event", interval.superseded_by_event_id),
      row("Payload", interval.payload),
      row("Metadata", interval.metadata)
    ]
  end

  defp source_binding_data_interval_rows(interval_id, %DataBindingInterval{} = interval) do
    [
      row("Source binding interval", interval_id),
      row("Binding", interval.binding_id),
      row("Data binding event", interval.data_binding_event_id),
      row("Event type", interval.event_type),
      row("Status", interval.status),
      row("Binding version", interval.binding_version),
      row("Logical source", interval.logical_source),
      row("Realm", interval.realm),
      row("Data source", interval.data_source_id),
      row("Dataset", interval.dataset),
      row("Priority", interval.priority),
      row("Started", interval.started_at),
      row("Ended", interval.ended_at),
      row("Active from", interval.active_from),
      row("Active to", interval.active_to)
    ]
  end

  defp find_effective_interval(%DataLink{} = link, organization_id, mission_id) do
    link.target
    |> effective_intervals(organization_id, mission_id, effective_interval_opts(link))
    |> Enum.find(&(&1.interval_id == link.target_id))
  end

  defp effective_interval_opts(%DataLink{} = link) do
    opts = [event_limit: 1_000]

    case replay_run_id(link.context) do
      replay_run_id when is_binary(replay_run_id) and replay_run_id != "" ->
        Keyword.put(opts, :replay_run_id, replay_run_id)

      _other ->
        opts
    end
  end

  defp effective_intervals(:binding_set_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :binding_set,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(:application_binding_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :application_binding,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(:catalog_revision_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :catalog_revision,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(:source_binding_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :source_binding,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(:source_health_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :source_health,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(:transport_execution_interval, organization_id, mission_id, opts),
    do:
      OperationalEvidence.list_effective_intervals(
        :transport_execution,
        organization_id,
        mission_id,
        opts
      )

  defp effective_intervals(target, organization_id, mission_id, opts)
       when target in [
              :transport_connection_state_interval,
              :ground_station_connection_state_interval
            ],
       do:
         OperationalEvidence.list_effective_intervals(
           :connection_state,
           organization_id,
           mission_id,
           opts
         )

  defp effective_intervals(
         :ground_station_antenna_pointing_state_interval,
         organization_id,
         mission_id,
         opts
       ) do
    opts = Keyword.put(opts, :observable_id, ["ground.station.antenna_pointing_state"])

    OperationalEvidence.list_effective_intervals(
      :operational_observable_state,
      organization_id,
      mission_id,
      opts
    )
  end

  defp effective_intervals(target, organization_id, mission_id, opts)
       when target in [:link_rf_lock_state_interval, :link_frame_sync_state_interval],
       do:
         OperationalEvidence.list_effective_intervals(
           :link_rf_state,
           organization_id,
           mission_id,
           opts
         )

  defp effective_intervals(_target, _organization_id, _mission_id, _opts), do: []

  defp find_source_binding_data_interval(target_id, organization_id, mission_id) do
    DataSources.list_data_binding_intervals(organization_id, mission_id)
    |> Enum.find(&(source_binding_data_interval_id(&1) == target_id))
  end

  defp source_binding_data_interval_id(%DataBindingInterval{} = interval) do
    "effective_interval:source_binding:#{interval.data_binding_event_id}"
  end

  defp source_binding_event_related_links(%DataLink{} = link, event) do
    [
      related_link(
        link,
        :operational_event,
        "operational_event:data_source_binding_event:#{event.data_binding_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp effective_interval_related_links(%DataLink{} = link, %EffectiveInterval{} = interval) do
    [
      related_link(
        link,
        :operational_event,
        interval.source_event_id,
        "Source event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        interval.superseded_by_event_id,
        "Superseding event",
        :follow_up_event
      )
      | effective_interval_resource_links(link, interval)
    ]
  end

  defp effective_interval_resource_links(
         %DataLink{} = link,
         %EffectiveInterval{kind: :application_binding, payload: payload}
       ) do
    [
      related_link(
        link,
        :source_endpoint,
        context_value(payload, :source_endpoint_ref),
        "Source endpoint"
      )
    ]
  end

  defp effective_interval_resource_links(
         %DataLink{} = link,
         %EffectiveInterval{kind: :transport_execution, payload: payload}
       ) do
    [
      related_link(
        link,
        :transport,
        context_value(payload, :capability_instance_id),
        "Transport"
      ),
      related_link(
        link,
        :contact,
        context_value(payload, :realized_contact_id) || context_value(payload, :contact_id),
        "Contact"
      )
    ]
  end

  defp effective_interval_resource_links(_link, _interval), do: []

  defp source_binding_data_interval_related_links(
         %DataLink{} = link,
         %DataBindingInterval{} = interval
       ) do
    [
      related_link(
        link,
        :source_binding_event,
        interval.data_binding_event_id,
        "Source binding event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        "operational_event:data_source_binding_event:#{interval.data_binding_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end
end
