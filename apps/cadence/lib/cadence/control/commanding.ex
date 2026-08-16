defmodule Cadence.Control.Commanding do
  @moduledoc """
  Control-plane boundary for command queueing, release, and verification.
  """

  alias Cadence.Commanding, as: LegacyCommanding
  alias Cadence.Commanding.CommandReleaseAttempt
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.Management.Commanding.ApprovedCommand
  alias Cadence.Runtime.Commanding, as: RuntimeCommanding
  alias Cadence.Runtime.TransmitCommand

  @spec enqueue(ApprovedCommand.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def enqueue(%ApprovedCommand{} = approved_command, enqueued_by \\ %{}, opts \\ []) do
    with {:ok, command_request} <-
           LegacyCommanding.fetch_command_request(
             approved_command.organization_id,
             approved_command.mission_id,
             approved_command.command_request_id
           ),
         true <- ApprovedCommand.matches_request?(approved_command, command_request),
         {:ok, %{command_request: queued_request} = result} <-
           LegacyCommanding.enqueue_command_request(
             approved_command.organization_id,
             approved_command.mission_id,
             approved_command.command_request_id,
             enqueued_by,
             Keyword.update(
               opts,
               :metadata,
               %{approved_content_sha256: approved_command.content_sha256},
               &Map.put(&1, :approved_content_sha256, approved_command.content_sha256)
             )
           ),
         true <- ApprovedCommand.matches_request?(approved_command, queued_request) do
      {:ok, result}
    else
      false -> {:error, :approved_command_basis_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec enqueue_approved_command(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def enqueue_approved_command(
        organization_id,
        mission_id,
        command_request_id,
        enqueued_by \\ %{},
        opts \\ []
      ) do
    with {:ok, approved_command} <-
           ManagementCommanding.fetch_approved_command(
             organization_id,
             mission_id,
             command_request_id
           ) do
      enqueue(approved_command, enqueued_by, opts)
    end
  end

  defdelegate dispatch_queue_lane(
                organization_id,
                mission_id,
                queue_lane_key,
                released_by \\ %{},
                opts \\ []
              ),
              to: LegacyCommanding

  defdelegate release_command_queue_entry(
                organization_id,
                mission_id,
                command_queue_entry_id,
                realized_contact_id,
                released_by \\ %{},
                opts \\ []
              ),
              to: LegacyCommanding

  defdelegate requeue_release_pending_queue_entries(), to: LegacyCommanding
  defdelegate list_pending_queue_lanes(opts \\ []), to: LegacyCommanding
  defdelegate notify_release_target_available(realized_contact), to: LegacyCommanding
  defdelegate timeout_command_verifier_instances(current_time), to: LegacyCommanding
  defdelegate command_verifier_timeout_projection(), to: LegacyCommanding

  defdelegate evaluate_command_verifiers(telemetry_samples), to: LegacyCommanding
  defdelegate evaluate_command_verifiers(repo, telemetry_samples), to: LegacyCommanding

  defdelegate evaluate_transport_command_verifiers(
                transport_capability_records,
                transport_action_requests
              ),
              to: LegacyCommanding

  defdelegate evaluate_transport_command_verifiers(
                repo,
                transport_capability_records,
                transport_action_requests
              ),
              to: LegacyCommanding

  @spec encode_command(term(), map()) :: {:ok, map()} | {:error, term()}
  def encode_command(immutable_runtime_definition, resolved_argument_values) do
    RuntimeCommanding.encode(immutable_runtime_definition, resolved_argument_values)
  end

  @spec transmit_release_attempt(map(), CommandReleaseAttempt.t()) ::
          {:ok, [term()]} | {:error, term()}
  def transmit_release_attempt(release_context, %CommandReleaseAttempt{} = attempt)
      when is_map(release_context) do
    with {:ok, %TransmitCommand{} = request} <-
           TransmitCommand.new(%{
             transmit_request_id: attempt.command_release_attempt_id,
             mission_id: release_context.mission_id,
             realized_contact_id: release_context.realized_contact.realized_contact_id,
             path_id: release_context.path.path_id,
             transport_binding_id: release_context.transport_binding.transport_binding_id,
             occurred_at: release_context.attempted_at,
             command_queue_entry_id: attempt.command_queue_entry_id,
             command_request_id: attempt.command_request_id,
             source_endpoint_ref: attempt.source_endpoint_ref,
             mission_model_revision_id: attempt.mission_model_revision_id,
             command_id: attempt.command_id,
             command_name: attempt.command_name,
             layout_kind: attempt.layout_kind,
             preferred_uplink_service: attempt.preferred_uplink_service,
             apid: attempt.apid,
             service_type: attempt.service_type,
             service_subtype: attempt.service_subtype,
             opcode: attempt.opcode,
             encoded_binary_base64: attempt.encoded_binary_base64,
             encoded_size_bytes: attempt.encoded_size_bytes || 0,
             metadata: attempt.metadata
           }) do
      RuntimeCommanding.transmit(request)
    end
  end
end
