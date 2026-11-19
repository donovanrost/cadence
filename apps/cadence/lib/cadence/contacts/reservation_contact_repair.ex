defmodule Cadence.Contacts.ReservationContactRepair do
  @moduledoc """
  Finds, and with `apply: true` releases, contacts left open for reservations that won't fly
  (director 11-14). A reservation failed by a recorded provider error (a delivery descriptor that
  conflicted with its transport, for one) used to keep its contact 'scheduled', and that contact
  opened a listener for a pass no provider flew.

  A finding is a reservation the provider no longer holds (`ProviderReservations.lost?/1`) whose
  pass hasn't ended and whose contact is still 'scheduled', or realized but not started
  (action "cancel"). Applying runs the release the poll runs (`ProviderReservations.release_lost/1`):
  the code path, never a hand edit. A contact already running is left to its LOS.

  A failure from Cadence's own checks is not lost (the provider may still fly the pass, director
  11-14): it's listed as action "recheck" for visibility and never released. The reconciler polls
  it until its pass ends, and the provider's next answer can return it to the provider's state.
  qa runs it without `apply` first and sends the list for review.
  """

  import Ecto.Query

  require Logger

  alias Cadence.Contacts
  alias Cadence.Contacts.{ContactStore, ProviderReservations, RealizedContact, ScheduledContact}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @lost_states ~w(failed canceled rejected)

  @spec run(binary(), binary(), keyword()) :: {:ok, [map()]}
  def run(organization_id, mission_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    findings = findings(organization_id, mission_id, now)
    rechecks = organization_id |> provisional_failures(mission_id, now) |> Enum.map(&recheck/1)

    if Keyword.get(opts, :apply, false),
      do: {:ok, Enum.map(findings, &apply_one/1) ++ rechecks},
      else: {:ok, Enum.map(findings, &describe/1) ++ rechecks}
  end

  # Cadence-side failures the reconciler still polls (ProviderReservations.cadence_side_failure?/1).
  defp provisional_failures(organization_id, mission_id, now) do
    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^organization_id and row.lifecycle_state == "failed" and
          row.ends_at > ^now,
      order_by: [asc: row.starts_at]
    )
    |> maybe_mission(mission_id)
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
    |> Enum.filter(&ProviderReservations.cadence_side_failure?/1)
  end

  defp recheck(reservation) do
    %{
      provider_reservation_id: reservation.provider_reservation_id,
      reservation_state: "failed",
      spacecraft_id: reservation.spacecraft_id,
      scheduled_contact_id: reservation.scheduled_contact_id,
      contact_state: nil,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      action: "recheck",
      source: reservation.last_error_document["source"],
      reason: reservation.last_error_document["reason"]
    }
  end

  @doc """
  The reconciler's re-check each cycle (api-ops' review): releases any lost reservation's open
  contact in the organization (or one mission), so a release that failed after its transition
  committed is retried. Logs what it releases; never raises.
  """
  @spec sweep(binary(), keyword()) :: :ok
  def sweep(organization_id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    organization_id
    |> findings(Keyword.get(opts, :mission_id), now)
    |> Enum.each(fn finding ->
      result = apply_one(finding)
      Logger.info("released the open contact of lost reservation: #{inspect(result)}")
    end)
  rescue
    exception ->
      Logger.warning("lost-reservation contact sweep failed: #{Exception.message(exception)}")
      :ok
  end

  defp findings(organization_id, mission_id, now) do
    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^organization_id and row.lifecycle_state in @lost_states and
          row.ends_at > ^now,
      order_by: [asc: row.starts_at]
    )
    |> maybe_mission(mission_id)
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
    |> Enum.filter(&ProviderReservations.lost?/1)
    |> Enum.flat_map(fn reservation ->
      case open_contact(reservation) do
        {:open, contact_state} -> [{reservation, contact_state}]
        :closed -> []
      end
    end)
  end

  defp maybe_mission(query, nil), do: query
  defp maybe_mission(query, mission_id), do: where(query, [row], row.mission_id == ^mission_id)

  defp open_contact(%{scheduled_contact_id: nil}), do: :closed

  defp open_contact(reservation) do
    case Contacts.fetch_scheduled_contact(
           reservation.organization_id,
           reservation.mission_id,
           reservation.scheduled_contact_id
         ) do
      {:ok, %ScheduledContact{lifecycle_state: :scheduled}} -> {:open, "scheduled"}
      {:ok, %ScheduledContact{lifecycle_state: :realized} = scheduled} -> realized(scheduled)
      _closed_or_missing -> :closed
    end
  end

  defp realized(%ScheduledContact{realized_contact_id: nil}), do: {:open, "scheduled"}

  defp realized(%ScheduledContact{} = scheduled) do
    case ContactStore.fetch_realized(
           scheduled.organization_id,
           scheduled.mission_id,
           scheduled.realized_contact_id
         ) do
      {:ok, %RealizedContact{lifecycle_state: :defined}} -> {:open, "realized_not_started"}
      _running_or_ended -> :closed
    end
  end

  defp describe({reservation, contact_state}) do
    %{
      provider_reservation_id: reservation.provider_reservation_id,
      reservation_state: Atom.to_string(reservation.lifecycle_state),
      spacecraft_id: reservation.spacecraft_id,
      scheduled_contact_id: reservation.scheduled_contact_id,
      contact_state: contact_state,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      action: "cancel"
    }
  end

  defp apply_one({reservation, _contact_state} = finding) do
    result =
      case ProviderReservations.release_lost(reservation) do
        :ok -> "released"
        {:error, reason} -> "failed: #{inspect(reason)}"
      end

    finding |> describe() |> Map.put(:result, result)
  end
end
