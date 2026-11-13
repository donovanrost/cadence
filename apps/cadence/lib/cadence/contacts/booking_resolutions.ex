defmodule Cadence.Contacts.BookingResolutions do
  @moduledoc """
  Operator resolution of unconfirmed bookings (DECISIONS #53) and the conflicts it can leave
  for acknowledgment (#54). Reads and acknowledgment are in `BookingResolutions.Attention`.

  `resolve/6` takes a booking whose provider hasn't answered past the confirmation window
  (#52). It always re-reads the provider first; a decisive answer settles the item and no
  operator claim is recorded beyond the audit row. Otherwise:

  - **Mark booked** (provider reference + note): the reservation stays at the provider's state
    but carries the operator's attestation, so its scheduled contact materializes with evidence
    `operator_attested`, and no `:command_window` until the provider itself confirms uplink.
    The item becomes `reserved`.
  - **Mark not booked** (note): Cadence sends the provider cancel first, then fails the item
    with `operator_not_booked`, which feeds repair like `booking_lost`.

  Later provider answers are checked by `provider_answered/1` (from `ProviderReservations`):
  an answer that contradicts the attestation, a late confirmation of a pass marked not booked,
  or a failed cancel raises a conflict on the resolution row; nothing is re-booked silently.
  """

  import Ecto.Query
  require Logger

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{ConfirmationWindow, ContactPlanExecutions}
  alias Cadence.Contacts.BookingResolutions.Row

  alias Cadence.Contacts.{
    LateUplink,
    ProviderBooking,
    ProviderReservation,
    ProviderReservationReconciler,
    ProviderReservations
  }

  alias Cadence.{Ids, Repo}
  alias Cadence.Platform.ScopedReadUpdates

  @marker "operator_resolution"
  @decisive ~w(confirmed active completed rejected failed canceled)a
  @materialized ~w(confirmed active completed)a
  @dead ~w(rejected failed canceled)a

  @doc "The reservation metadata key that marks an operator resolution."
  def marker, do: @marker

  @doc """
  Resolves one unconfirmed booking. `attrs`: `"note"` (required) and, for `:booked`,
  `"provider_reference"`. Options: `:now`, `:confirmation_window_ms`, `:reconcile` (fresh
  provider read), `:cancel` (provider cancel).
  """
  @spec resolve(Scope.t(), binary(), binary(), :booked | :not_booked, map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve(%Scope{} = scope, mission_id, item_id, action, attrs, opts \\ [])
      when action in [:booked, :not_booked] do
    org = scope.organization_id

    with {:ok, actor} <- authorize(scope),
         {:ok, input} <- input(action, attrs),
         {:ok, item} <- ContactPlanExecutions.fetch_item(org, mission_id, item_id),
         :ok <- unconfirmed(item, opts),
         {:ok, reservation} <-
           ProviderReservations.fetch(org, mission_id, item.provider_reservation_id) do
      {answer, reservation} = fresh_read(reservation, opts)
      row = row_attrs(item, reservation, action, input, actor, answer)

      result =
        if reservation.lifecycle_state in @decisive,
          do: settle_from_provider(item, reservation, row, opts),
          else: apply_action(action, item, reservation, row, opts)

      if match?({:ok, _}, result), do: changed(org, mission_id)
      result
    end
  end

  ## Provider answers after a resolution

  @doc """
  Called after a provider status is applied to a reservation. Only reservations carrying an
  operator resolution are checked. Never fails the caller.
  """
  @spec provider_answered(ProviderReservation.t()) :: :ok
  def provider_answered(%ProviderReservation{metadata: %{@marker => _}} = reservation) do
    case latest(reservation) do
      nil -> :ok
      row -> react(row, reservation)
    end
  rescue
    error ->
      Logger.warning("booking resolution check failed: #{Exception.message(error)}")
      :ok
  end

  def provider_answered(_reservation), do: :ok

  @doc """
  Called when a provider answer couldn't be applied because the reservation is already
  terminal, e.g. a confirmation of a booking Cadence canceled after 'Mark not booked'.
  """
  @spec provider_answer_refused(binary(), binary(), binary(), atom()) :: :ok
  def provider_answer_refused(org, mission, reservation_id, requested_state) do
    with true <- requested_state in @materialized,
         {:ok, %ProviderReservation{metadata: %{@marker => _}} = reservation} <-
           ProviderReservations.fetch(org, mission, reservation_id),
         %Row{outcome: "not_booked"} = row <- latest(reservation) do
      raise_conflict(row, "late_confirmation", %{
        "provider_state" => Atom.to_string(requested_state),
        "provider_message" => "provider confirmed a booking Cadence canceled"
      })
    end

    :ok
  rescue
    error ->
      Logger.warning("booking resolution check failed: #{Exception.message(error)}")
      :ok
  end

  ## Resolve steps

  defp authorize(%Scope{user: %{user_id: id, display_name: name}} = scope) do
    with :ok <-
           Policy.authorize(scope, :approve_contact_plans, %{
             organization_id: scope.organization_id
           }) do
      {:ok, %{"kind" => "user", "id" => id, "name" => name}}
    end
  end

  defp authorize(_scope), do: {:error, :forbidden}

  defp input(action, attrs) when is_map(attrs) do
    note = text(attrs["note"])
    reference = text(attrs["provider_reference"])

    cond do
      is_nil(note) ->
        {:error, {:invalid, %{note: "is required"}}}

      action == :booked and is_nil(reference) ->
        {:error, {:invalid, %{provider_reference: "is required"}}}

      true ->
        {:ok, %{note: note, provider_reference: if(action == :booked, do: reference)}}
    end
  end

  defp input(_action, _attrs), do: {:error, {:invalid, %{note: "is required"}}}

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 2_000)
    end
  end

  defp text(_value), do: nil

  defp unconfirmed(item, opts) do
    cond do
      ConfirmationWindow.overdue?(item, opts) -> :ok
      resolved = for_item(item) -> {:error, {:booking_already_resolved, resolved.actor_document}}
      true -> {:error, :booking_not_unconfirmed}
    end
  end

  defp for_item(item),
    do: Repo.get_by(Row, contact_plan_execution_item_id: item.contact_plan_execution_item_id)

  defp fresh_read(reservation, opts) do
    reconcile =
      Keyword.get(opts, :reconcile, &ProviderReservationReconciler.reconcile_reservation/1)

    read_at = DateTime.to_iso8601(DateTime.utc_now())

    case reconcile.(reservation) do
      {:ok, %ProviderReservation{} = updated} ->
        {%{"status" => Atom.to_string(updated.lifecycle_state), "read_at" => read_at}, updated}

      error ->
        {%{"error" => inspect(error_reason(error)), "read_at" => read_at}, refetch(reservation)}
    end
  end

  defp error_reason({:error, _reservation, reason}), do: reason
  defp error_reason({:error, reason}), do: reason
  defp error_reason(other), do: other

  defp refetch(reservation) do
    case ProviderReservations.fetch(
           reservation.organization_id,
           reservation.mission_id,
           reservation.provider_reservation_id
         ) do
      {:ok, current} -> current
      _missing -> reservation
    end
  end

  # The provider answered on the re-read: settle the item from that answer, record the audit
  # row, and claim nothing.
  defp settle_from_provider(item, reservation, row, opts) do
    Repo.transaction(fn ->
      {:ok, current} =
        ContactPlanExecutions.fetch_item(
          item.organization_id,
          item.mission_id,
          item.contact_plan_execution_item_id
        )

      with {:ok, settled} <- settle_item(current, reservation, opts),
           {:ok, _plan, _items} <- project(settled, opts),
           {:ok, inserted} <- insert(Map.put(row, :outcome, "provider_answered")) do
        %{outcome: :provider_answered, item: settled, resolution: inserted}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp settle_item(
         %{lifecycle_state: :uncertain} = item,
         %{lifecycle_state: :canceled} = r,
         opts
       ),
       do:
         ContactPlanExecutions.finish_item(
           item,
           :failed,
           r.provider_reservation_id,
           %{"code" => "provider_canceled"},
           opts
         )

  defp settle_item(%{lifecycle_state: :uncertain} = item, reservation, opts),
    do: ContactPlanExecutions.finish_with_reservation(item, reservation, opts)

  defp settle_item(item, _reservation, _opts), do: {:ok, item}

  defp apply_action(:booked, item, reservation, row, opts) do
    Repo.transaction(fn ->
      with {:ok, inserted} <- insert(Map.put(row, :outcome, "attested")),
           {:ok, _} <- ProviderReservations.attest_booking(reservation, marker_document(inserted)),
           {:ok, reserved} <-
             ContactPlanExecutions.finish_item(
               item,
               :reserved,
               reservation.provider_reservation_id,
               %{
                 "evidence" => "operator_attested",
                 "resolution_id" => inserted.booking_resolution_id,
                 "resolved_by" => Map.take(inserted.actor_document || %{}, ["kind", "id"]),
                 "resolved_at" => DateTime.to_iso8601(inserted.inserted_at)
               },
               opts
             ),
           {:ok, _plan, _items} <- project(reserved, opts) do
        %{outcome: :attested, item: reserved, resolution: inserted}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_action(:not_booked, item, reservation, row, opts) do
    with {:ok, inserted} <- Repo.transaction(fn -> record_not_booked(reservation, row) end) do
      cancel = Keyword.get(opts, :cancel, &ProviderBooking.cancel/3)

      canceled =
        cancel.(item.organization_id, item.mission_id, reservation.provider_reservation_id)

      finish_not_booked(item, inserted, canceled, opts)
    end
  end

  # The decision and the reservation marker are written before the provider cancel, so a
  # confirmation that races it is already caught as a conflict.
  defp record_not_booked(reservation, row) do
    with {:ok, inserted} <- insert(Map.put(row, :outcome, "not_booked")),
         {:ok, _} <-
           ProviderReservations.put_operator_resolution(reservation, marker_document(inserted)) do
      inserted
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp finish_not_booked(item, inserted, canceled, opts) do
    error = %{
      "code" => "operator_not_booked",
      "resolution_id" => inserted.booking_resolution_id,
      # ux U29 "by <name> at <time>".
      "resolved_by" => Map.take(inserted.actor_document || %{}, ["kind", "id"]),
      "resolved_at" => DateTime.to_iso8601(inserted.inserted_at)
    }

    Repo.transaction(fn ->
      with {:ok, current} <-
             ContactPlanExecutions.fetch_item(
               item.organization_id,
               item.mission_id,
               item.contact_plan_execution_item_id
             ),
           {:ok, failed} <-
             ContactPlanExecutions.finish_item(
               current,
               :failed,
               item.provider_reservation_id,
               error,
               opts
             ),
           {:ok, _plan, _items} <- project(failed, opts) do
        row = Repo.get!(Row, inserted.booking_resolution_id)
        row = cancel_conflict(row, canceled)
        %{outcome: :not_booked, item: failed, resolution: row}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp cancel_conflict(row, {:ok, _booking}), do: row

  defp cancel_conflict(row, error) do
    {:ok, row} =
      row
      |> Row.conflict_changeset(
        "cancel_failed",
        %{"provider_message" => inspect(error_reason(error))},
        DateTime.utc_now()
      )
      |> Repo.update()

    row
  end

  defp project(item, opts),
    do:
      ContactPlanExecutions.project_plan(
        item.organization_id,
        item.mission_id,
        item.contact_plan_id,
        item.contact_plan_version,
        opts
      )

  defp insert(attrs) do
    attrs
    |> Map.put(:booking_resolution_id, Ids.new("booking_resolution"))
    |> Row.changeset()
    |> Repo.insert()
    |> case do
      {:ok, row} ->
        {:ok, row}

      {:error, %Ecto.Changeset{errors: [contact_plan_execution_item_id: _]}} ->
        {:error, {:booking_already_resolved, nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp row_attrs(item, reservation, action, input, actor, answer) do
    %{
      organization_id: item.organization_id,
      mission_id: item.mission_id,
      contact_plan_id: item.contact_plan_id,
      contact_plan_version: item.contact_plan_version,
      contact_plan_execution_item_id: item.contact_plan_execution_item_id,
      provider_reservation_id: reservation.provider_reservation_id,
      provider_contact_ref: reservation.provider_contact_ref,
      scheduled_contact_id: reservation.scheduled_contact_id,
      spacecraft_id: reservation.spacecraft_id,
      ground_station_ref: station_ref(reservation),
      provider_id: reservation.provider_id,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      action: Atom.to_string(action),
      provider_reference: input.provider_reference,
      note: input.note,
      actor_document: actor,
      provider_answer_document: answer
    }
  end

  @doc false
  def station_ref(%ProviderReservation{} = reservation) do
    Enum.find_value(
      [
        reservation.provider_confirmed_snapshot_document,
        reservation.requested_snapshot_document,
        reservation.request_document
      ],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  defp marker_document(%Row{} = row) do
    %{
      "resolution_id" => row.booking_resolution_id,
      "action" => row.action,
      "provider_reference" => row.provider_reference,
      "actor" => row.actor_document,
      "at" => DateTime.to_iso8601(row.inserted_at)
    }
  end

  ## Reacting to provider answers

  defp latest(reservation) do
    Row
    |> where(
      [r],
      r.organization_id == ^reservation.organization_id and
        r.mission_id == ^reservation.mission_id and
        r.provider_reservation_id == ^reservation.provider_reservation_id
    )
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp react(%Row{outcome: "attested"} = row, %{lifecycle_state: state} = r) when state in @dead,
    do: raise_conflict(row, "contradicts_attestation", answer(r))

  defp react(%Row{outcome: "attested"} = row, %{lifecycle_state: state} = r)
       when state in @materialized do
    # #55: the provider's own confirmation may bring the uplink leg; revise before AOS.
    uplink =
      case LateUplink.revise(r) do
        {:ok, result} -> Atom.to_string(result)
        {:error, reason} -> "error: " <> inspect(reason)
      end

    close(row, r, Atom.to_string(state), %{"uplink" => uplink})
  end

  defp react(%Row{outcome: "not_booked"} = row, %{lifecycle_state: state} = r)
       when state in @materialized,
       do: raise_conflict(row, "late_confirmation", answer(r))

  defp react(
         %Row{outcome: "not_booked", conflict: "cancel_failed"} = row,
         %{lifecycle_state: :canceled} = r
       ),
       do: close(row, r, "canceled")

  defp react(_row, _reservation), do: :ok

  defp answer(reservation) do
    %{
      "provider_state" => Atom.to_string(reservation.lifecycle_state),
      "provider_message" => provider_message(reservation)
    }
  end

  defp provider_message(reservation) do
    snapshot = reservation.provider_confirmed_snapshot_document || %{}
    error = reservation.last_error_document || %{}

    snapshot["status_reason"] || error["detail"] || error["message"] ||
      reservation.provider_status
  end

  defp raise_conflict(row, conflict, document) do
    {:ok, _row} =
      row |> Row.conflict_changeset(conflict, document, DateTime.utc_now()) |> Repo.update()

    changed(row.organization_id, row.mission_id)
  end

  # A provider answer that agrees with the resolution closes an open conflict, or just
  # records the answer.
  defp close(row, reservation, action, extra \\ %{}) do
    attrs =
      if row.conflict_state in ["open", "acknowledged"],
        do: %{
          conflict_state: "resolved",
          conflict_resolved_at: DateTime.utc_now(),
          conflict_resolved_by: %{"kind" => "provider", "id" => reservation.provider_id},
          conflict_resolution_action: action
        },
        else: %{}

    {:ok, _row} =
      row
      |> Row.state_changeset(
        Map.put(attrs, :provider_answer_document, Map.merge(answer(reservation), extra))
      )
      |> Repo.update()

    changed(row.organization_id, row.mission_id)
  end

  @doc false
  def changed(org, mission) do
    ScopedReadUpdates.publish(:attention_changed, org, mission)
    :ok
  end
end
