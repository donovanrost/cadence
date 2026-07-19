defmodule Cadence.Dashboards.DataLinkResolver.TransportRuntimeTargets do
  @moduledoc """
  Resolves transport capability and action-request evidence targets.

  Public row formatters are shared by generic operational-event inspection.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(%DataLink{} = link, organization_id, mission_id) do
    {source_record_kind, rows_fun, missing_message} =
      case link.target do
        :transport_capability_record ->
          {"transport_capability_record", &capability_rows/1,
           "Transport capability record was not found in this mission."}

        :transport_action_request ->
          {"transport_action_request", &action_request_rows/1,
           "Transport action request was not found in this mission."}
      end

    case first_event(organization_id, mission_id, source_record_kind, link.target_id) do
      %OperationalEvent{} = event ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           rows_fun.(event),
           [related_link(link, :operational_event, event.event_id, "Operational event")]
         )}

      nil ->
        {:error, inspector(link, :missing, missing_message, [])}
    end
  end

  @spec capability_rows(OperationalEvent.t()) :: [map() | nil]
  def capability_rows(%OperationalEvent{} = event) do
    payload = event.payload || %{}

    [
      row("Transport capability record", state_value(payload, :transport_record_id)),
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
      row("Event kind", state_value(payload, :event_kind)),
      row("Timer", state_value(payload, :timer_key)),
      row("Emitted record kinds", state_value(payload, :emitted_record_kinds)),
      row("Emitted record count", state_value(payload, :emitted_record_count)),
      row("Action request count", state_value(payload, :action_request_count)),
      row("State snapshot", state_value(payload, :state_snapshot)),
      row("Record metadata", state_value(payload, :record_metadata)),
      row("Recorded", state_value(payload, :recorded_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  @spec action_request_rows(OperationalEvent.t()) :: [map() | nil]
  def action_request_rows(%OperationalEvent{} = event) do
    payload = event.payload || %{}

    [
      row("Transport action request", state_value(payload, :action_request_id)),
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
      row("Source endpoint", state_value(payload, :source_endpoint_ref)),
      row("Command release attempt", state_value(payload, :command_release_attempt_id)),
      row("Command request", state_value(payload, :command_request_id)),
      row("Command", state_value(payload, :command_name)),
      row("Signal phase", state_value(payload, :signal_phase)),
      row("Action kind", state_value(payload, :action_kind)),
      row("Request document", state_value(payload, :request_document)),
      row("Requested", state_value(payload, :requested_at)),
      row("Action metadata", state_value(payload, :action_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp first_event(organization_id, mission_id, source_record_kind, source_record_id) do
    organization_id
    |> OperationalEvents.list_events(
      mission_id,
      source_record_kind: source_record_kind,
      source_record_id: source_record_id,
      order: :asc,
      limit: 1
    )
    |> List.first()
  end
end
