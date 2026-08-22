defmodule Cadence.Dashboards.DataLinkResolver.CommandTargets do
  @moduledoc """
  Resolves command request, queue, release, and verifier data-link targets.

  The resolver owns mission-scoped persistence reads, inspector rows, and the
  related-link graph between command lifecycle records.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{DataLink, DataLinkInspector}
  alias Cadence.Reads.Commands, as: CommandReads
  alias Cadence.Reads.OperationalEvidence

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(
        %DataLink{target: :command_release_attempt} = link,
        organization_id,
        mission_id
      ) do
    case CommandReads.fetch_command_release_attempt(
           organization_id,
           mission_id,
           link.target_id
         ) do
      {:ok, release_attempt} ->
        transport_action_event =
          transport_action_event(release_attempt, organization_id, mission_id)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           release_attempt_rows(release_attempt, transport_action_event),
           release_attempt_related_links(
             link,
             release_attempt,
             organization_id,
             mission_id
           )
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Command release attempt was not found in this mission.",
           []
         )}
    end
  end

  def resolve(%DataLink{target: :command_queue_entry} = link, organization_id, mission_id) do
    case CommandReads.fetch_command_queue_entry(organization_id, mission_id, link.target_id) do
      {:ok, queue_entry} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           queue_entry_rows(queue_entry),
           queue_entry_related_links(link, queue_entry)
         )}

      {:error, _reason} ->
        {:error,
         inspector(link, :missing, "Command queue entry was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{target: :command_request} = link, organization_id, mission_id) do
    case CommandReads.fetch_command_request(organization_id, mission_id, link.target_id) do
      {:ok, request} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           request_rows(request),
           request_related_links(link, request, organization_id, mission_id)
         )}

      {:error, _reason} ->
        {:error, inspector(link, :missing, "Command request was not found in this mission.", [])}
    end
  end

  def resolve(
        %DataLink{target: :command_verifier_instance} = link,
        organization_id,
        mission_id
      ) do
    case CommandReads.fetch_command_verifier_instance(
           organization_id,
           mission_id,
           link.target_id
         ) do
      {:ok, verifier_instance} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           verifier_instance_rows(verifier_instance),
           verifier_instance_related_links(link, verifier_instance)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Command verifier instance was not found in this mission.",
           []
         )}
    end
  end

  defp queue_entry_rows(queue_entry) do
    [
      row("Command queue entry", queue_entry.command_queue_entry_id),
      row("Lifecycle state", queue_entry.lifecycle_state),
      row("Command request", queue_entry.command_request_id),
      row("Source endpoint", queue_entry.source_endpoint_ref),
      row("Queue lane", queue_entry.queue_lane_key),
      row("Priority", queue_entry.priority),
      row("Queue sequence", queue_entry.queue_sequence),
      row("Not before", queue_entry.not_before),
      row("Expires at", queue_entry.expires_at),
      row("Enqueued at", queue_entry.enqueued_at),
      row("Enqueued by", queue_entry.enqueued_by),
      row("Metadata", queue_entry.metadata)
    ]
  end

  defp queue_entry_related_links(%DataLink{} = link, queue_entry) do
    [
      related_link(
        link,
        :command_request,
        queue_entry.command_request_id,
        "Command request"
      )
    ]
  end

  defp request_rows(request) do
    [
      row("Command request", request.command_request_id),
      row("Lifecycle state", request.lifecycle_state),
      row("Verification state", request.verification_state),
      row("Source endpoint", request.source_endpoint_ref),
      row("Command", request.command_name),
      row("Command display name", request.command_display_name),
      row("Command id", request.command_id),
      row("Mission Model revision", request.mission_model_revision_id),
      row("Priority", request.priority),
      row("Not before", request.not_before),
      row("Expires at", request.expires_at),
      row("Requested at", request.requested_at),
      row("Requested by", request.requested_by),
      row("Source command stage", request.source_command_stage_id),
      row("Source staged command item", request.source_staged_command_item_id),
      row("Argument values", request.argument_values),
      row("Resolved argument values", request.resolved_argument_values),
      row("Significance", request.significance),
      row("Critical", request.critical),
      row("Hazardous", request.hazardous),
      row("Subsystem", request.subsystem),
      row("Group", request.group_name),
      row("Preferred uplink service", request.preferred_uplink_service),
      row("Release policy hint", request.release_policy_hint),
      row("APID", request.apid),
      row("Service type", request.service_type),
      row("Service subtype", request.service_subtype),
      row("Opcode", request.opcode),
      row("Metadata", request.metadata)
    ]
  end

  defp request_related_links(%DataLink{} = link, request, organization_id, mission_id) do
    queue_entry_links =
      organization_id
      |> CommandReads.list_command_queue_entries(
        mission_id,
        command_request_id: request.command_request_id
      )
      |> Enum.sort_by(&{&1.enqueued_at || DateTime.from_unix!(0), &1.command_queue_entry_id})
      |> Enum.map(fn queue_entry ->
        related_link(
          link,
          :command_queue_entry,
          queue_entry.command_queue_entry_id,
          "Command queue entry"
        )
      end)

    release_attempt_links =
      organization_id
      |> CommandReads.list_command_release_attempts(
        mission_id,
        command_request_id: request.command_request_id
      )
      |> Enum.map(fn release_attempt ->
        related_link(
          link,
          :command_release_attempt,
          release_attempt.command_release_attempt_id,
          "Command release attempt"
        )
      end)

    queue_entry_links ++ release_attempt_links
  end

  defp release_attempt_rows(release_attempt, transport_action_event) do
    transport_action_payload =
      case transport_action_event do
        nil -> %{}
        event -> event.payload || %{}
      end

    [
      row("Command release attempt", release_attempt.command_release_attempt_id),
      row("Lifecycle state", release_attempt.lifecycle_state),
      row("Verification state", release_attempt.verification_state),
      row("Failure reason", release_attempt.failure_reason),
      row("Command request", release_attempt.command_request_id),
      row("Command queue entry", release_attempt.command_queue_entry_id),
      row("Command", release_attempt.command_name),
      row("Command id", release_attempt.command_id),
      row("Mission Model revision", release_attempt.mission_model_revision_id),
      row("Source endpoint", release_attempt.source_endpoint_ref),
      row("Transport action request", state_value(transport_action_payload, :action_request_id)),
      row("Signal phase", state_value(transport_action_payload, :signal_phase)),
      row("Action kind", state_value(transport_action_payload, :action_kind)),
      row(
        "Transport operational event",
        transport_action_event && transport_action_event.event_id
      ),
      row("Realized contact", release_attempt.realized_contact_id),
      row("Path", release_attempt.path_id),
      row("Transport binding", release_attempt.transport_binding_id),
      row("Layout kind", release_attempt.layout_kind),
      row("Preferred uplink service", release_attempt.preferred_uplink_service),
      row("APID", release_attempt.apid),
      row("Service type", release_attempt.service_type),
      row("Service subtype", release_attempt.service_subtype),
      row("Opcode", release_attempt.opcode),
      row("Encoded size bytes", release_attempt.encoded_size_bytes),
      row("Attempted at", release_attempt.attempted_at),
      row("Released at", release_attempt.released_at),
      row("Released by", release_attempt.released_by),
      row("Metadata", release_attempt.metadata)
    ]
  end

  defp transport_action_event(release_attempt, organization_id, mission_id) do
    case state_value(release_attempt.metadata, :transport_action_request_id) do
      action_request_id when is_binary(action_request_id) and action_request_id != "" ->
        first_operational_event(
          organization_id,
          mission_id,
          "transport_action_request",
          action_request_id
        )

      _missing ->
        nil
    end
  end

  defp first_operational_event(
         organization_id,
         mission_id,
         source_record_kind,
         source_record_id
       ) do
    organization_id
    |> OperationalEvidence.list_operational_events(
      mission_id,
      source_record_kind: source_record_kind,
      source_record_id: source_record_id,
      order: :asc,
      limit: 1
    )
    |> List.first()
  end

  defp release_attempt_related_links(
         %DataLink{} = link,
         release_attempt,
         organization_id,
         mission_id
       ) do
    verifier_links =
      organization_id
      |> CommandReads.list_command_verifier_instances(
        mission_id,
        command_release_attempt_id: release_attempt.command_release_attempt_id
      )
      |> Enum.sort_by(&{&1.matched_at || DateTime.from_unix!(0), &1.command_verifier_instance_id})
      |> Enum.map(fn verifier_instance ->
        related_link(
          link,
          :command_verifier_instance,
          verifier_instance.command_verifier_instance_id,
          "Command verifier instance"
        )
      end)

    [
      related_link(
        link,
        :command_request,
        release_attempt.command_request_id,
        "Command request"
      ),
      related_link(
        link,
        :command_queue_entry,
        release_attempt.command_queue_entry_id,
        "Command queue entry"
      ),
      related_link(
        link,
        :source_endpoint,
        release_attempt.source_endpoint_ref,
        "Source endpoint"
      ),
      related_link(
        link,
        :contact,
        release_attempt.realized_contact_id,
        "Contact"
      ),
      related_link(
        link,
        :transport_action_request,
        state_value(release_attempt.metadata, :transport_action_request_id),
        "Transport action request"
      )
      | verifier_links
    ]
  end

  defp verifier_instance_rows(verifier_instance) do
    [
      row("Command verifier instance", verifier_instance.command_verifier_instance_id),
      row("Verifier", verifier_instance.verifier_id),
      row("Verifier name", verifier_instance.verifier_name),
      row("Lifecycle state", verifier_instance.lifecycle_state),
      row("Severity", verifier_instance.severity),
      row("Phase", verifier_instance.phase),
      row("Command release attempt", verifier_instance.command_release_attempt_id),
      row("Command request", verifier_instance.command_request_id),
      row("Command", verifier_instance.command_name),
      row("Command id", verifier_instance.command_id),
      row("Mission Model revision", verifier_instance.mission_model_revision_id),
      row("Source endpoint", verifier_instance.source_endpoint_ref),
      row("Matched record kind", verifier_instance.matched_record_kind),
      row("Matched record", verifier_instance.matched_record_id),
      row("Matched at", verifier_instance.matched_at),
      row("Failure reason", verifier_instance.failure_reason),
      row("Delay until", verifier_instance.delay_until),
      row("Timeout at", verifier_instance.timeout_at),
      row("Success criteria", verifier_instance.success_criteria),
      row("Failure criteria", verifier_instance.failure_criteria),
      row("Metadata", verifier_instance.metadata)
    ]
  end

  defp verifier_instance_related_links(%DataLink{} = link, verifier_instance) do
    [
      related_link(
        link,
        :command_release_attempt,
        verifier_instance.command_release_attempt_id,
        "Command release attempt"
      ),
      related_link(
        link,
        :command_request,
        verifier_instance.command_request_id,
        "Command request"
      ),
      matched_record_related_link(
        link,
        verifier_instance.matched_record_kind,
        verifier_instance.matched_record_id
      )
    ]
  end

  defp matched_record_related_link(%DataLink{} = link, matched_record_kind, matched_record_id) do
    with target when is_atom(target) <- DataLink.parse_resolvable_target(matched_record_kind),
         id when is_binary(id) and id != "" <- string_id(matched_record_id) do
      related_link(link, target, id, target_text(target))
    else
      _missing -> nil
    end
  end
end
