defmodule Cadence.Contacts.ContactLifecycle do
  @moduledoc """
  Orchestrates contact reconciliation, runtime transitions, and operator actions.
  """

  require Logger

  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.ContactRuntimeConfig
  alias Cadence.Contacts.ContactSettlement
  alias Cadence.Contacts.ContactSettler
  alias Cadence.Contacts.ContactStartFailure
  alias Cadence.Contacts.ContactStore
  alias Cadence.Contacts.JournalReclaim
  alias Cadence.Contacts.RealizationFailure
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Contacts.Validation
  alias Cadence.Control.Contacts, as: Runtime

  # Who starts a scheduled pass on time (api U46 "started_by").
  @scheduler %{"kind" => "system", "id" => "contact_scheduler"}

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
  def start_realized(%RealizedContact{} = realized_contact),
    do: start_realized_by(realized_contact, nil)

  @doc """
  Starts the contact's runtime for `started_by` (api U46), who asked:
  `%{"kind" => "user" | "service" | "system", "id" => id}`, recorded when the contact goes active.
  """
  @spec start_realized_by(RealizedContact.t(), map() | nil) :: {:ok, pid()} | {:error, term()}
  def start_realized_by(%RealizedContact{} = realized_contact, started_by) do
    start_runtime_and_mark_active(realized_contact, %{
      started_at: DateTime.utc_now(),
      started_by: started_by
    })
  end

  @spec start_realized(binary(), binary()) :: {:ok, pid()} | {:error, term()}
  def start_realized(mission_id, realized_contact_id)
      when is_binary(mission_id) and is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           ContactStore.fetch_realized(mission_id, realized_contact_id) do
      start_realized(realized_contact)
    end
  end

  @spec start_realized(binary(), binary(), binary(), map() | nil) ::
          {:ok, pid()} | {:error, term()}
  def start_realized(organization_id, mission_id, realized_contact_id, started_by \\ nil)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(realized_contact_id) do
    with {:ok, %RealizedContact{} = realized_contact} <-
           ContactStore.fetch_realized(organization_id, mission_id, realized_contact_id) do
      start_realized_by(realized_contact, started_by)
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
    # Running contacts whose runtime is gone, and in-window contacts that never started (ux U45:
    # e.g. the station listener was still held by the previous pass on the same profile).
    restart_candidates =
      ContactStore.active_realized_to_restart(reference_time, mission_id) ++
        ContactStore.defined_realized_to_start(reference_time, mission_id)

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

    :ok = close_never_started(mission_id, reference_time)

    {restarted_realized_contact_ids, restart_errors} =
      restart_candidates
      |> collect_reconcile_results(&restart_realized_for_reconcile(&1, reference_time))

    {settling_realized_contact_ids, settle_errors} =
      mission_id
      |> ContactSettlement.sweep_candidates(running_realized_contact_ids(mission_id))
      |> collect_reconcile_results(&settle_realized_for_reconcile/1)

    {replaying_realized_contact_ids, replay_errors} =
      mission_id
      |> replay_candidates(reference_time)
      |> collect_reconcile_results(&replay_realized_for_reconcile/1)

    :ok = reclaim_journals(mission_id, reference_time)

    {:ok,
     %{
       reference_time: reference_time,
       expired_scheduled_contact_ids: Enum.reverse(expired_scheduled_contact_ids),
       completed_scheduled_contact_ids: Enum.reverse(completed_scheduled_contact_ids),
       realized_scheduled_contact_ids: Enum.reverse(realized_scheduled_contact_ids),
       completed_realized_contact_ids: Enum.reverse(completed_realized_contact_ids),
       restarted_realized_contact_ids: Enum.reverse(restarted_realized_contact_ids),
       settling_realized_contact_ids: Enum.reverse(settling_realized_contact_ids),
       replaying_realized_contact_ids: Enum.reverse(replaying_realized_contact_ids),
       errors:
         Enum.reverse(expiration_errors) ++
           Enum.reverse(scheduled_completion_errors) ++
           Enum.reverse(realization_errors) ++
           Enum.reverse(completion_errors) ++
           Enum.reverse(restart_errors) ++
           Enum.reverse(settle_errors) ++ Enum.reverse(replay_errors)
     }}
  end

  @window_grace_s 5 * 60
  @hand_start_s 60 * 60

  # The orphan sweep (director, lead 11-14): a realized contact still 'defined' after its window
  # ended (plus a grace, so the in-window retry and its LOS edge aren't raced), or a hand start
  # still 'defined' an hour after it was realized, will never start. It closes as :stopped with
  # not_started {at, reason}, and a settlement that a replay never picks (no runtime ever ran, and
  # inspected_at is set: ContactSettlement.uninspected). contact_start's missed item, keyed on
  # start_failure, stays until marked seen.
  defp close_never_started(mission_id, reference_time) do
    now = DateTime.utc_now()

    reference_time
    |> DateTime.add(-@window_grace_s, :second)
    |> ContactStore.never_started(
      DateTime.add(reference_time, -@hand_start_s, :second),
      mission_id
    )
    |> Enum.each(fn {contact, reason} -> close_never_started_contact(contact, reason, now) end)

    :ok
  rescue
    exception ->
      Logger.warning(
        "never-started sweep failed for #{mission_id}: #{Exception.message(exception)}"
      )

      :ok
  end

  defp close_never_started_contact(%RealizedContact{} = contact, reason, now) do
    at = DateTime.to_iso8601(now)

    settlement =
      contact.metadata
      |> Map.get("settlement", %{})
      |> Map.merge(%{
        "state" => "settled",
        "settled_at" => at,
        "runtime" => "absent",
        "inspected_at" => at
      })

    case ContactStore.update_realized_lifecycle(contact, :stopped, %{
           "not_started" => %{"at" => at, "reason" => reason},
           "settlement" => settlement
         }) do
      {:ok, _stopped} ->
        Logger.info(
          "closed never-started contact #{contact.realized_contact_id} " <>
            "(#{contact.mission_id}, #{reason})"
        )

      {:error, error} ->
        Logger.warning(
          "could not close never-started contact #{contact.realized_contact_id}: #{inspect(error)}"
        )
    end
  end

  # DECISIONS #71 sweep: an ended contact with no settler gets one (idempotent), so a failed
  # handoff or a lost settler is retried rather than leaving its runtime running.
  defp settle_realized_for_reconcile(%RealizedContact{} = realized_contact) do
    %{mission_id: mission_id, realized_contact_id: id} = realized_contact

    if ContactSettler.settling?(mission_id, id) do
      :skip
    else
      case ContactSettler.settle(realized_contact) do
        :ok ->
          {:ok, id}

        {:error, reason} ->
          {:error, reconcile_error(:realized_contact_settlement, realized_contact, reason)}
      end
    end
  end

  # #71 follow-up: a settled contact's journal stream leaves the disk after its retention, one
  # per tick, never while a replay runs (JournalReclaim). It must never break the reconcile.
  defp reclaim_journals(nil, _reference_time), do: :ok

  defp reclaim_journals(mission_id, reference_time) do
    if not ContactSettler.replaying?(mission_id),
      do: JournalReclaim.run(mission_id, Enum.max([reference_time, DateTime.utc_now()], DateTime))

    :ok
  rescue
    exception ->
      Logger.warning("journal reclaim failed for #{mission_id}: #{Exception.message(exception)}")
      :ok
  end

  # #71 follow-up: one replay per mission at a time, so a backlog of ended contacts drains in
  # turn and doesn't swamp the TSDB as it comes back.
  defp replay_candidates(nil, _reference_time), do: []

  defp replay_candidates(mission_id, reference_time) do
    if ContactSettler.replaying?(mission_id) do
      []
    else
      mission_id
      |> ContactSettlement.next_replay(
        Runtime.journaled_realized_contact_ids(mission_id),
        running_realized_contact_ids(mission_id),
        Enum.max([reference_time, DateTime.utc_now()], DateTime)
      )
      |> List.wrap()
    end
  end

  defp replay_realized_for_reconcile(%RealizedContact{} = realized_contact) do
    case ContactSettler.replay(realized_contact) do
      :ok ->
        {:ok, realized_contact.realized_contact_id}

      {:error, :replay_running} ->
        :skip

      {:error, reason} ->
        {:error, reconcile_error(:realized_contact_replay, realized_contact, reason)}
    end
  end

  defp running_realized_contact_ids(nil), do: []

  defp running_realized_contact_ids(mission_id),
    do: Runtime.running_realized_contact_ids(mission_id)

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
        _ = RealizationFailure.realized(scheduled_contact, reference_time)
        {:ok, realized_contact.realized_contact_id}

      {:error, :scheduled_contact_already_realized} ->
        :skip

      # U45 (lead 11-17, A): never silent. Recorded on the scheduled contact for contact_start.
      {:error, reason} ->
        _ = RealizationFailure.after_error(scheduled_contact, reason, reference_time)
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
             started_at: reference_time,
             started_by: @scheduler
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
             started_at: transition_time,
             started_by: @scheduler
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
         {:ok, pid} <- start_runtime(persisted_realized_contact),
         {:ok, _updated_realized_contact} <-
           ContactStore.update_realized_lifecycle(
             persisted_realized_contact,
             :active,
             persisted_realized_contact
             |> start_patch(metadata_patch)
             |> Map.merge(
               ContactStartFailure.started(persisted_realized_contact, DateTime.utc_now())
             )
           ) do
      :ok = ContactStartFailure.announce_started(persisted_realized_contact)
      {:ok, pid}
    end
  end

  # A contact already active keeps who started it (a release reaching a running pass isn't a start).
  defp start_patch(%RealizedContact{lifecycle_state: :active}, patch),
    do: Map.delete(patch, :started_by)

  defp start_patch(%RealizedContact{}, %{started_by: nil} = patch),
    do: Map.delete(patch, :started_by)

  defp start_patch(%RealizedContact{}, patch), do: patch

  # ux U45: a failed start is kept on the contact, so the reconcile retries it and Now shows it.
  defp start_runtime(%RealizedContact{} = realized_contact) do
    case Runtime.start_realized_contact(realized_contact) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        _recorded = ContactStartFailure.record(realized_contact, reason, DateTime.utc_now())
        {:error, reason}
    end
  end

  # DECISIONS #71: ending a contact records the end and hands its runtime to a settler; it never
  # waits for the runtime to drain (a TSDB outage would hold every caller, the scheduler too).
  defp stop_realized_transition(%RealizedContact{} = realized_contact, metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized(realized_contact),
         {:ok, %RealizedContact{} = stopped_realized_contact} <-
           mark_realized_stopped(persisted_realized_contact, metadata_patch),
         :ok <- ContactSettler.settle(stopped_realized_contact) do
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
    ContactStore.update_realized_lifecycle(
      realized_contact,
      :stopped,
      Map.merge(metadata_patch, ContactSettlement.settling(DateTime.utc_now()))
    )
  end

  defp complete_realized(%RealizedContact{} = realized_contact, metadata_patch) do
    with {:ok, %RealizedContact{} = persisted_realized_contact} <-
           ensure_persisted_realized(realized_contact),
         {:ok, %RealizedContact{} = completed_realized_contact} <-
           ContactStore.update_realized_lifecycle(
             persisted_realized_contact,
             :completed,
             Map.merge(metadata_patch, ContactSettlement.settling(DateTime.utc_now()))
           ),
         :ok <- ContactSettler.settle(completed_realized_contact) do
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
    # The caller's details (a provider's cause and reason, ux U56) are kept with the cancel.
    |> Map.merge(Keyword.get(opts, :metadata, %{}))
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
      metadata:
        Map.merge(
          %{canceled_during_execution?: not is_nil(scheduled_contact.realized_contact_id)},
          Keyword.get(opts, :metadata, %{})
        ),
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
