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
    CommandApprovalRow,
    CommandQueueEntry,
    CommandQueueEntryRow,
    CommandReleaseAttempt,
    CommandReleaseAttemptRow,
    CommandRequest,
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    CommandVerifierInstance,
    Dispatcher,
    DispatchSupervisor,
    Encoder,
    LifecyclePolicy,
    ReleaseArtifacts,
    ReleaseTargetSelection,
    RequestValidation,
    StagedCommandItem,
    StagedCommandItemRow,
    VerifierScheduler,
    VerifierStore,
    VerifierWorkflow
  }

  alias Cadence.Contacts
  alias Cadence.Contacts.{Path, RealizedContact, TransportBinding}
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}
  alias Cadence.Telemetry.Sample

  alias Cadence.Persistence.Schemas.{
    TransportActionRequestRow,
    TransportCapabilityRecordRow
  }

  alias Cadence.Repo
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints

  @spec persist_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def persist_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    with {:ok, scoped_command_stage} <- put_organization_scope(command_stage, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_command_stage.organization_id,
             scoped_command_stage.mission_id
           ),
         {:ok, %CommandStageRow{} = row} <-
           Repo.insert(CommandStageRow.changeset(scoped_command_stage),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_stage_id]
           ) do
      {:ok, CommandStageRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_command_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def update_command_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    with {:ok, scoped_command_stage} <- put_organization_scope(command_stage, organization_id),
         {:ok, row} <-
           fetch_command_stage_row(
             scoped_command_stage.organization_id,
             scoped_command_stage.mission_id,
             scoped_command_stage.command_stage_id
           ),
         {:ok, %CommandStageRow{} = updated_row} <-
           row
           |> CommandStageRow.update_changeset(scoped_command_stage)
           |> Repo.update() do
      {:ok, CommandStageRow.to_domain(updated_row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_command_stage(binary(), binary(), binary()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def fetch_command_stage(organization_id, mission_id, command_stage_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) do
    case Repo.get_by(CommandStageRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_stage_id: command_stage_id
         ) do
      nil -> {:error, :command_stage_not_found}
      %CommandStageRow{} = row -> {:ok, CommandStageRow.to_domain(row)}
    end
  end

  @spec list_command_stages(binary(), binary(), keyword()) :: [CommandStage.t()]
  def list_command_stages(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandStageRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.inserted_at, asc: row.command_stage_id)
    |> Repo.all()
    |> Enum.map(&CommandStageRow.to_domain/1)
  end

  @spec persist_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def persist_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    with {:ok, scoped_item} <- put_organization_scope(staged_command_item, organization_id),
         {:ok, _stage} <- validate_stage_assignment(scoped_item),
         {:ok, _source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.source_endpoint_ref
           ),
         {:ok, _request_basis} <-
           RequestValidation.resolve_basis(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.command_snapshot_id,
             scoped_item.command_id
           ),
         {:ok, %StagedCommandItemRow{} = row} <-
           Repo.insert(StagedCommandItemRow.changeset(scoped_item),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :staged_command_item_id]
           ) do
      {:ok, StagedCommandItemRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_staged_command_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def update_staged_command_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    with {:ok, scoped_item} <- put_organization_scope(staged_command_item, organization_id),
         {:ok, row} <-
           fetch_staged_command_item_row(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.staged_command_item_id
           ),
         :ok <- LifecyclePolicy.ensure_staged_item_editable(row),
         {:ok, _stage} <- validate_stage_assignment(scoped_item),
         {:ok, _source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.source_endpoint_ref
           ),
         {:ok, _request_basis} <-
           RequestValidation.resolve_basis(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.command_snapshot_id,
             scoped_item.command_id
           ),
         {:ok, %StagedCommandItemRow{} = updated_row} <-
           row
           |> StagedCommandItemRow.update_changeset(scoped_item)
           |> Repo.update() do
      {:ok, StagedCommandItemRow.to_domain(updated_row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_staged_command_item(binary(), binary(), binary()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def fetch_staged_command_item(organization_id, mission_id, staged_command_item_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(staged_command_item_id) do
    case Repo.get_by(StagedCommandItemRow,
           organization_id: organization_id,
           mission_id: mission_id,
           staged_command_item_id: staged_command_item_id
         ) do
      nil -> {:error, :staged_command_item_not_found}
      %StagedCommandItemRow{} = row -> {:ok, StagedCommandItemRow.to_domain(row)}
    end
  end

  @spec list_staged_command_items(binary(), binary(), keyword()) :: [StagedCommandItem.t()]
  def list_staged_command_items(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    StagedCommandItemRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_stage_id, Keyword.get(opts, :command_stage_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.item_order, asc: row.inserted_at, asc: row.staged_command_item_id)
    |> Repo.all()
    |> Enum.map(&StagedCommandItemRow.to_domain/1)
  end

  @spec persist_command_request(binary(), CommandRequest.t()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def persist_command_request(organization_id, %CommandRequest{} = command_request)
      when is_binary(organization_id) do
    with {:ok, scoped_request} <- put_organization_scope(command_request, organization_id),
         {:ok, validated_request} <- RequestValidation.validate_and_enrich(scoped_request),
         {:ok, %CommandRequestRow{} = row} <-
           Repo.insert(CommandRequestRow.changeset(validated_request),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_request_id]
           ) do
      {:ok, CommandRequestRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_command_request(binary(), binary(), binary()) ::
          {:ok, CommandRequest.t()} | {:error, term()}
  def fetch_command_request(organization_id, mission_id, command_request_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_request_id) do
    case Repo.get_by(CommandRequestRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> {:error, :command_request_not_found}
      %CommandRequestRow{} = row -> {:ok, CommandRequestRow.to_domain(row)}
    end
  end

  @spec list_command_requests(binary(), binary(), keyword()) :: [CommandRequest.t()]
  def list_command_requests(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandRequestRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:source_command_stage_id, Keyword.get(opts, :command_stage_id))
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.requested_at, asc: row.command_request_id)
    |> Repo.all()
    |> Enum.map(&CommandRequestRow.to_domain/1)
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
    decide_command_request(
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
    decide_command_request(
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
    case Repo.get_by(CommandApprovalRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_approval_id: command_approval_id
         ) do
      nil -> {:error, :command_approval_not_found}
      %CommandApprovalRow{} = row -> {:ok, CommandApprovalRow.to_domain(row)}
    end
  end

  @spec list_command_approvals(binary(), binary(), keyword()) :: [CommandApproval.t()]
  def list_command_approvals(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandApprovalRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:decision, decision_filter(opts))
    |> order_by([row], asc: row.decided_at, asc: row.command_approval_id)
    |> Repo.all()
    |> Enum.map(&CommandApprovalRow.to_domain/1)
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
    with {:ok, %CommandRequestRow{} = request_row} <-
           fetch_command_request_row(organization_id, mission_id, command_request_id),
         :ok <- LifecyclePolicy.ensure_request_queueable(request_row),
         :ok <- LifecyclePolicy.ensure_request_not_expired(request_row),
         :ok <- ensure_request_not_already_queued(organization_id, mission_id, command_request_id) do
      queue_entry =
        CommandQueueEntry.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          command_request_id: command_request_id,
          source_endpoint_ref: request_row.source_endpoint_ref,
          queue_lane_key: request_row.source_endpoint_ref,
          priority: request_row.priority,
          queue_sequence: System.unique_integer([:positive, :monotonic]),
          not_before: request_row.not_before,
          expires_at: request_row.expires_at,
          lifecycle_state: :pending,
          enqueued_by: enqueued_by,
          enqueued_at: Keyword.get(opts, :enqueued_at, DateTime.utc_now()),
          metadata: Keyword.get(opts, :metadata, %{})
        })

      multi =
        Multi.new()
        |> Multi.insert(:queue_entry, CommandQueueEntryRow.changeset(queue_entry))
        |> Multi.update(
          :command_request,
          CommandRequestRow.lifecycle_changeset(request_row, :queued)
        )

      case Repo.transaction(multi) do
        {:ok, %{queue_entry: queue_entry_row, command_request: updated_request_row}} ->
          maybe_schedule_queue_lane_dispatch(
            queue_entry_row.organization_id,
            queue_entry_row.mission_id,
            queue_entry_row.queue_lane_key
          )

          {:ok,
           %{
             queue_entry: CommandQueueEntryRow.to_domain(queue_entry_row),
             command_request: CommandRequestRow.to_domain(updated_request_row)
           }}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_command_queue_entry(binary(), binary(), binary()) ::
          {:ok, CommandQueueEntry.t()} | {:error, term()}
  def fetch_command_queue_entry(organization_id, mission_id, command_queue_entry_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(command_queue_entry_id) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_queue_entry_id: command_queue_entry_id
         ) do
      nil -> {:error, :command_queue_entry_not_found}
      %CommandQueueEntryRow{} = row -> {:ok, CommandQueueEntryRow.to_domain(row)}
    end
  end

  @spec list_command_queue_entries(binary(), binary(), keyword()) :: [CommandQueueEntry.t()]
  def list_command_queue_entries(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandQueueEntryRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:queue_lane_key, Keyword.get(opts, :queue_lane_key))
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row],
      asc: row.queue_lane_key,
      asc: row.priority,
      asc: row.queue_sequence,
      asc: row.command_queue_entry_id
    )
    |> Repo.all()
    |> Enum.map(&CommandQueueEntryRow.to_domain/1)
  end

  @spec list_pending_queue_lanes(keyword()) :: [
          %{organization_id: binary(), mission_id: binary(), queue_lane_key: binary()}
        ]
  def list_pending_queue_lanes(opts \\ []) when is_list(opts) do
    CommandQueueEntryRow
    |> where([row], row.lifecycle_state == "pending")
    |> maybe_filter_equals(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter_equals(:mission_id, Keyword.get(opts, :mission_id))
    |> distinct([row], [row.organization_id, row.mission_id, row.queue_lane_key])
    |> order_by([row], asc: row.organization_id, asc: row.mission_id, asc: row.queue_lane_key)
    |> select([row], %{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      queue_lane_key: row.queue_lane_key
    })
    |> Repo.all()
  end

  @spec notify_release_target_available(RealizedContact.t()) :: :ok
  def notify_release_target_available(%RealizedContact{} = realized_contact)
      when realized_contact.lifecycle_state in [:defined, :active] do
    lane_keys = release_target_lane_keys(realized_contact)

    if lane_keys == [] do
      :ok
    else
      realized_contact.organization_id
      |> pending_release_target_lanes(realized_contact.mission_id, lane_keys)
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

  defp pending_release_target_lanes(nil, mission_id, lane_keys) do
    CommandQueueEntryRow
    |> where([row], row.mission_id == ^mission_id)
    |> pending_release_target_lanes_query(lane_keys)
  end

  defp pending_release_target_lanes(organization_id, mission_id, lane_keys)
       when is_binary(organization_id) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> pending_release_target_lanes_query(lane_keys)
  end

  defp pending_release_target_lanes_query(query, lane_keys) when is_list(lane_keys) do
    query
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], row.queue_lane_key in ^lane_keys)
    |> distinct([row], [row.organization_id, row.mission_id, row.queue_lane_key])
    |> order_by([row], asc: row.organization_id, asc: row.mission_id, asc: row.queue_lane_key)
    |> select([row], %{
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      queue_lane_key: row.queue_lane_key
    })
    |> Repo.all()
  end

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
    {updated_count, _rows} =
      CommandQueueEntryRow
      |> where([row], row.lifecycle_state == "release_pending")
      |> Repo.update_all(set: [lifecycle_state: "pending"])

    updated_count
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

    with :ok <- ensure_queue_lane_not_in_flight(organization_id, mission_id, queue_lane_key),
         {:ok, %CommandQueueEntryRow{} = queue_entry_row} <-
           next_dispatch_candidate(
             organization_id,
             mission_id,
             queue_lane_key,
             attempted_at
           ),
         {:ok, %CommandRequestRow{} = request_row} <-
           fetch_command_request_row(
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
    case Repo.get_by(CommandReleaseAttemptRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_release_attempt_id: command_release_attempt_id
         ) do
      nil -> {:error, :command_release_attempt_not_found}
      %CommandReleaseAttemptRow{} = row -> {:ok, CommandReleaseAttemptRow.to_domain(row)}
    end
  end

  @spec list_command_release_attempts(binary(), binary(), keyword()) :: [
          CommandReleaseAttempt.t()
        ]
  def list_command_release_attempts(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandReleaseAttemptRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_request_id, Keyword.get(opts, :command_request_id))
    |> maybe_filter_equals(:command_queue_entry_id, Keyword.get(opts, :command_queue_entry_id))
    |> maybe_filter_equals(:realized_contact_id, Keyword.get(opts, :realized_contact_id))
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.attempted_at, asc: row.command_release_attempt_id)
    |> Repo.all()
    |> Enum.map(&CommandReleaseAttemptRow.to_domain/1)
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
           fetch_command_queue_entry_row(organization_id, mission_id, command_queue_entry_id),
         :ok <- LifecyclePolicy.ensure_queue_entry_releaseable(queue_entry_row, attempted_at),
         :ok <-
           ensure_queue_lane_not_in_flight(
             organization_id,
             mission_id,
             queue_entry_row.queue_lane_key
           ),
         :ok <- ensure_queue_entry_is_next_release_candidate(queue_entry_row, attempted_at),
         {:ok, %CommandRequestRow{} = request_row} <-
           fetch_command_request_row(
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
           Encoder.encode(
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
           claim_queue_entry_for_release(release_context.queue_entry_row),
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
    case persist_command_release_attempt(organization_id, pending_attempt) do
      {:ok, %CommandReleaseAttempt{} = persisted_attempt} ->
        {:ok, persisted_attempt}

      {:error, reason} ->
        restore_queue_entry_pending(claimed_queue_entry_row)

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
    uplink_request = ReleaseArtifacts.uplink_request(persisted_attempt)

    case Runtime.handle_path_control_input(
           release_context.mission_id,
           release_context.realized_contact.realized_contact_id,
           release_context.path.path_id,
           release_context.transport_binding.transport_binding_id,
           uplink_request,
           occurred_at: release_context.attempted_at
         ) do
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
    with {:ok, stage_row} <-
           fetch_command_stage_row(organization_id, mission_id, command_stage_id),
         :ok <- LifecyclePolicy.ensure_stage_editable(stage_row),
         {:ok, item_rows} <-
           fetch_submission_item_rows(
             organization_id,
             mission_id,
             command_stage_id,
             staged_command_item_ids
           ),
         {:ok, validated_requests} <- build_stage_requests(item_rows, requested_by) do
      multi =
        validated_requests
        |> Enum.reduce(Multi.new(), fn {item_row, request}, multi ->
          multi
          |> Multi.insert(
            {:command_request, request.command_request_id},
            CommandRequestRow.changeset(request)
          )
          |> Multi.update(
            {:staged_command_item, item_row.staged_command_item_id},
            StagedCommandItemRow.submission_changeset(item_row, request.command_request_id)
          )
        end)
        |> maybe_mark_stage_submitted(stage_row, staged_command_item_ids)

      case Repo.transaction(multi) do
        {:ok, _changes} ->
          command_request_ids =
            Enum.map(validated_requests, fn {_row, request} -> request.command_request_id end)

          {:ok,
           Enum.map(command_request_ids, fn command_request_id ->
             {:ok, request} =
               fetch_command_request(organization_id, mission_id, command_request_id)

             request
           end)}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  defp maybe_mark_stage_submitted(
         %Multi{} = multi,
         %CommandStageRow{} = stage_row,
         submitted_item_ids
       ) do
    remaining_draft_count =
      StagedCommandItemRow
      |> where(
        [row],
        row.organization_id == ^stage_row.organization_id and
          row.mission_id == ^stage_row.mission_id and
          row.command_stage_id == ^stage_row.command_stage_id and
          row.lifecycle_state == "draft" and
          row.staged_command_item_id not in ^submitted_item_ids
      )
      |> select([row], count(row.staged_command_item_id))
      |> Repo.one()

    if remaining_draft_count == 0 do
      Multi.update(
        multi,
        :command_stage_submitted,
        CommandStageRow.lifecycle_changeset(stage_row, :submitted)
      )
    else
      multi
    end
  end

  defp build_stage_requests(item_rows, requested_by) do
    item_rows
    |> Enum.reduce_while({:ok, []}, fn %StagedCommandItemRow{} = item_row, {:ok, acc} ->
      request =
        CommandRequest.new(%{
          mission_id: item_row.mission_id,
          organization_id: item_row.organization_id,
          source_endpoint_ref: item_row.source_endpoint_ref,
          command_snapshot_id: item_row.command_snapshot_id,
          command_id: item_row.command_id,
          priority: item_row.priority,
          not_before: item_row.not_before,
          expires_at: item_row.expires_at,
          requested_by: requested_by,
          source_command_stage_id: item_row.command_stage_id,
          source_staged_command_item_id: item_row.staged_command_item_id,
          argument_values: JsonDocument.unwrap_value(item_row.argument_values_document),
          metadata: %{
            "notes" => item_row.notes,
            "stage_item_order" => item_row.item_order,
            "stage_item_metadata" => JsonDocument.unwrap_value(item_row.metadata_document)
          }
        })

      case RequestValidation.validate_and_enrich(request) do
        {:ok, validated_request} ->
          {:cont, {:ok, [{item_row, validated_request} | acc]}}

        {:error, reason} ->
          {:halt,
           {:error, {:staged_command_submission_failed, item_row.staged_command_item_id, reason}}}
      end
    end)
    |> case do
      {:ok, requests} -> {:ok, Enum.reverse(requests)}
      error -> error
    end
  end

  defp decide_command_request(
         organization_id,
         mission_id,
         command_request_id,
         decision,
         decided_by,
         opts
       )
       when decision in [:approved, :rejected] do
    with {:ok, %CommandRequestRow{} = request_row} <-
           fetch_command_request_row(organization_id, mission_id, command_request_id),
         :ok <- LifecyclePolicy.ensure_request_pending_approval(request_row),
         :ok <- LifecyclePolicy.ensure_human_approval_actor(decided_by, command_request_id),
         :ok <- LifecyclePolicy.ensure_not_self_approval(request_row, decided_by) do
      approval =
        CommandApproval.new(%{
          organization_id: organization_id,
          mission_id: mission_id,
          command_request_id: command_request_id,
          decision: decision,
          decided_by: decided_by,
          decided_at: Keyword.get(opts, :decided_at, DateTime.utc_now()),
          reason: Keyword.get(opts, :reason),
          metadata: Keyword.get(opts, :metadata, %{})
        })

      request_lifecycle_state =
        case decision do
          :approved -> :approved
          :rejected -> :rejected
        end

      multi =
        Multi.new()
        |> Multi.insert(:approval, CommandApprovalRow.changeset(approval))
        |> Multi.update(
          :command_request,
          CommandRequestRow.lifecycle_changeset(request_row, request_lifecycle_state)
        )

      case Repo.transaction(multi) do
        {:ok, %{approval: approval_row, command_request: updated_request_row}} ->
          {:ok,
           %{
             approval: CommandApprovalRow.to_domain(approval_row),
             command_request: CommandRequestRow.to_domain(updated_request_row)
           }}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  defp ensure_request_not_already_queued(organization_id, mission_id, command_request_id) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> :ok
      %CommandQueueEntryRow{} -> {:error, {:command_request_already_queued, command_request_id}}
    end
  end

  defp ensure_queue_lane_not_in_flight(organization_id, mission_id, queue_lane_key)
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           queue_lane_key: queue_lane_key,
           lifecycle_state: "release_pending"
         ) do
      nil ->
        :ok

      %CommandQueueEntryRow{} ->
        {:error, {:command_queue_lane_release_pending, queue_lane_key}}
    end
  end

  defp ensure_queue_entry_is_next_release_candidate(
         %CommandQueueEntryRow{} = queue_entry_row,
         %DateTime{} = attempted_at
       ) do
    case next_release_candidate(
           queue_entry_row.organization_id,
           queue_entry_row.mission_id,
           queue_entry_row.queue_lane_key,
           attempted_at
         ) do
      nil ->
        {:error, {:command_queue_lane_empty, queue_entry_row.queue_lane_key}}

      %CommandQueueEntryRow{command_queue_entry_id: queue_entry_id}
      when queue_entry_id == queue_entry_row.command_queue_entry_id ->
        :ok

      %CommandQueueEntryRow{} = next_queue_entry_row ->
        {:error,
         {:command_queue_entry_not_next_for_release, queue_entry_row.command_queue_entry_id,
          next_queue_entry_row.command_queue_entry_id}}
    end
  end

  defp next_release_candidate(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       )
       when is_binary(organization_id) and is_binary(mission_id) and is_binary(queue_lane_key) do
    pending_release_candidates_query(organization_id, mission_id, queue_lane_key, attempted_at)
    |> order_by([row],
      asc: row.priority,
      asc: row.queue_sequence,
      asc: row.command_queue_entry_id
    )
    |> limit(1)
    |> Repo.one()
  end

  defp next_dispatch_candidate(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       ) do
    case next_release_candidate(organization_id, mission_id, queue_lane_key, attempted_at) do
      %CommandQueueEntryRow{} = queue_entry_row ->
        {:ok, queue_entry_row}

      nil ->
        case next_pending_not_before(organization_id, mission_id, queue_lane_key, attempted_at) do
          %DateTime{} = not_before ->
            {:error, {:command_queue_lane_waiting_for_not_before, queue_lane_key, not_before}}

          nil ->
            {:error, :command_queue_lane_empty}
        end
    end
  end

  defp pending_release_candidates_query(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       ) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id)
    |> where([row], row.mission_id == ^mission_id)
    |> where([row], row.queue_lane_key == ^queue_lane_key)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], is_nil(row.not_before) or row.not_before <= ^attempted_at)
    |> where([row], is_nil(row.expires_at) or row.expires_at >= ^attempted_at)
  end

  defp next_pending_not_before(
         organization_id,
         mission_id,
         queue_lane_key,
         %DateTime{} = attempted_at
       ) do
    CommandQueueEntryRow
    |> where([row], row.organization_id == ^organization_id)
    |> where([row], row.mission_id == ^mission_id)
    |> where([row], row.queue_lane_key == ^queue_lane_key)
    |> where([row], row.lifecycle_state == "pending")
    |> where([row], not is_nil(row.not_before) and row.not_before > ^attempted_at)
    |> where([row], is_nil(row.expires_at) or row.expires_at >= ^attempted_at)
    |> order_by([row], asc: row.not_before, asc: row.queue_sequence)
    |> select([row], row.not_before)
    |> limit(1)
    |> Repo.one()
  end

  defp claim_queue_entry_for_release(%CommandQueueEntryRow{} = queue_entry_row) do
    {updated_count, _rows} =
      CommandQueueEntryRow
      |> where(
        [row],
        row.organization_id == ^queue_entry_row.organization_id and
          row.mission_id == ^queue_entry_row.mission_id and
          row.command_queue_entry_id == ^queue_entry_row.command_queue_entry_id and
          row.lifecycle_state == "pending"
      )
      |> Repo.update_all(set: [lifecycle_state: "release_pending"])

    if updated_count == 1 do
      fetch_command_queue_entry_row(
        queue_entry_row.organization_id,
        queue_entry_row.mission_id,
        queue_entry_row.command_queue_entry_id
      )
    else
      {:error,
       {:command_queue_entry_not_releasable, queue_entry_row.command_queue_entry_id,
        queue_entry_row.lifecycle_state}}
    end
  end

  defp restore_queue_entry_pending(%CommandQueueEntryRow{} = queue_entry_row) do
    _ =
      queue_entry_row
      |> CommandQueueEntryRow.lifecycle_changeset(:pending)
      |> Repo.update()

    :ok
  end

  defp persist_command_release_attempt(
         organization_id,
         %CommandReleaseAttempt{} = command_release_attempt
       ) do
    with {:ok, scoped_command_release_attempt} <-
           put_organization_scope(command_release_attempt, organization_id),
         {:ok, %CommandReleaseAttemptRow{} = row} <-
           Repo.insert(CommandReleaseAttemptRow.changeset(scoped_command_release_attempt),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_release_attempt_id]
           ) do
      {:ok, CommandReleaseAttemptRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
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
           fetch_command_release_attempt_row(
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
      fetch_final_command_release_attempt_row(repo, queue_entry_row, completed_release_attempt)
    end)
    |> Multi.run(:final_command_request, fn repo, _changes ->
      fetch_final_command_request_row(repo, queue_entry_row, request_row)
    end)
  end

  defp fetch_final_command_release_attempt_row(
         repo,
         %CommandQueueEntryRow{} = queue_entry_row,
         %CommandReleaseAttempt{} = command_release_attempt
       ) do
    case repo.get_by(CommandReleaseAttemptRow,
           organization_id: queue_entry_row.organization_id,
           mission_id: queue_entry_row.mission_id,
           command_release_attempt_id: command_release_attempt.command_release_attempt_id
         ) do
      %CommandReleaseAttemptRow{} = final_release_attempt_row ->
        {:ok, final_release_attempt_row}

      nil ->
        {:error, :command_release_attempt_not_found}
    end
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
    case fetch_command_release_attempt_row(
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

  defp validate_stage_assignment(%StagedCommandItem{} = staged_command_item) do
    with {:ok, %CommandStage{} = command_stage} <-
           fetch_command_stage(
             staged_command_item.organization_id,
             staged_command_item.mission_id,
             staged_command_item.command_stage_id
           ),
         :ok <- LifecyclePolicy.ensure_stage_editable(command_stage) do
      {:ok, command_stage}
    end
  end

  defp fetch_command_stage_row(organization_id, mission_id, command_stage_id) do
    case Repo.get_by(CommandStageRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_stage_id: command_stage_id
         ) do
      nil -> {:error, :command_stage_not_found}
      %CommandStageRow{} = row -> {:ok, row}
    end
  end

  defp fetch_staged_command_item_row(organization_id, mission_id, staged_command_item_id) do
    case Repo.get_by(StagedCommandItemRow,
           organization_id: organization_id,
           mission_id: mission_id,
           staged_command_item_id: staged_command_item_id
         ) do
      nil -> {:error, :staged_command_item_not_found}
      %StagedCommandItemRow{} = row -> {:ok, row}
    end
  end

  defp fetch_command_request_row(organization_id, mission_id, command_request_id) do
    case Repo.get_by(CommandRequestRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_request_id: command_request_id
         ) do
      nil -> {:error, :command_request_not_found}
      %CommandRequestRow{} = row -> {:ok, row}
    end
  end

  defp fetch_command_queue_entry_row(organization_id, mission_id, command_queue_entry_id) do
    case Repo.get_by(CommandQueueEntryRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_queue_entry_id: command_queue_entry_id
         ) do
      nil -> {:error, :command_queue_entry_not_found}
      %CommandQueueEntryRow{} = row -> {:ok, row}
    end
  end

  defp fetch_command_release_attempt_row(
         organization_id,
         mission_id,
         command_release_attempt_id
       ) do
    case Repo.get_by(CommandReleaseAttemptRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_release_attempt_id: command_release_attempt_id
         ) do
      nil -> {:error, :command_release_attempt_not_found}
      %CommandReleaseAttemptRow{} = row -> {:ok, row}
    end
  end

  defp fetch_submission_item_rows(
         organization_id,
         mission_id,
         command_stage_id,
         staged_command_item_ids
       ) do
    normalized_ids =
      staged_command_item_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    item_rows =
      StagedCommandItemRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_stage_id == ^command_stage_id and
          row.staged_command_item_id in ^normalized_ids
      )
      |> order_by([row], asc: row.item_order, asc: row.staged_command_item_id)
      |> Repo.all()

    cond do
      normalized_ids == [] ->
        {:error, :no_staged_command_items_selected}

      length(item_rows) != length(normalized_ids) ->
        found_ids = MapSet.new(Enum.map(item_rows, & &1.staged_command_item_id))

        missing_ids =
          normalized_ids
          |> Enum.reject(&MapSet.member?(found_ids, &1))
          |> Enum.sort()

        {:error, {:staged_command_items_not_found, missing_ids}}

      Enum.any?(item_rows, &(&1.lifecycle_state != "draft")) ->
        row = Enum.find(item_rows, &(&1.lifecycle_state != "draft"))

        {:error,
         {:staged_command_item_not_editable, row.staged_command_item_id, row.lifecycle_state}}

      true ->
        {:ok, item_rows}
    end
  end

  defp lifecycle_state_filter(opts) do
    case Keyword.get(opts, :lifecycle_state) do
      nil -> nil
      lifecycle_state when is_atom(lifecycle_state) -> Atom.to_string(lifecycle_state)
      lifecycle_state when is_binary(lifecycle_state) -> lifecycle_state
    end
  end

  defp decision_filter(opts) do
    case Keyword.get(opts, :decision) do
      nil -> nil
      decision when is_atom(decision) -> Atom.to_string(decision)
      decision when is_binary(decision) -> decision
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp put_organization_scope(%CommandStage{} = command_stage, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_stage.organization_id do
      nil ->
        {:ok, %CommandStage{command_stage | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_stage}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_stage.mission_id}}
    end
  end

  defp put_organization_scope(%StagedCommandItem{} = staged_command_item, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case staged_command_item.organization_id do
      nil ->
        {:ok, %StagedCommandItem{staged_command_item | organization_id: organization_id}}

      ^organization_id ->
        {:ok, staged_command_item}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          staged_command_item.mission_id}}
    end
  end

  defp put_organization_scope(%CommandRequest{} = command_request, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_request.organization_id do
      nil ->
        {:ok, %CommandRequest{command_request | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_request}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_request.mission_id}}
    end
  end

  defp put_organization_scope(%CommandReleaseAttempt{} = command_release_attempt, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_release_attempt.organization_id do
      nil ->
        {:ok, %CommandReleaseAttempt{command_release_attempt | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_release_attempt}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_release_attempt.mission_id}}
    end
  end
end
