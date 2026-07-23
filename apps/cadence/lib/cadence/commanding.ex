defmodule Cadence.Commanding do
  @moduledoc """
  Persistence and validation boundary for command stages, staged command items,
  validated command requests, command approvals, queued command entries, and
  release attempts.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandStage,
    CommandVerifierInstance,
    Dispatcher,
    DispatchSupervisor,
    LifecyclePolicy,
    ReleaseArtifacts,
    ReleaseStore,
    ReleaseTargetSelection,
    RequestQueueStore,
    RequestValidation,
    StagedCommandItem,
    StageStore,
    VerifierScheduler,
    VerifierStore,
    VerifierWorkflow
  }

  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}
  alias Cadence.Control.Commanding, as: ControlCommanding
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}
  alias Cadence.Telemetry.Sample

  alias Cadence.Persistence.Schemas.{
    TransportActionRequestRow,
    TransportCapabilityRecordRow
  }

  alias Cadence.Repo

  @spec persist_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def persist_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    StageStore.persist_stage(organization_id, command_stage)
  end

  @spec update_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def update_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    StageStore.update_stage(organization_id, command_stage)
  end

  @spec fetch_command_stage(binary(), binary(), binary()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def fetch_command_stage(organization_id, mission_id, command_stage_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) do
    StageStore.fetch_stage(organization_id, mission_id, command_stage_id)
  end

  @spec list_command_stages(binary(), binary(), keyword()) :: [CommandStage.t()]
  def list_command_stages(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    StageStore.list_stages(organization_id, mission_id, opts)
  end

  @spec persist_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def persist_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    StageStore.persist_item(organization_id, staged_command_item)
  end

  @spec update_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def update_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    StageStore.update_item(organization_id, staged_command_item)
  end

  @spec fetch_staged_command_item(binary(), binary(), binary()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def fetch_staged_command_item(organization_id, mission_id, staged_command_item_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(staged_command_item_id) do
    StageStore.fetch_item(organization_id, mission_id, staged_command_item_id)
  end

  @spec list_staged_command_items(binary(), binary(), keyword()) :: [StagedCommandItem.t()]
  def list_staged_command_items(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    StageStore.list_items(organization_id, mission_id, opts)
  end

  @spec persist_command_request(binary(), CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def persist_command_request(organization_id, %CommandRequest{} = command_request)
      when is_binary(organization_id) do
    RequestQueueStore.persist_request(organization_id, command_request)
  end

  @spec fetch_command_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def fetch_command_request(organization_id, mission_id, command_request_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_request_id) do
    RequestQueueStore.fetch_request(organization_id, mission_id, command_request_id)
  end

  @spec list_command_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  def list_command_requests(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    RequestQueueStore.list_requests(organization_id, mission_id, opts)
  end

  @spec approve_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def approve_command_request(
        organization_id,
        mission_id,
        command_request_id,
        approved_by,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(approved_by) and is_list(opts) do
    RequestQueueStore.decide_request(
      organization_id,
      mission_id,
      command_request_id,
      :approved,
      approved_by,
      opts
    )
  end

  @spec reject_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{approval: CommandApproval.t(), command_request: CommandRequest.t()}}
          | {:error, term()}
  def reject_command_request(
        organization_id,
        mission_id,
        command_request_id,
        rejected_by,
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(rejected_by) and is_list(opts) do
    RequestQueueStore.decide_request(
      organization_id,
      mission_id,
      command_request_id,
      :rejected,
      rejected_by,
      opts
    )
  end

  @spec fetch_command_approval(binary(), binary(), binary()) ::
          {:ok, CommandApproval.t()} | {:error, term()}
  def fetch_command_approval(organization_id, mission_id, command_approval_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_approval_id) do
    RequestQueueStore.fetch_approval(organization_id, mission_id, command_approval_id)
  end

  @spec list_command_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  def list_command_approvals(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    RequestQueueStore.list_approvals(organization_id, mission_id, opts)
  end

  @spec enqueue_command_request(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, %{command_request: CommandRequest.t(), queue_entry: CommandQueueEntry.t()}}
          | {:error, term()}
  def enqueue_command_request(
        organization_id,
        mission_id,
        command_request_id,
        enqueued_by \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_request_id) and is_map(enqueued_by) and is_list(opts) do
    case RequestQueueStore.enqueue_request(
           organization_id,
           mission_id,
           command_request_id,
           enqueued_by,
           opts
         ) do
      {:ok, %{queue_entry: queue_entry} = result} ->
        maybe_schedule_queue_lane_dispatch(
          queue_entry.organization_id,
          queue_entry.mission_id,
          queue_entry.queue_lane_key
        )

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec fetch_command_queue_entry(binary(), binary(), binary()) ::
          {:ok, CommandQueueEntry.t()} | {:error, term()}
  def fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) do
    RequestQueueStore.fetch_queue_entry(organization_id, mission_id, command_queue_entry_id)
  end

  @spec list_command_queue_entries(binary(), binary(), keyword()) :: [CommandQueueEntry.t()]
  def list_command_queue_entries(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    RequestQueueStore.list_queue_entries(organization_id, mission_id, opts)
  end

  @spec list_pending_queue_lanes(keyword()) :: [
          %{organization_id: binary(), mission_id: binary(), queue_lane_key: binary()}
        ]
  def list_pending_queue_lanes(opts \\ []) when is_list(opts) do
    RequestQueueStore.list_pending_lanes(opts)
  end

  @spec notify_release_target_available(RealizedContact.t()) :: :ok
  def notify_release_target_available(%RealizedContact{} = realized_contact)
      when realized_contact.lifecycle_state in [:defined, :active] do
    lane_keys = release_target_lane_keys(realized_contact)

    if lane_keys == [] do
      :ok
    else
      realized_contact.organization_id
      |> RequestQueueStore.pending_target_lanes(realized_contact.mission_id, lane_keys)
      |> Enum.each(fn lane ->
        maybe_schedule_queue_lane_dispatch(
          lane.organization_id,
          lane.mission_id,
          lane.queue_lane_key
        )
      end)
    end

    :ok
  end

  def notify_release_target_available(%RealizedContact{}), do: :ok

  defp release_target_lane_keys(%RealizedContact{} = realized_contact) do
    realized_contact.paths
    |> Enum.filter(&selected_uplink_path?/1)
    |> Enum.map(fn %Path{source_endpoint_ref: source_endpoint_ref} -> source_endpoint_ref end)
    |> Enum.concat(realized_contact.source_endpoint_refs)
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp selected_uplink_path?(%Path{direction: :uplink, selection_role: :selected}), do: true
  defp selected_uplink_path?(%Path{}), do: false

  @spec requeue_release_pending_queue_entries() :: non_neg_integer()
  def requeue_release_pending_queue_entries do
    RequestQueueStore.requeue_release_pending()
  end

  @spec dispatch_queue_lane(binary(), binary(), binary(), map(), keyword()) ::
          {:ok,
           %{
             release_attempt: CommandReleaseAttempt.t(),
             queue_entry: CommandQueueEntry.t(),
             command_request: CommandRequest.t()
           }}
          | {:error, term()}
  def dispatch_queue_lane(
        organization_id,
        mission_id,
        queue_lane_key,
        released_by \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) and
             is_map(released_by) and is_list(opts) do
    attempted_at = Keyword.get(opts, :attempted_at, DateTime.utc_now())

    with :ok <-
           RequestQueueStore.ensure_lane_not_in_flight(
             organization_id,
             mission_id,
             queue_lane_key
           ),
         {:ok, %CommandQueueEntryRow{} = queue_entry_row} <-
           RequestQueueStore.next_dispatch_candidate(
             organization_id,
             mission_id,
             queue_lane_key,
             attempted_at
           ),
         {:ok, %CommandRequestRow{} = request_row} <-
           RequestQueueStore.fetch_request_row(
             organization_id,
             mission_id,
             queue_entry_row.command_request_id
           ),
         {:ok,
          %{
            realized_contact: %RealizedContact{} = realized_contact,
            path: %Path{} = path,
            transport_binding: %TransportBinding{} = transport_binding
          }} <-
           ReleaseTargetSelection.resolve_dispatch(
             organization_id,
             mission_id,
             CommandRequestRow.to_domain(request_row)
           ) do
      release_command_queue_entry(
        organization_id,
        mission_id,
        queue_entry_row.command_queue_entry_id,
        realized_contact.realized_contact_id,
        released_by,
        attempted_at: attempted_at,
        path_id: path.path_id,
        transport_binding_id: transport_binding.transport_binding_id
      )
    end
  end

  @spec fetch_command_release_attempt(binary(), binary(), binary()) ::
          {:ok, CommandReleaseAttempt.t()} | {:error, term()}
  def fetch_command_release_attempt(organization_id, mission_id, command_release_attempt_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_release_attempt_id) do
    ReleaseStore.fetch(organization_id, mission_id, command_release_attempt_id)
  end

  @spec list_command_release_attempts(binary(), binary(), keyword()) :: [
          CommandReleaseAttempt.t()
        ]
  def list_command_release_attempts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ReleaseStore.list(organization_id, mission_id, opts)
  end

  @spec fetch_command_verifier_instance(binary(), binary(), binary()) ::
          {:ok, CommandVerifierInstance.t()} | {:error, term()}
  def fetch_command_verifier_instance(organization_id, mission_id, command_verifier_instance_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_verifier_instance_id) do
    VerifierStore.fetch(organization_id, mission_id, command_verifier_instance_id)
  end

  @spec list_command_verifier_instances(binary(), binary(), keyword()) :: [
          CommandVerifierInstance.t()
        ]
  def list_command_verifier_instances(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    VerifierStore.list(organization_id, mission_id, opts)
  end

  @spec evaluate_command_verifiers([Sample.t()]) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_command_verifiers(telemetry_samples) when is_list(telemetry_samples) do
    case Repo.transaction(fn -> evaluate_command_verifiers(Repo, telemetry_samples) end) do
      {:ok, {:ok, verifier_instances}} ->
        VerifierScheduler.notify_verifier_instances_changed(verifier_instances)
        {:ok, verifier_instances}

      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec evaluate_command_verifiers(module(), [Sample.t()]) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_command_verifiers(repo, telemetry_samples)
      when is_list(telemetry_samples) do
    VerifierWorkflow.evaluate_telemetry(
      telemetry_samples,
      fn organization_id, mission_id ->
        VerifierStore.pending_entries(repo, organization_id, mission_id)
      end,
      &VerifierStore.apply_updates(repo, &1)
    )
  end

  @spec evaluate_transport_command_verifiers(
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()]
        ) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_transport_command_verifiers(
        transport_capability_records,
        transport_action_requests
      )
      when is_list(transport_capability_records) and is_list(transport_action_requests) do
    case Repo.transaction(fn ->
           evaluate_transport_command_verifiers(
             Repo,
             transport_capability_records,
             transport_action_requests
           )
         end) do
      {:ok, {:ok, verifier_instances}} ->
        VerifierScheduler.notify_verifier_instances_changed(verifier_instances)
        {:ok, verifier_instances}

      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec evaluate_transport_command_verifiers(
          module(),
          [TransportCapabilityRecord.t()],
          [TransportActionRequest.t()]
        ) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def evaluate_transport_command_verifiers(
        repo,
        transport_capability_records,
        transport_action_requests
      )
      when is_list(transport_capability_records) and is_list(transport_action_requests) do
    VerifierWorkflow.evaluate_transport(
      transport_capability_records,
      transport_action_requests,
      fn organization_id, mission_id, command_release_attempt_ids ->
        VerifierStore.pending_transport_entries(
          repo,
          organization_id,
          mission_id,
          command_release_attempt_ids
        )
      end,
      &VerifierStore.apply_updates(repo, &1)
    )
  end

  @spec command_verifier_timeout_projection() :: [CommandVerifierInstance.t()]
  def command_verifier_timeout_projection do
    VerifierStore.timeout_projection()
  end

  @spec timeout_command_verifier_instances(DateTime.t()) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def timeout_command_verifier_instances(%DateTime{} = current_time) do
    case Repo.transaction(fn -> timeout_command_verifier_instances(Repo, current_time) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @spec timeout_command_verifier_instances(module(), DateTime.t()) ::
          {:ok, [CommandVerifierInstance.t()]} | {:error, term()}
  def timeout_command_verifier_instances(repo, %DateTime{} = current_time) do
    VerifierStore.timeout(repo, current_time)
  end

  @spec release_command_queue_entry(binary(), binary(), binary(), binary(), map(), keyword()) ::
          {:ok,
           %{
             release_attempt: CommandReleaseAttempt.t(),
             queue_entry: CommandQueueEntry.t(),
             command_request: CommandRequest.t()
           }}
          | {:error, term()}
  def release_command_queue_entry(
        organization_id,
        mission_id,
        command_queue_entry_id,
        realized_contact_id,
        released_by \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) and is_binary(realized_contact_id) and
             is_map(released_by) and is_list(opts) do
    attempted_at = Keyword.get(opts, :attempted_at, DateTime.utc_now())

    with {:ok, %CommandQueueEntryRow{} = queue_entry_row} <-
           RequestQueueStore.fetch_queue_entry_row(
             organization_id,
             mission_id,
             command_queue_entry_id
           ),
         :ok <- LifecyclePolicy.ensure_queue_entry_releaseable(queue_entry_row, attempted_at),
         :ok <-
           RequestQueueStore.ensure_lane_not_in_flight(
             organization_id,
             mission_id,
             queue_entry_row.queue_lane_key
           ),
         :ok <-
           RequestQueueStore.ensure_entry_is_next_release_candidate(
             queue_entry_row,
             attempted_at
           ),
         {:ok, %CommandRequestRow{} = request_row} <-
           RequestQueueStore.fetch_request_row(
             organization_id,
             mission_id,
             queue_entry_row.command_request_id
           ),
         :ok <- LifecyclePolicy.ensure_request_releasable(request_row),
         {:ok, %RealizedContact{} = realized_contact} <-
           ReleaseTargetSelection.fetch_realized_contact(
             organization_id,
             mission_id,
             realized_contact_id
           ),
         {:ok, _pid} <-
           Contacts.start_realized_contact(organization_id, mission_id, realized_contact_id),
         {:ok,
          %{path: %Path{} = path, transport_binding: %TransportBinding{} = transport_binding}} <-
           ReleaseTargetSelection.resolve(
             realized_contact,
             CommandRequestRow.to_domain(request_row),
             opts
           ),
         {:ok, request_basis} <-
           RequestValidation.resolve_basis(
             organization_id,
             mission_id,
             request_row.command_snapshot_id,
             request_row.command_id
           ),
         {:ok, encoded_command} <-
           ControlCommanding.encode_command(
             request_basis.runtime_definition,
             JsonDocument.unwrap_value(request_row.resolved_argument_values_document)
           ) do
      execute_release_attempt(%{
        organization_id: organization_id,
        mission_id: mission_id,
        queue_entry_row: queue_entry_row,
        request_row: request_row,
        realized_contact: realized_contact,
        path: path,
        transport_binding: transport_binding,
        request_basis: request_basis,
        encoded_command: encoded_command,
        released_by: released_by,
        attempted_at: attempted_at,
        metadata: Keyword.get(opts, :metadata, %{})
      })
    else
      {:error, reason} ->
        {:error, reason}

      reason ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError] ->
      {:error, {:command_release_encoding_failed, Exception.message(error)}}
  end

  defp execute_release_attempt(release_context) when is_map(release_context) do
    with {:ok, %CommandQueueEntryRow{} = claimed_queue_entry_row} <-
           RequestQueueStore.claim_for_release(release_context.queue_entry_row),
         claimed_release_context = %{release_context | queue_entry_row: claimed_queue_entry_row},
         release_attempt_context =
           release_attempt_context(claimed_release_context),
         pending_attempt <-
           ReleaseArtifacts.build_attempt(
             release_attempt_context,
             claimed_release_context.encoded_command,
             claimed_release_context.released_by,
             claimed_release_context.attempted_at,
             claimed_release_context.metadata
           ),
         {:ok, %CommandReleaseAttempt{} = persisted_attempt} <-
           persist_or_restore_release_attempt(
             claimed_release_context.organization_id,
             pending_attempt,
             claimed_queue_entry_row
           ) do
      dispatch_release_attempt(claimed_release_context, persisted_attempt)
    end
  end

  defp release_attempt_context(release_context) when is_map(release_context) do
    %{
      organization_id: release_context.organization_id,
      queue_entry: CommandQueueEntryRow.to_domain(release_context.queue_entry_row),
      command_request: CommandRequestRow.to_domain(release_context.request_row),
      realized_contact: release_context.realized_contact,
      path: release_context.path,
      transport_binding: release_context.transport_binding,
      runtime_definition: release_context.request_basis.runtime_definition
    }
  end

  defp persist_or_restore_release_attempt(
         organization_id,
         %CommandReleaseAttempt{} = pending_attempt,
         %CommandQueueEntryRow{} = claimed_queue_entry_row
       ) do
    case ReleaseStore.persist(organization_id, pending_attempt) do
      {:ok, %CommandReleaseAttempt{} = persisted_attempt} ->
        {:ok, persisted_attempt}

      {:error, reason} ->
        RequestQueueStore.restore_pending(claimed_queue_entry_row)

        maybe_schedule_queue_lane_dispatch(
          claimed_queue_entry_row.organization_id,
          claimed_queue_entry_row.mission_id,
          claimed_queue_entry_row.queue_lane_key
        )

        {:error, reason}
    end
  end

  defp dispatch_release_attempt(release_context, %CommandReleaseAttempt{} = persisted_attempt)
       when is_map(release_context) do
    case ControlCommanding.transmit_release_attempt(release_context, persisted_attempt) do
      {:ok, _transport_outputs} ->
        complete_release_success(
          release_context.queue_entry_row,
          release_context.request_row,
          persisted_attempt,
          release_context.request_basis.verifier_plans,
          release_context.attempted_at
        )

      {:error, reason} ->
        complete_release_failure(release_context.queue_entry_row, persisted_attempt, reason)
        {:error, reason}
    end
  end

  @spec submit_staged_command_items(binary(), binary(), binary(), [binary()], map()) ::
          {:ok, [CommandRequest.t()]} | {:error, term()}
  def submit_staged_command_items(
        organization_id,
        mission_id,
        command_stage_id,
        staged_command_item_ids,
        requested_by \\ %{}
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) and
             is_list(staged_command_item_ids) and is_map(requested_by) do
    StageStore.submit_items(
      organization_id,
      mission_id,
      command_stage_id,
      staged_command_item_ids,
      requested_by
    )
  end

  defp complete_release_success(
         %CommandQueueEntryRow{} = queue_entry_row,
         %CommandRequestRow{} = request_row,
         %CommandReleaseAttempt{} = command_release_attempt,
         verifier_plans,
         %DateTime{} = attempted_at
       )
       when is_list(verifier_plans) do
    with {:ok, %CommandReleaseAttemptRow{} = release_attempt_row} <-
           ReleaseStore.fetch_row(
             command_release_attempt.organization_id,
             command_release_attempt.mission_id,
             command_release_attempt.command_release_attempt_id
           ) do
      initial_verification_state = ReleaseArtifacts.initial_verification_state(verifier_plans)

      completed_release_attempt =
        %CommandReleaseAttempt{
          command_release_attempt
          | lifecycle_state: :released,
            verification_state: initial_verification_state,
            released_at: attempted_at,
            failure_reason: nil
        }

      verifier_instances =
        ReleaseArtifacts.verifier_instances(
          CommandQueueEntryRow.to_domain(queue_entry_row),
          CommandRequestRow.to_domain(request_row),
          completed_release_attempt,
          verifier_plans,
          attempted_at
        )

      release_attempt_row
      |> release_success_multi(
        queue_entry_row,
        request_row,
        completed_release_attempt,
        verifier_instances,
        initial_verification_state
      )
      |> Repo.transaction()
      |> handle_complete_release_success_result()
    end
  end

  defp release_success_multi(
         %CommandReleaseAttemptRow{} = release_attempt_row,
         %CommandQueueEntryRow{} = queue_entry_row,
         %CommandRequestRow{} = request_row,
         %CommandReleaseAttempt{} = completed_release_attempt,
         verifier_instances,
         initial_verification_state
       ) do
    Multi.new()
    |> Multi.update(
      :command_release_attempt,
      CommandReleaseAttemptRow.update_changeset(release_attempt_row, completed_release_attempt)
    )
    |> Multi.update(
      :command_queue_entry,
      CommandQueueEntryRow.lifecycle_changeset(queue_entry_row, :released)
    )
    |> Multi.update(
      :command_request,
      request_row
      |> CommandRequestRow.lifecycle_changeset(:released)
      |> Ecto.Changeset.put_change(
        :verification_state,
        Atom.to_string(initial_verification_state)
      )
    )
    |> VerifierStore.add_inserts(verifier_instances)
    |> Multi.run(:transport_command_verifier_evaluations, fn repo, _changes ->
      evaluate_transport_command_verifiers_for_release_attempt(
        repo,
        queue_entry_row.organization_id,
        queue_entry_row.mission_id,
        completed_release_attempt.command_release_attempt_id
      )
    end)
    |> Multi.run(:pending_command_verifier_timeouts, fn repo, _changes ->
      {:ok,
       VerifierStore.pending_timeout_instances(
         repo,
         queue_entry_row.organization_id,
         queue_entry_row.mission_id,
         completed_release_attempt.command_release_attempt_id
       )}
    end)
    |> Multi.run(:final_command_release_attempt, fn repo, _changes ->
      ReleaseStore.fetch_row(
        repo,
        queue_entry_row.organization_id,
        queue_entry_row.mission_id,
        completed_release_attempt.command_release_attempt_id
      )
    end)
    |> Multi.run(:final_command_request, fn repo, _changes ->
      fetch_final_command_request_row(repo, queue_entry_row, request_row)
    end)
  end

  defp fetch_final_command_request_row(
         repo,
         %CommandQueueEntryRow{} = queue_entry_row,
         %CommandRequestRow{} = request_row
       ) do
    case repo.get_by(CommandRequestRow,
           organization_id: queue_entry_row.organization_id,
           mission_id: queue_entry_row.mission_id,
           command_request_id: request_row.command_request_id
         ) do
      %CommandRequestRow{} = final_request_row ->
        {:ok, final_request_row}

      nil ->
        {:error, :command_request_not_found}
    end
  end

  defp handle_complete_release_success_result(
         {:ok,
          %{
            final_command_release_attempt: release_attempt_row,
            command_queue_entry: queue_entry_row,
            final_command_request: request_row,
            pending_command_verifier_timeouts: pending_command_verifier_timeouts
          }}
       ) do
    VerifierScheduler.notify_verifier_instances_changed(pending_command_verifier_timeouts)

    maybe_schedule_queue_lane_dispatch(
      queue_entry_row.organization_id,
      queue_entry_row.mission_id,
      queue_entry_row.queue_lane_key
    )

    {:ok,
     %{
       release_attempt: CommandReleaseAttemptRow.to_domain(release_attempt_row),
       queue_entry: CommandQueueEntryRow.to_domain(queue_entry_row),
       command_request: CommandRequestRow.to_domain(request_row)
     }}
  end

  defp handle_complete_release_success_result(
         {:error, _operation, %Changeset{} = changeset, _changes_so_far}
       ) do
    {:error, changeset}
  end

  defp handle_complete_release_success_result({:error, _operation, reason, _changes_so_far}) do
    {:error, reason}
  end

  defp complete_release_failure(
         %CommandQueueEntryRow{} = queue_entry_row,
         %CommandReleaseAttempt{} = command_release_attempt,
         reason
       ) do
    case ReleaseStore.fetch_row(
           command_release_attempt.organization_id,
           command_release_attempt.mission_id,
           command_release_attempt.command_release_attempt_id
         ) do
      {:ok, %CommandReleaseAttemptRow{} = release_attempt_row} ->
        failed_release_attempt =
          %CommandReleaseAttempt{
            command_release_attempt
            | lifecycle_state: :release_failed,
              failure_reason: inspect(reason),
              released_at: nil
          }

        _ =
          Multi.new()
          |> Multi.update(
            :command_release_attempt,
            CommandReleaseAttemptRow.update_changeset(release_attempt_row, failed_release_attempt)
          )
          |> Multi.update(
            :command_queue_entry,
            CommandQueueEntryRow.lifecycle_changeset(queue_entry_row, :pending)
          )
          |> Repo.transaction()

        maybe_schedule_queue_lane_dispatch(
          queue_entry_row.organization_id,
          queue_entry_row.mission_id,
          queue_entry_row.queue_lane_key
        )

        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp evaluate_transport_command_verifiers_for_release_attempt(
         repo,
         organization_id,
         mission_id,
         command_release_attempt_id
       )
       when is_binary(organization_id) and is_binary(mission_id) and
              is_binary(command_release_attempt_id) do
    transport_capability_records =
      TransportCapabilityRecordRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          fragment(
            "? ->> 'command_release_attempt_id' = ?",
            row.metadata,
            ^command_release_attempt_id
          )
      )
      |> order_by([row], asc: row.recorded_at, asc: row.transport_record_id)
      |> repo.all()
      |> Enum.map(&TransportCapabilityRecordRow.to_domain/1)

    transport_action_requests =
      TransportActionRequestRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_release_attempt_id == ^command_release_attempt_id
      )
      |> order_by([row], asc: row.requested_at, asc: row.action_request_id)
      |> repo.all()
      |> Enum.map(&TransportActionRequestRow.to_domain/1)

    evaluate_transport_command_verifiers(
      repo,
      transport_capability_records,
      transport_action_requests
    )
  end

  defp maybe_schedule_queue_lane_dispatch(organization_id, mission_id, queue_lane_key)
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    case DispatchSupervisor.lane_dispatcher(organization_id, mission_id, queue_lane_key) do
      {:ok, lane_dispatcher} when lane_dispatcher == self() ->
        send(self(), :dispatch)

      _other ->
        _ = Dispatcher.kick_lane(organization_id, mission_id, queue_lane_key)
        :ok
    end

    :ok
  end
end
