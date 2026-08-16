defmodule Cadence.Commanding.ReleaseArtifacts do
  @moduledoc """
  Builds release-attempt, uplink-request, and verifier-instance domain values.
  """

  alias Cadence.ActionRequests.UplinkRequest
  alias Cadence.Catalog.Command.Compiler.{RuntimeDefinition, VerifierPlan}

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}

  @type release_context :: %{
          organization_id: binary(),
          queue_entry: CommandQueueEntry.t(),
          command_request: CommandRequest.t(),
          realized_contact: RealizedContact.t(),
          path: Path.t(),
          transport_binding: TransportBinding.t(),
          runtime_definition: RuntimeDefinition.t()
        }

  @spec build_attempt(release_context(), map(), map(), DateTime.t(), map()) ::
          CommandReleaseAttempt.t()
  def build_attempt(
        release_context,
        encoded_command,
        released_by,
        %DateTime{} = attempted_at,
        metadata
      )
      when is_map(release_context) and is_map(encoded_command) and is_map(released_by) and
             is_map(metadata) do
    queue_entry = release_context.queue_entry
    command_request = release_context.command_request
    realized_contact = release_context.realized_contact
    path = release_context.path
    transport_binding = release_context.transport_binding
    runtime_definition = release_context.runtime_definition

    CommandReleaseAttempt.new(%{
      organization_id: release_context.organization_id,
      mission_id: queue_entry.mission_id,
      command_queue_entry_id: queue_entry.command_queue_entry_id,
      command_request_id: command_request.command_request_id,
      source_endpoint_ref: queue_entry.source_endpoint_ref,
      realized_contact_id: realized_contact.realized_contact_id,
      path_id: path.path_id,
      transport_binding_id: transport_binding.transport_binding_id,
      mission_model_revision_id: command_request.mission_model_revision_id,
      command_id: command_request.command_id,
      command_name: command_request.command_name,
      layout_kind: runtime_definition.layout_kind,
      preferred_uplink_service: command_request.preferred_uplink_service,
      apid: runtime_definition.apid,
      service_type: runtime_definition.service_type,
      service_subtype: runtime_definition.service_subtype,
      opcode: runtime_definition.opcode,
      encoded_binary_base64: encoded_command.base64,
      encoded_size_bytes: encoded_command.size_bytes,
      lifecycle_state: :release_pending,
      verification_state: nil,
      released_by: released_by,
      attempted_at: attempted_at,
      metadata: metadata
    })
  end

  @spec initial_verification_state([VerifierPlan.t()]) :: :not_required | :pending
  def initial_verification_state([]), do: :not_required
  def initial_verification_state(_verifier_plans), do: :pending

  @spec uplink_request(CommandReleaseAttempt.t()) :: UplinkRequest.t()
  def uplink_request(%CommandReleaseAttempt{} = command_release_attempt) do
    UplinkRequest.new(%{
      command_release_attempt_id: command_release_attempt.command_release_attempt_id,
      command_queue_entry_id: command_release_attempt.command_queue_entry_id,
      command_request_id: command_release_attempt.command_request_id,
      source_endpoint_ref: command_release_attempt.source_endpoint_ref,
      mission_model_revision_id: command_release_attempt.mission_model_revision_id,
      command_id: command_release_attempt.command_id,
      command_name: command_release_attempt.command_name,
      layout_kind: command_release_attempt.layout_kind,
      preferred_uplink_service: command_release_attempt.preferred_uplink_service,
      apid: command_release_attempt.apid,
      service_type: command_release_attempt.service_type,
      service_subtype: command_release_attempt.service_subtype,
      opcode: command_release_attempt.opcode,
      encoded_binary_base64: command_release_attempt.encoded_binary_base64,
      encoded_size_bytes: command_release_attempt.encoded_size_bytes || 0,
      metadata: command_release_attempt.metadata
    })
  end

  @spec verifier_instances(
          CommandQueueEntry.t(),
          CommandRequest.t(),
          CommandReleaseAttempt.t(),
          [VerifierPlan.t()],
          DateTime.t()
        ) :: [CommandVerifierInstance.t()]
  def verifier_instances(
        %CommandQueueEntry{} = queue_entry,
        %CommandRequest{} = command_request,
        %CommandReleaseAttempt{} = command_release_attempt,
        verifier_plans,
        %DateTime{} = released_at
      )
      when is_list(verifier_plans) do
    Enum.map(verifier_plans, fn %VerifierPlan{} = verifier_plan ->
      CommandVerifierInstance.new(%{
        organization_id: queue_entry.organization_id,
        mission_id: queue_entry.mission_id,
        command_request_id: command_request.command_request_id,
        command_release_attempt_id: command_release_attempt.command_release_attempt_id,
        source_endpoint_ref: queue_entry.source_endpoint_ref,
        mission_model_revision_id: command_request.mission_model_revision_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        verifier_id: verifier_plan.verifier_id,
        verifier_name: verifier_plan.name,
        phase: verifier_plan.phase,
        severity: verifier_plan.severity,
        success_criteria: verifier_plan.success_criteria,
        failure_criteria: verifier_plan.failure_criteria,
        delay_until: shift_time(released_at, verifier_plan.delay_ms),
        timeout_at: shift_time(released_at, verifier_plan.timeout_ms),
        metadata: verifier_plan.metadata
      })
    end)
  end

  defp shift_time(%DateTime{} = _datetime, nil), do: nil

  defp shift_time(%DateTime{} = datetime, milliseconds) when is_integer(milliseconds),
    do: DateTime.add(datetime, milliseconds, :millisecond)
end
