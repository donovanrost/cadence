defmodule Cadence.Dashboards.DataLinkResolver.LimitTargets do
  @moduledoc """
  Resolves limit events, definitions, lifecycle events, and effective intervals.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.Limits
  alias Cadence.Limits.{DefinitionInterval, DefinitionLifecycle}

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(%DataLink{target: :limit_event} = link, organization_id, mission_id) do
    case Limits.fetch_limit_event(organization_id, mission_id, link.target_id) do
      {:ok, event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           limit_event_rows(event),
           limit_event_related_links(link, event)
         )}

      {:error, :limit_event_not_found} ->
        {:error, inspector(link, :missing, "Limit event was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{target: :limit_definition} = link, organization_id, mission_id) do
    case Limits.fetch_latest_limit_definition(organization_id, mission_id, link.target_id) do
      {:ok, definition} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           limit_definition_rows(definition),
           limit_definition_related_links(link, definition)
         )}

      {:error, :limit_definition_not_found} ->
        {:error, inspector(link, :missing, "Limit definition was not found in this mission.", [])}
    end
  end

  def resolve(
        %DataLink{target: :limit_definition_interval} = link,
        organization_id,
        mission_id
      ) do
    with activation_key when is_binary(activation_key) <-
           interval_activation_key(link.target_id),
         {:ok, event} <-
           DefinitionLifecycle.fetch_latest_definition_lifecycle_event(
             organization_id,
             mission_id,
             activation_key,
             include_unscoped?: true
           ) do
      definition = fetch_definition_for_interval(event, organization_id, mission_id)
      interval = DefinitionInterval.from_event(event, event.active_to, definition)

      {:ok,
       inspector(
         link,
         :resolved,
         nil,
         interval_rows(link.target_id, interval),
         interval_related_links(link, interval)
       )}
    else
      _missing ->
        {:error,
         inspector(link, :missing, "Limit definition interval was not found in this mission.", [])}
    end
  end

  def resolve(
        %DataLink{target: :limit_definition_lifecycle_event} = link,
        organization_id,
        mission_id
      ) do
    case DefinitionLifecycle.fetch_definition_lifecycle_event(
           organization_id,
           mission_id,
           link.target_id,
           include_unscoped?: true
         ) do
      {:ok, event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           lifecycle_event_rows(event),
           lifecycle_event_related_links(link, event)
         )}

      {:error, :limit_definition_lifecycle_event_not_found} ->
        {:error,
         inspector(
           link,
           :missing,
           "Limit definition lifecycle event was not found in this mission.",
           []
         )}
    end
  end

  defp limit_event_rows(event) do
    [
      row("Limit event", event.limit_event_id),
      row("Point", event.point_id),
      row("Spacecraft", event.spacecraft_id),
      row("Sample", event.sample_id),
      row("Definition", event.limit_definition_id),
      row("Definition version", event.limit_definition_version),
      row("Limit set", event.limit_set_name),
      row("Evaluated", event.evaluated_value),
      row("Limit state", event.limit_state),
      row("Normalized state", event.normalized_state),
      row("Violation", event.violation),
      row("Generation", event.generation_time),
      row("Receipt", event.receipt_time)
    ]
  end

  defp limit_definition_rows(definition) do
    [
      row("Definition", definition.limit_definition_id),
      row("Point", definition.point_id),
      row("Version", definition.version),
      row("Limit set", definition.limit_set_name),
      row("Thresholds", definition.thresholds),
      row("Metadata", definition.metadata)
    ]
  end

  defp lifecycle_event_rows(event) do
    [
      row("Limit definition lifecycle event", event.limit_definition_lifecycle_event_id),
      row("Definition activation", event.definition_activation_key),
      row("Point", event.point_id),
      row("Limit set", event.limit_set_name),
      row("Scope type", event.scope_type),
      row("Scope ref", event.scope_ref),
      row("Realm", event.realm),
      row("Event type", event.event_type),
      row("Limit definition", event.limit_definition_id),
      row("Limit definition version", event.limit_definition_version),
      row("Previous limit definition", event.previous_limit_definition_id),
      row("Previous limit definition version", event.previous_limit_definition_version),
      row("Active from", event.active_from),
      row("Active to", event.active_to),
      row("Reason", event.reason),
      row("Observed", event.observed_at),
      row("Payload", event.payload)
    ]
  end

  defp interval_rows(interval_id, %DefinitionInterval{} = interval) do
    [
      row("Limit definition interval", interval_id),
      row("Definition activation", interval.definition_activation_key),
      row("Lifecycle event", interval.limit_definition_lifecycle_event_id),
      row("Point", interval.point_id),
      row("Limit set", interval.limit_set_name),
      row("Scope type", interval.scope_type),
      row("Scope ref", interval.scope_ref),
      row("Realm", interval.realm),
      row("Event type", interval.event_type),
      row("Limit definition", interval.limit_definition_id),
      row("Limit definition version", interval.limit_definition_version),
      row("Previous limit definition", interval.previous_limit_definition_id),
      row("Previous limit definition version", interval.previous_limit_definition_version),
      row("Active from", interval.active_from),
      row("Active to", interval.active_to),
      row("Observed", interval.observed_at),
      row("Complete", interval.complete?),
      row("Thresholds", interval.thresholds),
      row("Metadata", interval.metadata)
    ]
  end

  defp limit_event_related_links(%DataLink{} = link, event) do
    [
      related_link(link, :telemetry_point, event.point_id, "Telemetry point"),
      limit_event_sample_link(link, event),
      related_link(link, :limit_definition, event.limit_definition_id, "Limit definition")
    ]
  end

  defp limit_event_sample_link(
         %DataLink{} = link,
         %{source_sample_type: :telemetry_sample} = event
       ) do
    related_link(link, :telemetry_sample, event.sample_id, "Telemetry sample")
  end

  defp limit_event_sample_link(_link, _event), do: nil

  defp limit_definition_related_links(%DataLink{} = link, definition) do
    [
      related_link(link, :telemetry_point, definition.point_id, "Telemetry point")
    ]
  end

  defp lifecycle_event_related_links(%DataLink{} = link, event) do
    [
      related_link(link, :telemetry_point, event.point_id, "Telemetry point"),
      related_link(link, :limit_definition, event.limit_definition_id, "Limit definition"),
      related_link(
        link,
        :operational_event,
        "operational_event:limit_definition_lifecycle_event:#{event.limit_definition_lifecycle_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp interval_related_links(%DataLink{} = link, %DefinitionInterval{} = interval) do
    [
      related_link(link, :telemetry_point, interval.point_id, "Telemetry point"),
      related_link(link, :limit_definition, interval.limit_definition_id, "Limit definition"),
      related_link(
        link,
        :limit_definition_lifecycle_event,
        interval.limit_definition_lifecycle_event_id,
        "Limit definition lifecycle event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        "operational_event:limit_definition_lifecycle_event:#{interval.limit_definition_lifecycle_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp interval_activation_key(target_id) do
    case string_id(target_id) do
      "effective_interval:limit_definition:" <> activation_key -> activation_key
      activation_key -> activation_key
    end
  end

  defp fetch_definition_for_interval(event, organization_id, mission_id) do
    case Limits.fetch_limit_definition(
           organization_id,
           mission_id,
           event.limit_definition_id,
           event.limit_definition_version,
           include_unscoped?: true
         ) do
      {:ok, definition} -> definition
      {:error, :limit_definition_not_found} -> nil
    end
  end
end
