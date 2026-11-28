defmodule Cadence.Contacts.ProviderReservationChanges do
  @moduledoc "Provider Contact change ledger, policy classification, and atomic application."

  import Ecto.Query

  require Logger

  alias Cadence.Contacts.ContactAction
  alias Cadence.Contacts.ContactStore
  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.ProviderChangeApproval
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Contacts.ProviderReservationChange
  alias Cadence.Contacts.ScheduledContactRevision
  alias Cadence.Contacts.ScheduledContactRevisions

  alias Cadence.GroundNetworks.{
    DeliveryPolicy,
    DeliveryPolicyEvaluator,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAudit,
    ProviderAuditEntry,
    Validation
  }

  alias Cadence.Persistence.JsonDocument

  alias Cadence.Control.Contacts.Store.{
    ProviderChangeApprovalRow,
    ProviderReservationChangeRow,
    ProviderReservationRow,
    ScheduledContactRevisionRow
  }

  alias Cadence.Repo

  @pending_states ~w(pending_approval acknowledgment_required policy_accepted)
  # Who moved a contact's window when the provider's change took effect without an approval.
  @window_actor %{"kind" => "system", "id" => "provider_change_observer"}
  @snapshot_fields ~w(
    provider_contact_ref provider_revision client_reference opportunity_ref spacecraft_ref
    ground_station_ref antenna_or_service_pool_ref service_profile_ref delivery_profile_ref
    starts_at ends_at status pass_phase delivery_state delivery_descriptor status_reason extensions
    uplink
  )

  @spec observe(ProviderReservation.t(), map(), keyword()) ::
          {:ok, ProviderReservationChange.t() | nil, ProviderReservation.t()} | {:error, term()}
  def observe(%ProviderReservation{} = reservation, response, opts \\ []) when is_map(response) do
    current = snapshot(response, reservation)
    provider_revision = current["provider_revision"]

    cond do
      not is_integer(provider_revision) or provider_revision <= 0 ->
        {:error, {:malformed_provider_response, :provider_revision}}

      provider_revision < reservation.provider_revision ->
        {:ok, nil, reservation}

      provider_revision == reservation.provider_revision ->
        {:ok, nil, reservation}

      true ->
        observe_advanced_revision(reservation, current, opts)
    end
  end

  @spec fetch(binary(), binary()) ::
          {:ok, ProviderReservationChange.t()} | {:error, :provider_reservation_change_not_found}
  def fetch(organization_id, provider_reservation_change_id) do
    case Repo.get_by(ProviderReservationChangeRow,
           organization_id: organization_id,
           provider_reservation_change_id: provider_reservation_change_id
         ) do
      nil -> {:error, :provider_reservation_change_not_found}
      row -> {:ok, ProviderReservationChangeRow.to_domain(row)}
    end
  end

  @spec list_for_reservation(binary(), binary()) :: [ProviderReservationChange.t()]
  def list_for_reservation(organization_id, provider_reservation_id) do
    ProviderReservationChangeRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_reservation_id == ^provider_reservation_id
    )
    |> order_by([row], asc: row.provider_revision, asc: row.inserted_at)
    |> Repo.all()
    |> Enum.map(&ProviderReservationChangeRow.to_domain/1)
  end

  @doc false
  @spec apply(binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def apply(organization_id, change_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(change_id) and is_map(actor) do
    allowed_states = Keyword.get(opts, :allowed_states, [:policy_accepted, :pending_approval])
    decision_state = Keyword.get(opts, :decision_state, :approved)
    expected_hash = Keyword.get(opts, :proposal_hash)
    now = now(opts)

    Repo.transaction(fn ->
      with {:ok, change_row} <- lock_change(organization_id, change_id),
           :ok <- require_state(change_row, allowed_states),
           :ok <- require_hash(change_row, expected_hash),
           :ok <- maybe_require_decision_deadline(change_row, opts),
           {:ok, reservation_row} <- lock_reservation(change_row),
           :ok <- maybe_require_pass_open(reservation_row, now, opts),
           :ok <- require_current_revision(change_row, reservation_row),
           :ok <- require_current_policy(change_row, reservation_row),
           :ok <- require_active_grant(reservation_row),
           {:ok, contact_row} <- lock_scheduled_contact(reservation_row),
           :ok <- require_pre_realization(contact_row),
           {:ok, approval_row} <- maybe_insert_approval(Keyword.get(opts, :approval)),
           {:ok, updated_contact_row} <- update_contact(contact_row, change_row),
           {:ok, revision_row} <- append_revision(updated_contact_row, change_row, actor, now),
           :ok <- maybe_inject_failure(opts),
           {:ok, updated_reservation_row} <- accept_snapshot(reservation_row, change_row),
           {:ok, updated_change_row} <-
             decide_change(change_row, decision_state, actor, now, %{
               "scheduled_contact_revision" => revision_row.revision
             }),
           {:ok, audit_row} <-
             append_audit(updated_change_row, updated_reservation_row, actor, now) do
        %{
          change: ProviderReservationChangeRow.to_domain(updated_change_row),
          scheduled_contact: ScheduledContactRow.to_domain(updated_contact_row),
          scheduled_contact_revision: ScheduledContactRevisionRow.to_domain(revision_row),
          provider_reservation: ProviderReservationRow.to_domain(updated_reservation_row),
          provider_change_approval:
            approval_row && ProviderChangeApprovalRow.to_domain(approval_row),
          provider_audit_entry_id: audit_row.provider_audit_entry_id
        }
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  def decide_without_application(
        change_id,
        organization_id,
        state,
        actor,
        decision_patch,
        opts \\ []
      ) do
    now = now(opts)

    Repo.transaction(fn ->
      with {:ok, row} <- lock_change(organization_id, change_id),
           :ok <- require_hash(row, Keyword.get(opts, :proposal_hash)),
           :ok <- require_state(row, Keyword.fetch!(opts, :allowed_states)),
           {:ok, reservation} <- lock_reservation(row),
           :ok <- maybe_require_pass_open(reservation, now, opts),
           :ok <- maybe_require_actionable(row, opts),
           {:ok, _approval_row} <- maybe_insert_approval(Keyword.get(opts, :approval)),
           {:ok, updated} <- decide_change(row, state, actor, now, decision_patch),
           {:ok, _audit} <- append_audit(updated, reservation, actor, now) do
        ProviderReservationChangeRow.to_domain(updated)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, change} -> {:ok, change}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec snapshot(map(), ProviderReservation.t()) :: map()
  def snapshot(response, reservation) do
    response = Validation.sanitize(response)
    previous = reservation.provider_confirmed_snapshot_document

    %{
      "provider_contact_ref" =>
        first_truthy([
          response["provider_contact_ref"],
          response["id"],
          previous["provider_contact_ref"],
          reservation.provider_contact_ref
        ]),
      "provider_revision" =>
        first_truthy([
          response["provider_revision"],
          response["revision"],
          reservation.provider_revision
        ]),
      "client_reference" =>
        snapshot_value(response, previous, "client_reference", reservation.idempotency_key),
      "opportunity_ref" =>
        snapshot_value(
          response,
          previous,
          "opportunity_ref",
          reservation.provider_opportunity_ref
        ),
      "spacecraft_ref" =>
        snapshot_value(
          response,
          previous,
          "spacecraft_ref",
          reservation.provider_spacecraft_ref
        ),
      "ground_station_ref" => present(response, previous, "ground_station_ref"),
      "antenna_or_service_pool_ref" => present(response, previous, "antenna_or_service_pool_ref"),
      "service_profile_ref" =>
        snapshot_value(
          response,
          previous,
          "service_profile_ref",
          reservation.service_profile_ref["id"]
        ),
      "delivery_profile_ref" =>
        snapshot_value(
          response,
          previous,
          "delivery_profile_ref",
          reservation.delivery_profile_ref["id"]
        ),
      "starts_at" =>
        snapshot_value(
          response,
          previous,
          "starts_at",
          DateTime.to_iso8601(reservation.starts_at)
        ),
      "ends_at" =>
        snapshot_value(
          response,
          previous,
          "ends_at",
          DateTime.to_iso8601(reservation.ends_at)
        ),
      "status" =>
        snapshot_value(
          response,
          previous,
          "status",
          Atom.to_string(reservation.lifecycle_state)
        ),
      "pass_phase" =>
        snapshot_value(
          response,
          previous,
          "pass_phase",
          Atom.to_string(reservation.pass_phase)
        ),
      "delivery_state" =>
        snapshot_value(
          response,
          previous,
          "delivery_state",
          Atom.to_string(reservation.delivery_state)
        ),
      "delivery_descriptor" =>
        snapshot_value(
          response,
          previous,
          "delivery_descriptor",
          reservation.delivery_descriptor_document
        ),
      "status_reason" => present(response, previous, "status_reason"),
      "extensions" => snapshot_value(response, previous, "extensions", %{})
    }
    |> put_uplink(present(response, previous, "uplink"))
    |> Map.take(@snapshot_fields)
    |> JsonDocument.encode()
  end

  defp observe_advanced_revision(reservation, current, opts) do
    before = reservation.provider_confirmed_snapshot_document

    with {:ok, provider} <-
           MissionProviders.fetch_provider_version(
             reservation.organization_id,
             reservation.mission_id,
             reservation.provider_id,
             reservation.provider_version
           ),
         {:ok, policy} <- DeliveryPolicy.normalize(provider.delivery_policy_document),
         decision =
           DeliveryPolicyEvaluator.evaluate(policy, before, current,
             already_effective?: Keyword.get(opts, :already_effective?, false)
           ),
         change = build_change(reservation, before, current, policy, decision, opts),
         {:ok, persisted, updated_reservation} <- persist_observation(change, reservation) do
      maybe_apply_policy(persisted, updated_reservation, opts)
    end
  rescue
    error in [ArgumentError, KeyError] -> {:error, {:invalid_provider_change, error.message}}
  end

  defp build_change(reservation, before, current, policy, decision, opts) do
    proposal_hash = hash(%{"before" => before, "after" => current})
    provider_revision = current["provider_revision"]

    ProviderReservationChange.new(%{
      organization_id: reservation.organization_id,
      mission_id: reservation.mission_id,
      provider_reservation_id: reservation.provider_reservation_id,
      provider_account_id: reservation.provider_account_id,
      provider_account_version: reservation.provider_account_version,
      provider_revision: provider_revision,
      from_provider_revision: reservation.provider_revision,
      change_identity:
        hash(%{
          "provider_reservation_id" => reservation.provider_reservation_id,
          "provider_revision" => provider_revision,
          "proposal_hash" => proposal_hash
        }),
      proposal_hash: proposal_hash,
      before_snapshot_document: before,
      after_snapshot_document: current,
      changed_fields_document: changed_fields(before, current, decision.changed_fields),
      classification: decision.decision,
      lifecycle_state: initial_state(decision.decision),
      policy_version: policy.version,
      policy_document: DeliveryPolicy.to_document(policy),
      decision_document: decision,
      actionable: actionable?(decision.decision, current),
      already_effective: decision.decision == :acknowledgment_required,
      deadline_at: deadline_at(current),
      provider_evidence_id: Keyword.get(opts, :provider_evidence_id)
    })
  end

  defp persist_observation(change, reservation) do
    Repo.transaction(fn ->
      query =
        from(row in ProviderReservationRow,
          where:
            row.organization_id == ^reservation.organization_id and
              row.provider_reservation_id == ^reservation.provider_reservation_id,
          lock: "FOR UPDATE"
        )

      row = Repo.one!(query)

      cond do
        row.provider_revision == change.provider_revision ->
          existing =
            Repo.get_by!(ProviderReservationChangeRow,
              provider_reservation_id: change.provider_reservation_id,
              change_identity: change.change_identity
            )

          {existing, row, nil}

        row.provider_revision != change.from_provider_revision ->
          Repo.rollback(:provider_change_revision_superseded)

        true ->
          supersede_pending(row.provider_reservation_id, change.provider_revision)

          persisted =
            change
            |> ProviderReservationChangeRow.changeset()
            |> Repo.insert!()

          updated =
            row
            |> ProviderReservationRow.transition_changeset(reservation_transition_attrs(change))
            |> Repo.update!()

          {persisted, updated, align_contact_window(change, updated, persisted)}
      end
    end)
    |> case do
      {:ok, {change_row, reservation_row, moved}} ->
        # After the commit: the move's timeline event, then the scheduler re-plans start and stop
        # on the new window.
        if moved, do: announce_window_move(moved, reservation_row)

        {:ok, ProviderReservationChangeRow.to_domain(change_row),
         ProviderReservationRow.to_domain(reservation_row)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_apply_policy(%{classification: :policy_accept} = change, reservation, opts) do
    actor = %{"kind" => "system", "id" => "delivery_policy_evaluator"}

    case apply(reservation.organization_id, change.provider_reservation_change_id, actor,
           allowed_states: [:policy_accepted],
           decision_state: :policy_accepted,
           proposal_hash: change.proposal_hash,
           now: now(opts),
           fail_before_commit?: Keyword.get(opts, :fail_before_commit?, false)
         ) do
      {:ok, result} -> {:ok, result.change, result.provider_reservation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_apply_policy(change, reservation, _opts), do: {:ok, change, reservation}

  # Window truth (director 11-14): an observed change, or one the provider already made effective
  # (acknowledgment_required), moves the reservation's accepted window above, and the pass's
  # scheduled contact follows in the same transaction. Its window drives the runtime's start and
  # stop and the release gate (CommandWindow). Until 11-14 only an approved change moved the
  # contact (apply/4), so an effective shift left the runtime on the old window (003's 12:10:57Z
  # pass closed its listener 30 s before the provider's LOS). A running contact moves too: its
  # end is read live, so the scheduler stops it at the new LOS. An ended or canceled contact
  # stays as it is.
  defp align_contact_window(%{lifecycle_state: state}, reservation_row, change_row)
       when state in [:observed, :acknowledgment_required] do
    with {:ok, contact_row} <- lock_scheduled_contact(reservation_row),
         true <- contact_row.lifecycle_state in ["scheduled", "realized"],
         {:ok, window} <- snapshot_window(change_row),
         false <- same_window?({contact_row.starts_at, contact_row.ends_at}, window),
         {:ok, updated} <- update_contact(contact_row, change_row),
         {:ok, revision} <-
           append_revision(updated, change_row, @window_actor, DateTime.utc_now(), %{
             "before" => window_document({contact_row.starts_at, contact_row.ends_at}),
             "after" => window_document(window)
           }) do
      %{
        contact: ScheduledContactRow.to_domain(updated),
        before: {contact_row.starts_at, contact_row.ends_at},
        after: window,
        revision: revision.revision,
        change_row: change_row
      }
    else
      {:error, :scheduled_contact_not_found} -> nil
      already_aligned_or_closed when is_boolean(already_aligned_or_closed) -> nil
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp align_contact_window(_change, _reservation_row, _change_row), do: nil

  # The move's mission event (api, ux U56): one per move, subject the scheduled contact. Its id is
  # the contact's revision, so a retry records it once.
  defp announce_window_move(moved, reservation_row) do
    %{contact: contact, before: {from_start, from_end}, after: {to_start, to_end}} = moved
    snapshot = JsonDocument.unwrap_value(moved.change_row.after_snapshot_document)

    action =
      ContactAction.new(%{
        contact_action_id:
          "contact_window_moved:#{contact.scheduled_contact_id}:#{moved.revision}",
        organization_id: contact.organization_id,
        mission_id: contact.mission_id,
        scheduled_contact_id: contact.scheduled_contact_id,
        realized_contact_id: nil,
        action_kind: :contact_window_moved,
        actor: @window_actor,
        occurred_at: DateTime.utc_now(),
        metadata: %{
          "scheduled_contact_id" => contact.scheduled_contact_id,
          "provider_reservation_id" => reservation_row.provider_reservation_id,
          "provider_reservation_change_id" => moved.change_row.provider_reservation_change_id,
          "spacecraft_id" => reservation_row.spacecraft_id,
          "ground_station_ref" => snapshot["ground_station_ref"],
          "provider_id" => reservation_row.provider_id,
          # The sentence names the provider ('by Northlight'); nil reads 'by the provider'.
          "provider_name" => provider_name(reservation_row),
          "classification" => to_string(moved.change_row.classification),
          "before" => window_document({from_start, from_end}),
          "after" => window_document({to_start, to_end}),
          "start_delta_s" => DateTime.diff(to_start, from_start),
          "end_delta_s" => DateTime.diff(to_end, from_end)
        }
      })

    case ContactStore.persist_action(action) do
      {:ok, _action} -> :ok
      {:error, reason} -> Logger.warning("contact_window_moved not recorded: #{inspect(reason)}")
    end

    ContactStore.notify_contact_changed(contact)
  end

  defp provider_name(reservation_row) do
    case MissionProviders.fetch_provider_version(
           reservation_row.organization_id,
           reservation_row.mission_id,
           reservation_row.provider_id,
           reservation_row.provider_version
         ) do
      {:ok, provider} -> provider.display_name
      {:error, _not_found} -> nil
    end
  end

  defp snapshot_window(change_row) do
    snapshot = JsonDocument.unwrap_value(change_row.after_snapshot_document)

    with {:ok, starts_at} <- datetime(snapshot["starts_at"], :starts_at),
         {:ok, ends_at} <- datetime(snapshot["ends_at"], :ends_at),
         do: {:ok, {starts_at, ends_at}}
  end

  defp same_window?({starts_at, ends_at}, {to_starts_at, to_ends_at}),
    do:
      DateTime.compare(starts_at, to_starts_at) == :eq and
        DateTime.compare(ends_at, to_ends_at) == :eq

  defp window_document({starts_at, ends_at}),
    do: %{
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at)
    }

  defp reservation_transition_attrs(change) do
    attrs = %{
      provider_revision: change.provider_revision,
      provider_confirmed_snapshot_document:
        JsonDocument.wrap_value(change.after_snapshot_document)
    }

    if change.lifecycle_state in [:observed, :acknowledgment_required] do
      Map.put(
        attrs,
        :cadence_accepted_snapshot_document,
        JsonDocument.wrap_value(change.after_snapshot_document)
      )
    else
      attrs
    end
  end

  defp lock_change(organization_id, change_id) do
    ProviderReservationChangeRow
    |> where(
      [row],
      row.organization_id == ^organization_id and
        row.provider_reservation_change_id == ^change_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_reservation_change_not_found}
      row -> {:ok, row}
    end
  end

  defp lock_reservation(change_row) do
    ProviderReservationRow
    |> where(
      [row],
      row.organization_id == ^change_row.organization_id and
        row.provider_reservation_id == ^change_row.provider_reservation_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_reservation_not_found}
      row -> {:ok, row}
    end
  end

  defp lock_scheduled_contact(reservation_row) do
    ScheduledContactRow
    |> where(
      [row],
      row.organization_id == ^reservation_row.organization_id and
        row.mission_id == ^reservation_row.mission_id and
        row.scheduled_contact_id == ^reservation_row.scheduled_contact_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> case do
      nil -> {:error, :scheduled_contact_not_found}
      row -> {:ok, row}
    end
  end

  defp require_state(row, allowed_states) do
    if row.lifecycle_state in Enum.map(allowed_states, &Atom.to_string/1),
      do: :ok,
      else: {:error, {:provider_change_not_decidable, row.lifecycle_state}}
  end

  defp require_hash(_row, nil), do: :ok

  defp require_hash(row, expected_hash) do
    if row.proposal_hash == expected_hash,
      do: :ok,
      else: {:error, :stale_provider_change_proposal}
  end

  defp require_current_revision(change, reservation) do
    if reservation.provider_revision == change.provider_revision,
      do: :ok,
      else: {:error, :provider_change_revision_superseded}
  end

  defp require_current_policy(change, reservation) do
    case MissionProviders.fetch_provider_version(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_id,
           reservation.provider_version
         ) do
      {:error, :mission_provider_not_found} ->
        {:error, :mission_provider_not_found}

      {:ok, provider} ->
        with {:ok, policy} <-
               DeliveryPolicy.normalize(provider.delivery_policy_document),
             true <- policy.version == change.policy_version,
             true <-
               DeliveryPolicy.to_document(policy) ==
                 JsonDocument.unwrap_value(change.policy_document) do
          :ok
        else
          false -> {:error, :provider_change_policy_superseded}
          {:error, reason} -> {:error, {:invalid_delivery_policy, reason}}
        end
    end
  end

  defp require_active_grant(%ProviderReservationRow{provider_account_grant_id: nil}), do: :ok

  defp require_active_grant(reservation) do
    case ProviderAccountGrants.validate_binding(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_account_id,
           reservation.provider_account_version,
           reservation.provider_account_grant_id,
           reservation.provider_account_grant_version
         ) do
      {:ok, _grant} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # L14 (lead, ux U44): a change pending approval can't be decided once its pass has ended; it
  # expired. Acknowledging what a provider already did stays possible.
  defp maybe_require_pass_open(reservation_row, now, opts) do
    if Keyword.get(opts, :refuse_after_pass_end?, false) and pass_ended?(reservation_row, now),
      do: {:error, :provider_change_expired},
      else: :ok
  end

  @doc "Whether a reservation's pass has ended at `now` (L14's expiry rule: its ends_at)."
  def pass_ended?(%{ends_at: %DateTime{} = ends_at}, %DateTime{} = now),
    do: DateTime.compare(ends_at, now) != :gt

  def pass_ended?(_reservation, _now), do: false

  defp require_pre_realization(%ScheduledContactRow{
         lifecycle_state: "scheduled",
         realized_contact_id: nil
       }),
       do: :ok

  defp require_pre_realization(_row), do: {:error, :scheduled_contact_realization_started}

  defp maybe_require_actionable(row, opts) do
    cond do
      not Keyword.get(opts, :require_actionable?, false) ->
        :ok

      not row.actionable ->
        {:error, :provider_change_not_rejectable}

      match?(%DateTime{}, row.deadline_at) and
          DateTime.compare(row.deadline_at, now(opts)) != :gt ->
        {:error, :provider_change_decision_deadline_passed}

      true ->
        :ok
    end
  end

  defp maybe_require_decision_deadline(row, opts) do
    if Keyword.get(opts, :require_current_deadline?, false) and
         match?(%DateTime{}, row.deadline_at) and
         DateTime.compare(row.deadline_at, now(opts)) != :gt,
       do: {:error, :provider_change_decision_deadline_passed},
       else: :ok
  end

  defp maybe_insert_approval(nil), do: {:ok, nil}

  defp maybe_insert_approval(%ProviderChangeApproval{} = approval) do
    approval
    |> ProviderChangeApprovalRow.changeset()
    |> Repo.insert()
  end

  defp update_contact(row, change) do
    after_snapshot = JsonDocument.unwrap_value(change.after_snapshot_document)

    with {:ok, starts_at} <- datetime(after_snapshot["starts_at"], :starts_at),
         {:ok, ends_at} <- datetime(after_snapshot["ends_at"], :ends_at) do
      metadata =
        row.metadata
        |> JsonDocument.unwrap_value()
        |> Map.put("provider_execution", %{
          "ground_station_ref" => after_snapshot["ground_station_ref"],
          "antenna_or_service_pool_ref" => after_snapshot["antenna_or_service_pool_ref"],
          "estimated_capacity" => get_in(after_snapshot, ["extensions", "estimated_capacity"]),
          "cost" => get_in(after_snapshot, ["extensions", "cost"]),
          "provider_revision" => change.provider_revision
        })

      row
      |> ScheduledContactRow.revision_changeset(%{
        starts_at: starts_at,
        ends_at: ends_at,
        provider_contact_ref: after_snapshot["provider_contact_ref"],
        current_revision: row.current_revision + 1,
        metadata: JsonDocument.wrap_value(metadata)
      })
      |> Repo.update()
    end
  end

  defp append_revision(contact_row, change, actor, now, reason \\ %{}) do
    contact = ScheduledContactRow.to_domain(contact_row)

    revision =
      ScheduledContactRevision.new(%{
        organization_id: contact.organization_id,
        mission_id: contact.mission_id,
        scheduled_contact_id: contact.scheduled_contact_id,
        revision: contact.current_revision,
        provider_reservation_change_id: change.provider_reservation_change_id,
        snapshot_document: ScheduledContactRevisions.snapshot(contact),
        reason_document:
          Map.merge(
            %{
              "kind" => "provider_change",
              "classification" => change.classification,
              "proposal_hash" => change.proposal_hash,
              "provider_revision" => change.provider_revision
            },
            reason
          ),
        created_by: actor["id"] || actor[:id] || "cadence",
        created_at: now
      })

    revision
    |> ScheduledContactRevisionRow.changeset()
    |> Repo.insert()
  end

  defp accept_snapshot(reservation_row, change) do
    reservation_row
    |> ProviderReservationRow.transition_changeset(%{
      cadence_accepted_snapshot_document: change.after_snapshot_document
    })
    |> Repo.update()
  end

  defp decide_change(row, state, actor, now, patch) do
    current = JsonDocument.unwrap_value(row.decision_document)

    row
    |> ProviderReservationChangeRow.decision_changeset(%{
      lifecycle_state: Atom.to_string(state),
      decision_document:
        current
        |> Map.merge(JsonDocument.encode(patch))
        |> Map.put("decided_at", DateTime.to_iso8601(now))
        |> Map.put("decided_by", actor["id"] || actor[:id]),
      decided_at: now,
      decided_by: actor["id"] || actor[:id]
    })
    |> Repo.update()
  end

  defp append_audit(change, reservation, actor, now) do
    entry =
      ProviderAuditEntry.new(%{
        organization_id: change.organization_id,
        mission_id: change.mission_id,
        provider_account_id: reservation.provider_account_id,
        provider_account_grant_id: reservation.provider_account_grant_id,
        provider_id: reservation.provider_id,
        provider_reservation_id: reservation.provider_reservation_id,
        provider_change_id: change.provider_reservation_change_id,
        contact_id: reservation.provider_contact_ref,
        scheduled_contact_id: reservation.scheduled_contact_id,
        action: "provider_change.#{change.lifecycle_state}",
        outcome: change.lifecycle_state,
        recorded_at: now,
        actor_document: actor,
        previous_document: JsonDocument.unwrap_value(change.before_snapshot_document),
        current_document: JsonDocument.unwrap_value(change.after_snapshot_document),
        decision_document: JsonDocument.unwrap_value(change.decision_document),
        policy_document: JsonDocument.unwrap_value(change.policy_document)
      })

    ProviderAudit.append(entry)
  end

  defp supersede_pending(reservation_id, incoming_revision) do
    from(row in ProviderReservationChangeRow,
      where:
        row.provider_reservation_id == ^reservation_id and row.lifecycle_state in ^@pending_states
    )
    |> Repo.update_all(
      set: [
        lifecycle_state: "superseded",
        decided_at: DateTime.utc_now(),
        decided_by: "provider_revision:#{incoming_revision}",
        updated_at: DateTime.utc_now()
      ]
    )
  end

  defp initial_state(:observation), do: :observed
  defp initial_state(:policy_accept), do: :policy_accepted
  defp initial_state(:approval_required), do: :pending_approval
  defp initial_state(:acknowledgment_required), do: :acknowledgment_required
  defp initial_state(:configuration_failure), do: :configuration_failure

  defp actionable?(decision, current) when decision in [:approval_required, :policy_accept] do
    not provider_change_effective?(current) and
      get_in(current, ["extensions", "provider_change", "rejectable"]) != false
  end

  defp actionable?(_decision, _current), do: false

  defp provider_change_effective?(current),
    do: get_in(current, ["extensions", "provider_change", "effective"]) == true

  defp changed_fields(before, current, fields) do
    Map.new(fields, fn field ->
      {field, %{"before" => before[field], "after" => current[field]}}
    end)
  end

  defp deadline_at(current) do
    value = get_in(current, ["extensions", "provider_change", "deadline_at"])

    case DateTime.from_iso8601(value || "") do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  # Only a booked uplink leg (#44) adds the key: snapshots without one must stay identical to
  # those stored before uplink legs existed, or every reservation reads as provider-changed.
  defp put_uplink(snapshot, nil), do: snapshot
  defp put_uplink(snapshot, uplink), do: Map.put(snapshot, "uplink", uplink)

  defp present(response, previous, key) do
    if Map.has_key?(response, key), do: response[key], else: previous[key]
  end

  defp snapshot_value(response, previous, key, fallback) do
    first_truthy([response[key], previous[key], fallback])
  end

  defp first_truthy(values), do: Enum.find(values, & &1)

  defp datetime(value, field) do
    case DateTime.from_iso8601(value || "") do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, {:provider_change_missing_or_invalid, field}}
    end
  end

  defp maybe_inject_failure(opts) do
    if Keyword.get(opts, :fail_before_commit?, false),
      do: {:error, :injected_provider_change_apply_failure},
      else: :ok
  end

  defp hash(value) do
    value
    |> canonical()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical(item)} end)
    |> Enum.sort()
  end

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value), do: value

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
