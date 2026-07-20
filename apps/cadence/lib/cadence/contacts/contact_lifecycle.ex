defmodule Cadence.Contacts.ContactLifecycle do
  @moduledoc """
  Orchestrates contact reconciliation, runtime transitions, and operator actions.
  """

  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.ContactRuntimeConfig
  alias Cadence.Contacts.ContactStore
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Contacts.Validation
  alias Cadence.Runtime

  @spec reconcile(DateTime.t()) :: {:ok, map()}
  def reconcile(%DateTime{} = reference_time) do
    do_reconcile(nil, reference_time)
  end

  @spec reconcile(binary(), DateTime.t()) :: {:ok, map()}
  def reconcile(mission_id, %DateTime{} = reference_time) when is_binary(mission_id) do
    do_reconcile(mission_id, reference_time)
  end

  @spec realize_scheduled(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled(mission_id, scheduled_contact_id, opts)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           ContactStore.fetch_scheduled(mission_id, scheduled_contact_id) do
      realize_scheduled_record(scheduled_contact, opts)
    end
  end

  @spec realize_scheduled(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def realize_scheduled(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           ContactStore.fetch_scheduled(organization_id, mission_id, scheduled_contact_id) do
      realize_scheduled_record(scheduled_contact, opts)
    end
  end

  @spec cancel_scheduled(binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled(mission_id, scheduled_contact_id, opts)
      when is_binary(mission_id) and is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           ContactStore.fetch_scheduled(mission_id, scheduled_contact_id) do
      cancel_scheduled_record(scheduled_contact, opts)
    end
  end

  @spec cancel_scheduled(binary(), binary(), binary(), keyword()) ::
          {:ok, ScheduledContact.t()} | {:error, term()}
  def cancel_scheduled(organization_id, mission_id, scheduled_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(scheduled_contact_id) and is_list(opts) do
    with {:ok, %ScheduledContact{} = scheduled_contact} <-
           ContactStore.fetch_scheduled(organization_id, mission_id, scheduled_contact_id) do
      cancel_scheduled_record(scheduled_contact, opts)
    end
  end

  @spec start_realized(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized(%RealizedContact{} = realized_contact) do
    start_runtime_and_mark_active(realized_contact, %{started_at: DateTime.utc_now()})
  end

  @spec start_realized(binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           ContactStore.fetch_realized(mission_id, realized_contact_id) do
      start_realized(realized_contact)
    end
  end

  @spec start_realized(binary(), binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           ContactStore.fetch_realized(organization_id, mission_id, realized_contact_id) do
      start_realized(realized_contact)
    end
  end

  @spec end_realized_early(binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_early(mission_id, realized_contact_id, opts)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_list(opts) do
    case ContactStore.fetch_realized(mission_id, realized_contact_id) do
      {:ok, %RealizedContact{} = realized_contact} ->
        end_realized_early_record(realized_contact, opts)

      {:error, :realized_contact_not_found} ->
        case Runtime.stop_realized_contact(mission_id, realized_contact_id) do
          :ok -> {:error, :realized_contact_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec end_realized_early(binary(), binary(), binary(), keyword()) ::
          {:ok, RealizedContact.t()} | {:error, term()}
  def end_realized_early(organization_id, mission_id, realized_contact_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) and is_list(opts) do
    case ContactStore.fetch_realized(organization_id, mission_id, realized_contact_id) do
      {:ok, %RealizedContact{} = realized_contact} ->
        end_realized_early_record(realized_contact, opts)

      {:error, :realized_contact_not_found} ->
        case Runtime.stop_realized_contact(mission_id, realized_contact_id) do
          :ok -> {:error, :realized_contact_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec stop_realized(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    case end_realized_early(mission_id, realized_contact_id, []) do
      {:ok, _realized_contact} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_realized(binary(), binary(), binary()) :: :ok | {:error, term()}
  def stop_realized(organization_id, mission_id, realized_contact_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    case end_realized_early(organization_id, mission_id, realized_contact_id, []) do
      {:ok, _realized_contact} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_reconcile(mission_id, %DateTime{} = reference_time) do
    restart_candidates = ContactStore.active_realized_to_restart(reference_time, mission_id)

    {expired_scheduled_contact_ids, expiration_errors} =
      ContactStore.expired_scheduled(reference_time, mission_id)
      |> collect_reconcile_results(&expire_scheduled_for_reconcile(&1, reference_time))

    {completed_scheduled_contact_ids, scheduled_completion_errors} =
      ContactStore.completed_scheduled(reference_time, mission_id)
      |> collect_reconcile_results(&complete_scheduled_for_reconcile(&1, reference_time))

    {realized_scheduled_contact_ids, realization_errors} =
      ContactStore.due_scheduled(reference_time, mission_id)
      |> collect_reconcile_results(&realize_scheduled_for_reconcile(&1, reference_time))

    {completed_realized_contact_ids, completion_errors} =
      ContactStore.expired_active_realized(reference_time, mission_id)
      |> collect_reconcile_results(&complete_realized_for_reconcile(&1, reference_time))

    {restarted_realized_contact_ids, restart_errors} =
      restart_candidates
      |> collect_reconcile_results(&restart_realized_for_reconcile(&1, reference_time))

    {:ok,
     %{
       reference_time: reference_time,
       expired_scheduled_contact_ids: Enum.reverse(expired_scheduled_contact_ids),
       completed_scheduled_contact_ids: Enum.reverse(completed_scheduled_contact_ids),
       realized_scheduled_contact_ids: Enum.reverse(realized_scheduled_contact_ids),
       completed_realized_contact_ids: Enum.reverse(completed_realized_contact_ids),
       restarted_realized_contact_ids: Enum.reverse(restarted_realized_contact_ids),
       errors:
         Enum.reverse(expiration_errors) ++
           Enum.reverse(scheduled_completion_errors) ++
           Enum.reverse(realization_errors) ++
           Enum.reverse(completion_errors) ++ Enum.reverse(restart_errors)
     }}
  end

  defp collect_reconcile_results(contacts, action) do
    Enum.reduce(contacts, {[], []}, fn contact, {ids, errors} ->
      case action.(contact) do
        {:ok, contact_id} -> {[contact_id | ids], errors}
        :skip -> {ids, errors}
        {:error, error} -> {ids, [error | errors]}
      end
    end)
  end

  defp expire_scheduled_for_reconcile(%ScheduledContact{} = scheduled_contact, reference_time) do
    case update_scheduled(scheduled_contact, :expired, %{
           expired_at: reference_time,
           expired_from_schedule: true
         }) do
      {:ok, %ScheduledContact{} = contact} ->
        {:ok, contact.scheduled_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_expiration, scheduled_contact, reason)}
    end
  end

  defp complete_scheduled_for_reconcile(
         %ScheduledContact{} = scheduled_contact,
         reference_time
       ) do
    case update_scheduled(scheduled_contact, :completed, %{
           completed_at: reference_time,
           completed_from_schedule: true
         }) do
      {:ok, %ScheduledContact{} = contact} ->
        {:ok, contact.scheduled_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_completion, scheduled_contact, reason)}
    end
  end

  defp realize_scheduled_for_reconcile(
         %ScheduledContact{} = scheduled_contact,
         reference_time
       ) do
    case realize_scheduled(
           scheduled_contact.mission_id,
           scheduled_contact.scheduled_contact_id,
           clock_mode: :live,
           initial_time: reference_time,
           realized_at: reference_time,
           transition_time: reference_time,
           notify_scheduler?: false,
           metadata: %{scheduler_realized?: true}
         ) do
      {:ok, %RealizedContact{} = realized_contact} ->
        {:ok, realized_contact.realized_contact_id}

      {:error, :scheduled_contact_already_realized} ->
        :skip

      {:error, reason} ->
        {:error, reconcile_error(:scheduled_contact_realization, scheduled_contact, reason)}
    end
  end

  defp complete_realized_for_reconcile(
         %RealizedContact{} = realized_contact,
         reference_time
       ) do
    case complete_realized(realized_contact, %{
           completed_at: reference_time,
           completed_from_schedule: true
         }) do
      {:ok, %RealizedContact{} = contact} ->
        {:ok, contact.realized_contact_id}

      {:error, reason} ->
        {:error, reconcile_error(:realized_contact_completion, realized_contact, reason)}
    end
  end

  defp restart_realized_for_reconcile(%RealizedContact{} = realized_contact, reference_time) do
    if Runtime.realized_contact_running?(
         realized_contact.mission_id,
         realized_contact.realized_contact_id
       ) do
      :skip
    else
      case start_runtime_and_mark_active(realized_contact, %{
             reconciled_at: reference_time,
             started_at: reference_time
           }) do
        {:ok, _pid} ->
          {:ok, realized_contact.realized_contact_id}

        {:error, reason} ->
          {:error, reconcile_error(:realized_contact_restart, realized_contact, reason)}
      end
    end
  end

  defp realize_scheduled_record(%ScheduledContact{} = scheduled_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    with :ok <- Validation.schedule_realization(scheduled_contact),
         {:ok, realized_contact} <- build_realized(scheduled_contact, opts),
         :ok <- Validation.unique_path_ids(realized_contact.paths),
         {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ContactStore.persist_realization(scheduled_contact, realized_contact),
         {:ok, _pid} <-
           start_runtime_and_mark_active(persisted_realized_contact, %{
             activated_from_schedule: true,
             started_at: transition_time
           }),
         {:ok, %RealizedContact{} = active_realized_contact} <-
           ContactStore.fetch_realized(
             persisted_realized_contact.mission_id,
             persisted_realized_contact.realized_contact_id
           ) do
      scheduled_contact
      |> realized_scheduled_projection(active_realized_contact)
      |> maybe_notify_contact_changed(opts)

      active_realized_contact
      |> maybe_notify_contact_changed(opts)
    end
  end

  defp cancel_scheduled_record(%ScheduledContact{} = scheduled_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    case scheduled_contact.lifecycle_state do
      :canceled ->
        {:ok, scheduled_contact}

      :completed ->
        {:error, :scheduled_contact_completed}

      :expired ->
        {:error, :scheduled_contact_expired}

      _other_state ->
        with {:ok, _realized_contact} <-
               maybe_stop_linked_realized(scheduled_contact, transition_time, opts),
             {:ok, %ScheduledContact{} = canceled_scheduled_contact} <-
               update_scheduled(
                 scheduled_contact,
                 :canceled,
                 schedule_cancellation_metadata(scheduled_contact, transition_time, opts)
               ),
             {:ok, %ContactAction{}} <-
               ContactStore.persist_action(
                 build_scheduled_canceled_action(
                   canceled_scheduled_contact,
                   transition_time,
                   opts
                 )
               ) do
          ContactStore.notify_contact_changed(canceled_scheduled_contact)
        end
    end
  end

  defp end_realized_early_record(%RealizedContact{} = realized_contact, opts) do
    transition_time = Keyword.get(opts, :transition_time, DateTime.utc_now())

    with {:ok, %RealizedContact{} = stopped_realized_contact} <-
           stop_realized_transition(
             realized_contact,
             realized_stop_metadata(transition_time, opts)
           ),
         {:ok, _scheduled_contact} <-
           maybe_cancel_linked_scheduled(realized_contact, transition_time, opts),
         {:ok, %ContactAction{}} <-
           ContactStore.persist_action(
             build_realized_ended_early_action(stopped_realized_contact, transition_time, opts)
           ) do
      ContactStore.notify_contact_changed(stopped_realized_contact)
    end
  end

  defp start_runtime_and_mark_active(%RealizedContact{} = realized_contact, metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized(realized_contact),
         {:ok, pid} <- Runtime.start_realized_contact(persisted_realized_contact),
         {:ok, _updated_realized_contact} <-
           ContactStore.update_realized_lifecycle(
             persisted_realized_contact,
             :active,
             metadata_patch
           ) do
      {:ok, pid}
    end
  end

  defp stop_realized_transition(%RealizedContact{} = realized_contact, metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized(realized_contact),
         {:ok, %RealizedContact{} = stopped_realized_contact} <-
           mark_realized_stopped(persisted_realized_contact, metadata_patch),
         :ok <-
           Runtime.stop_realized_contact_sync(
             stopped_realized_contact.mission_id,
             stopped_realized_contact.realized_contact_id
           ) do
      {:ok, stopped_realized_contact}
    end
  end

  defp mark_realized_stopped(
         %RealizedContact{lifecycle_state: state} = realized_contact,
         _metadata_patch
       )
       when state in [:stopped, :completed],
       do: {:ok, realized_contact}

  defp mark_realized_stopped(%RealizedContact{} = realized_contact, metadata_patch) do
    ContactStore.update_realized_lifecycle(realized_contact, :stopped, metadata_patch)
  end

  defp complete_realized(%RealizedContact{} = realized_contact, metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized(realized_contact),
         {:ok, %RealizedContact{} = completed_realized_contact} <-
           ContactStore.update_realized_lifecycle(
             persisted_realized_contact,
             :completed,
             metadata_patch
           ),
         :ok <-
           Runtime.stop_realized_contact_sync(
             completed_realized_contact.mission_id,
             completed_realized_contact.realized_contact_id
           ) do
      {:ok, completed_realized_contact}
    end
  end

  defp ensure_persisted_realized(%RealizedContact{} = realized_contact) do
    case ContactStore.fetch_realized(
           realized_contact.mission_id,
           realized_contact.realized_contact_id
         ) do
      {:ok, %RealizedContact{} = persisted_realized_contact} ->
        {:ok, persisted_realized_contact}

      {:error, :realized_contact_not_found} ->
        ContactStore.persist_realized(realized_contact)
    end
  end

  defp maybe_stop_linked_realized(
         %ScheduledContact{realized_contact_id: nil},
         _transition_time,
         _opts
       ),
       do: {:ok, nil}

  defp maybe_stop_linked_realized(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    case ContactStore.fetch_realized(
           scheduled_contact.mission_id,
           scheduled_contact.realized_contact_id
         ) do
      {:ok, %RealizedContact{} = realized_contact} ->
        stop_realized_transition(
          realized_contact,
          schedule_cancellation_realized_metadata(transition_time, opts)
        )

      {:error, :realized_contact_not_found} ->
        {:ok, nil}
    end
  end

  defp maybe_cancel_linked_scheduled(
         %RealizedContact{scheduled_contact_id: nil},
         _transition_time,
         _opts
       ),
       do: {:ok, nil}

  defp maybe_cancel_linked_scheduled(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    case ContactStore.fetch_scheduled(
           realized_contact.mission_id,
           realized_contact.scheduled_contact_id
         ) do
      {:ok, %ScheduledContact{lifecycle_state: state} = scheduled_contact}
      when state in [:canceled, :completed, :expired] ->
        {:ok, scheduled_contact}

      {:ok, %ScheduledContact{} = scheduled_contact} ->
        update_scheduled(
          scheduled_contact,
          :canceled,
          realized_cancellation_metadata(realized_contact, transition_time, opts)
        )

      {:error, :scheduled_contact_not_found} ->
        {:ok, nil}
    end
  end

  defp update_scheduled(%ScheduledContact{} = scheduled_contact, state, metadata_patch) do
    ContactStore.update_scheduled_lifecycle(scheduled_contact, state, metadata_patch)
  end

  defp build_realized(%ScheduledContact{} = scheduled_contact, opts) do
    with {:ok, resolved_paths} <- ContactRuntimeConfig.resolve_paths(scheduled_contact) do
      metadata =
        scheduled_contact.metadata
        |> Map.merge(%{
          scheduled_contact_id: scheduled_contact.scheduled_contact_id,
          provider_contact_ref: scheduled_contact.provider_contact_ref,
          contact_intents: scheduled_contact.contact_intents,
          link_assignment_refs: scheduled_contact.link_assignment_refs,
          path_template_ids: scheduled_contact.path_template_ids,
          path_template_refs: scheduled_contact.path_template_refs
        })
        |> Map.merge(Keyword.get(opts, :metadata, %{}))

      {:ok,
       RealizedContact.new(%{
         realized_contact_id:
           Keyword.get(
             opts,
             :realized_contact_id,
             scheduled_contact.scheduled_contact_id <> "_run"
           ),
         organization_id: scheduled_contact.organization_id,
         mission_id: scheduled_contact.mission_id,
         scheduled_contact_id: scheduled_contact.scheduled_contact_id,
         source_endpoint_refs: scheduled_contact.source_endpoint_refs,
         contact_intents: scheduled_contact.contact_intents,
         paths: resolved_paths,
         clock_mode: Keyword.get(opts, :clock_mode, :live),
         initial_time: Keyword.get(opts, :initial_time, scheduled_contact.starts_at),
         lifecycle_state: :defined,
         realized_at: Keyword.get(opts, :realized_at, DateTime.utc_now()),
         metadata: metadata
       })}
    end
  end

  defp maybe_notify_contact_changed(contact, opts) do
    if Keyword.get(opts, :notify_scheduler?, true) do
      ContactStore.notify_contact_changed(contact)
    else
      {:ok, contact}
    end
  end

  defp realized_scheduled_projection(
         %ScheduledContact{} = scheduled_contact,
         %RealizedContact{} = realized_contact
       ) do
    %ScheduledContact{
      scheduled_contact
      | lifecycle_state: :realized,
        realized_contact_id: realized_contact.realized_contact_id
    }
  end

  defp reconcile_error(kind, %ScheduledContact{} = scheduled_contact, reason) do
    %{
      kind: kind,
      mission_id: scheduled_contact.mission_id,
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      reason: reason
    }
  end

  defp reconcile_error(kind, %RealizedContact{} = realized_contact, reason) do
    %{
      kind: kind,
      mission_id: realized_contact.mission_id,
      realized_contact_id: realized_contact.realized_contact_id,
      reason: reason
    }
  end

  defp realized_stop_metadata(transition_time, opts) do
    %{stopped_at: transition_time, ended_early?: true}
    |> maybe_put_reason(opts)
  end

  defp schedule_cancellation_realized_metadata(transition_time, opts) do
    %{
      stopped_at: transition_time,
      ended_early?: true,
      stopped_from_schedule_cancellation: true
    }
    |> maybe_put_reason(opts)
  end

  defp schedule_cancellation_metadata(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    %{
      canceled_at: transition_time,
      canceled_during_execution?: not is_nil(scheduled_contact.realized_contact_id),
      canceled_from_schedule_action: true
    }
    |> maybe_put_reason(opts)
  end

  defp realized_cancellation_metadata(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    %{
      canceled_at: transition_time,
      canceled_during_execution?: true,
      canceled_from_realized_contact_stop: true,
      realized_contact_id: realized_contact.realized_contact_id
    }
    |> maybe_put_reason(opts)
  end

  defp maybe_put_reason(metadata, opts) do
    case Keyword.get(opts, :reason) do
      nil -> metadata
      reason -> Map.put(metadata, :reason, reason)
    end
  end

  defp build_scheduled_canceled_action(
         %ScheduledContact{} = scheduled_contact,
         transition_time,
         opts
       ) do
    ContactAction.new(%{
      organization_id: scheduled_contact.organization_id,
      mission_id: scheduled_contact.mission_id,
      scheduled_contact_id: scheduled_contact.scheduled_contact_id,
      realized_contact_id: scheduled_contact.realized_contact_id,
      action_kind: :scheduled_contact_canceled,
      reason: Keyword.get(opts, :reason),
      actor: Keyword.get(opts, :actor, %{}),
      metadata: %{
        canceled_during_execution?: not is_nil(scheduled_contact.realized_contact_id)
      },
      occurred_at: transition_time
    })
  end

  defp build_realized_ended_early_action(
         %RealizedContact{} = realized_contact,
         transition_time,
         opts
       ) do
    ContactAction.new(%{
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      realized_contact_id: realized_contact.realized_contact_id,
      action_kind: :realized_contact_ended_early,
      reason: Keyword.get(opts, :reason),
      actor: Keyword.get(opts, :actor, %{}),
      metadata: %{ended_early?: true},
      occurred_at: transition_time
    })
  end
end
