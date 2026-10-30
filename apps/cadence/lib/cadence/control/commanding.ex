defmodule Cadence.Control.Commanding do
  @moduledoc """
  Control-plane boundary for command queueing, release, and verification.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Commanding, as: LegacyCommanding
  alias Cadence.Commanding.CommandReleaseAttempt
  alias Cadence.Commanding.ProcessNamespace
  alias Cadence.GroundNetworks
  alias Cadence.Management.Commanding, as: ManagementCommanding
  alias Cadence.Management.Commanding.ApprovedCommand
  alias Cadence.Platform.{PreparedSendEvidence, ResolutionEvidence}
  alias Cadence.Runtime.Commanding, as: RuntimeCommanding
  alias Cadence.Runtime.{TransmitCommand, TransportRecords}

  @doc "Reviews the complete durable stream basis for a prepared physical send."
  def review_prepared_send(%Scope{} = scope, mission, id) do
    with :ok <- authorize_reconciliation(scope, mission) do
      TransportRecords.review_prepared_send(
        scope.organization_id,
        mission,
        id,
        reconciliation_options(scope.organization_id, mission)
      )
    end
  end

  @doc "Audits exact-frame evidence without releasing lane/stream holds or granting readiness."
  def reconcile_prepared_send(%Scope{} = scope, mission, id, attrs) do
    with :ok <- authorize_reconciliation(scope, mission),
         {:ok, evidence} <-
           PreparedSendEvidence.new(Scope.audit_actor(scope), attrs),
         :ok <- validate_prepared_provider_evidence(scope.organization_id, evidence) do
      TransportRecords.reconcile_prepared_send(
        scope.organization_id,
        mission,
        id,
        evidence,
        reconciliation_options(scope.organization_id, mission)
      )
    end
  end

  defp reconciliation_options(organization, mission) do
    [
      attempt_basis: fn ids ->
        Map.new(ids, fn id ->
          {id, LegacyCommanding.fetch_command_release_attempt(organization, mission, id)}
        end)
      end
    ]
  end

  defp validate_prepared_provider_evidence(
         organization,
         %{"provider_evidence_id" => id} = evidence
       )
       when is_binary(id) do
    with {:ok, stored} <- GroundNetworks.fetch_provider_evidence(organization, id),
         true <- stored.content_sha256 == evidence["evidence_sha256"] do
      :ok
    else
      _ -> {:error, :provider_evidence_mismatch}
    end
  end

  defp validate_prepared_provider_evidence(_organization, _evidence), do: :ok

  defp authorize_reconciliation(scope, mission) do
    Policy.authorize(scope, :reconcile_prepared_send, %{
      organization_id: scope.organization_id,
      mission_id: mission
    })
  end

  @doc "Returns the immutable basis token and current evidence for release resolution."
  def review_release_resolution(%Scope{} = scope, mission, id) do
    with :ok <-
           Policy.authorize(scope, :resolve_command_release, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }) do
      LegacyCommanding.review_release_resolution(scope.organization_id, mission, id)
    end
  end

  @doc "Records scoped evidence and resolves the original claim; unknown outcomes keep the lane held."
  def resolve_release_attempt(%Scope{} = scope, mission, id, attrs) do
    with :ok <-
           Policy.authorize(scope, :resolve_command_release, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         {:ok, evidence} <- ResolutionEvidence.new(Scope.audit_actor(scope), attrs) do
      LegacyCommanding.resolve_release_attempt(scope.organization_id, mission, id, evidence)
    end
  end

  @doc """
  Checks the approved basis under the request and lane locks before admission.

  An internal `:before_enqueue` callback may reject the locked request. Dispatch
  is scheduled only after the store transaction commits.
  """
  @spec enqueue(ApprovedCommand.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def enqueue(%ApprovedCommand{} = approved_command, enqueued_by \\ %{}, opts \\ []) do
    before_enqueue = Keyword.get(opts, :before_enqueue, fn _request -> :ok end)

    opts =
      opts
      |> Keyword.put(:before_enqueue, fn request ->
        if ApprovedCommand.matches_request?(approved_command, request),
          do: before_enqueue.(request),
          else: {:error, :approved_command_basis_changed}
      end)
      |> Keyword.update(
        :metadata,
        %{approved_content_sha256: approved_command.content_sha256},
        &Map.put(&1, :approved_content_sha256, approved_command.content_sha256)
      )

    LegacyCommanding.enqueue_command_request(
      approved_command.organization_id,
      approved_command.mission_id,
      approved_command.command_request_id,
      enqueued_by,
      opts
    )
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

  defdelegate notify_release_target_available(realized_contact, process_namespace),
    to: LegacyCommanding

  defdelegate timeout_command_verifier_instances(current_time), to: LegacyCommanding
  defdelegate command_verifier_timeout_projection(), to: LegacyCommanding

  defdelegate evaluate_command_verifiers(telemetry_samples), to: LegacyCommanding

  def evaluate_command_verifiers(telemetry_samples, %ProcessNamespace{} = process_namespace)
      when is_list(telemetry_samples) do
    LegacyCommanding.evaluate_command_verifiers(telemetry_samples, process_namespace)
  end

  def evaluate_command_verifiers(repo, telemetry_samples) when is_list(telemetry_samples) do
    LegacyCommanding.evaluate_command_verifiers(repo, telemetry_samples)
  end

  defdelegate evaluate_transport_command_verifiers(
                transport_capability_records,
                transport_action_requests
              ),
              to: LegacyCommanding

  def evaluate_transport_command_verifiers(
        transport_capability_records,
        transport_action_requests,
        %ProcessNamespace{} = process_namespace
      )
      when is_list(transport_capability_records) and is_list(transport_action_requests) do
    LegacyCommanding.evaluate_transport_command_verifiers(
      transport_capability_records,
      transport_action_requests,
      process_namespace
    )
  end

  def evaluate_transport_command_verifiers(
        repo,
        transport_capability_records,
        transport_action_requests
      )
      when is_list(transport_capability_records) and is_list(transport_action_requests) do
    LegacyCommanding.evaluate_transport_command_verifiers(
      repo,
      transport_capability_records,
      transport_action_requests
    )
  end

  @spec encode_command(term(), map()) :: {:ok, map()} | {:error, term()}
  def encode_command(immutable_runtime_definition, resolved_argument_values) do
    RuntimeCommanding.encode(immutable_runtime_definition, resolved_argument_values)
  end

  @doc false
  def admit_release(context) do
    RuntimeCommanding.admit(
      context.mission_id,
      context.realized_contact.realized_contact_id,
      context.path.path_id,
      context.transport_binding.transport_binding_id
    )
  end

  @spec transmit_release_attempt(map(), CommandReleaseAttempt.t()) ::
          {:ok, [term()]} | {:error, term()}
  def transmit_release_attempt(release_context, %CommandReleaseAttempt{} = attempt)
      when is_map(release_context) do
    with {:ok, %TransmitCommand{} = request} <-
           TransmitCommand.new(%{
             transmit_request_id: attempt.command_release_attempt_id,
             session_admission: release_context.uplink_admission,
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
