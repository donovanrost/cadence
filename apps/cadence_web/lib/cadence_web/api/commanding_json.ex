defmodule CadenceWeb.API.CommandingJSON do
  @moduledoc "Commanding response serialization boundary."

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage,
    CommandVerifierInstance,
    StagedCommandItem
  }

  alias Cadence.Persistence.JsonDocument

  def command_stage(%CommandStage{} = stage) do
    %{
      command_stage_id: stage.command_stage_id,
      organization_id: stage.organization_id,
      mission_id: stage.mission_id,
      stage_name: stage.stage_name,
      description: stage.description,
      owner: stage.owner,
      visibility: Atom.to_string(stage.visibility),
      lifecycle_state: Atom.to_string(stage.lifecycle_state),
      metadata: stage.metadata
    }
  end

  def staged_command_item(%StagedCommandItem{} = item) do
    %{
      staged_command_item_id: item.staged_command_item_id,
      organization_id: item.organization_id,
      mission_id: item.mission_id,
      command_stage_id: item.command_stage_id,
      source_endpoint_ref: item.source_endpoint_ref,
      mission_model_revision_id: item.mission_model_revision_id,
      command_id: item.command_id,
      argument_values: JsonDocument.encode(item.argument_values),
      priority: item.priority,
      not_before: iso8601(item.not_before),
      expires_at: iso8601(item.expires_at),
      notes: item.notes,
      item_order: item.item_order,
      lifecycle_state: Atom.to_string(item.lifecycle_state),
      submitted_command_request_id: item.submitted_command_request_id,
      metadata: JsonDocument.encode(item.metadata)
    }
  end

  def command_request(%CommandRequest{} = request) do
    %{
      command_request_id: request.command_request_id,
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      source_endpoint_ref: request.source_endpoint_ref,
      mission_model_revision_id: request.mission_model_revision_id,
      command_id: request.command_id,
      command_name: request.command_name,
      command_display_name: request.command_display_name,
      lifecycle_state: Atom.to_string(request.lifecycle_state),
      verification_state: maybe_atom_to_string(request.verification_state),
      priority: request.priority,
      not_before: iso8601(request.not_before),
      expires_at: iso8601(request.expires_at),
      requested_by: JsonDocument.encode(request.requested_by),
      source_command_stage_id: request.source_command_stage_id,
      source_staged_command_item_id: request.source_staged_command_item_id,
      argument_values: JsonDocument.encode(request.argument_values),
      resolved_argument_values: JsonDocument.encode(request.resolved_argument_values),
      significance: maybe_atom_to_string(request.significance),
      critical: request.critical,
      hazardous: request.hazardous,
      subsystem: request.subsystem,
      group_name: request.group_name,
      preferred_uplink_service: request.preferred_uplink_service,
      release_policy_hint: request.release_policy_hint,
      apid: request.apid,
      service_type: request.service_type,
      service_subtype: request.service_subtype,
      opcode: JsonDocument.encode(request.opcode),
      requested_at: iso8601(request.requested_at),
      metadata: JsonDocument.encode(request.metadata)
    }
  end

  def command_approval(%CommandApproval{} = approval) do
    %{
      command_approval_id: approval.command_approval_id,
      organization_id: approval.organization_id,
      mission_id: approval.mission_id,
      command_request_id: approval.command_request_id,
      decision: Atom.to_string(approval.decision),
      decided_by: JsonDocument.encode(approval.decided_by),
      decided_at: iso8601(approval.decided_at),
      reason: approval.reason,
      metadata: JsonDocument.encode(approval.metadata)
    }
  end

  def command_queue_entry(%CommandQueueEntry{} = entry) do
    %{
      command_queue_entry_id: entry.command_queue_entry_id,
      organization_id: entry.organization_id,
      mission_id: entry.mission_id,
      command_request_id: entry.command_request_id,
      source_endpoint_ref: entry.source_endpoint_ref,
      queue_lane_key: entry.queue_lane_key,
      priority: entry.priority,
      queue_sequence: entry.queue_sequence,
      not_before: iso8601(entry.not_before),
      expires_at: iso8601(entry.expires_at),
      lifecycle_state: Atom.to_string(entry.lifecycle_state),
      enqueued_by: JsonDocument.encode(entry.enqueued_by),
      enqueued_at: iso8601(entry.enqueued_at),
      metadata: JsonDocument.encode(entry.metadata)
    }
  end

  def command_release_attempt(%CommandReleaseAttempt{} = attempt) do
    %{
      command_release_attempt_id: attempt.command_release_attempt_id,
      organization_id: attempt.organization_id,
      mission_id: attempt.mission_id,
      command_queue_entry_id: attempt.command_queue_entry_id,
      command_request_id: attempt.command_request_id,
      source_endpoint_ref: attempt.source_endpoint_ref,
      realized_contact_id: attempt.realized_contact_id,
      path_id: attempt.path_id,
      transport_binding_id: attempt.transport_binding_id,
      mission_model_revision_id: attempt.mission_model_revision_id,
      command_id: attempt.command_id,
      command_name: attempt.command_name,
      layout_kind: maybe_atom_to_string(attempt.layout_kind),
      preferred_uplink_service: attempt.preferred_uplink_service,
      apid: attempt.apid,
      service_type: attempt.service_type,
      service_subtype: attempt.service_subtype,
      opcode: JsonDocument.encode(attempt.opcode),
      encoded_binary_base64: attempt.encoded_binary_base64,
      encoded_size_bytes: attempt.encoded_size_bytes,
      lifecycle_state: Atom.to_string(attempt.lifecycle_state),
      verification_state: maybe_atom_to_string(attempt.verification_state),
      failure_reason: attempt.failure_reason,
      released_by: JsonDocument.encode(attempt.released_by),
      attempted_at: iso8601(attempt.attempted_at),
      released_at: iso8601(attempt.released_at),
      metadata: JsonDocument.encode(attempt.metadata)
    }
  end

  def command_verifier_instance(%CommandVerifierInstance{} = verifier) do
    %{
      command_verifier_instance_id: verifier.command_verifier_instance_id,
      organization_id: verifier.organization_id,
      mission_id: verifier.mission_id,
      command_request_id: verifier.command_request_id,
      command_release_attempt_id: verifier.command_release_attempt_id,
      source_endpoint_ref: verifier.source_endpoint_ref,
      mission_model_revision_id: verifier.mission_model_revision_id,
      command_id: verifier.command_id,
      command_name: verifier.command_name,
      verifier_id: verifier.verifier_id,
      verifier_name: verifier.verifier_name,
      phase: Atom.to_string(verifier.phase),
      severity: maybe_atom_to_string(verifier.severity),
      success_criteria: JsonDocument.encode(verifier.success_criteria),
      failure_criteria: JsonDocument.encode(verifier.failure_criteria),
      delay_until: iso8601(verifier.delay_until),
      timeout_at: iso8601(verifier.timeout_at),
      lifecycle_state: Atom.to_string(verifier.lifecycle_state),
      matched_record_kind: maybe_atom_to_string(verifier.matched_record_kind),
      matched_record_id: verifier.matched_record_id,
      matched_at: iso8601(verifier.matched_at),
      failure_reason: verifier.failure_reason,
      metadata: JsonDocument.encode(verifier.metadata)
    }
  end

  def command_request_decision_result(%{
        approval: %CommandApproval{} = approval,
        command_request: %CommandRequest{} = request
      }) do
    %{approval: command_approval(approval), command_request: command_request(request)}
  end

  def command_request_enqueue_result(%{
        queue_entry: %CommandQueueEntry{} = entry,
        command_request: %CommandRequest{} = request
      }) do
    %{queue_entry: command_queue_entry(entry), command_request: command_request(request)}
  end

  def command_queue_entry_release_result(%{
        release_attempt: %CommandReleaseAttempt{} = attempt,
        queue_entry: %CommandQueueEntry{} = entry,
        command_request: %CommandRequest{} = request
      }) do
    %{
      release_attempt: command_release_attempt(attempt),
      queue_entry: command_queue_entry(entry),
      command_request: command_request(request)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp maybe_atom_to_string(nil), do: nil
  defp maybe_atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_atom_to_string(value), do: value
end
