defmodule Cadence.Contacts.PassReleaseAttention do
  @moduledoc """
  The `pass_release` source of the mission attention read: a pass Cadence tried to release
  (cancel at the provider) whose cancel failed, so it may still be booked
  (`ProviderReservations.cancel_failed/2`). Conflict `cancel_failed`. `reason` is the outcome:

  - `refused` / `not_sent`: the cancel didn't happen and the booking stands;
  - `unknown`: it may have; the reconciler settles the reservation.

  Derived from the reservation's durable `cancel_failure` marker, so there's nothing to
  acknowledge (like `uplink_blocked`). An item is open until the reservation is canceled or ends
  some other way, or the pass ends; then it resolves (`resolved_by` kind `system`).
  """

  import Ecto.Query

  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @source "pass_release"
  @ended ~w(canceled completed rejected failed)a

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    now = DateTime.utc_now()

    org
    |> failed_cancels(mission)
    |> Enum.filter(&open?(&1, now))
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> Enum.map(&item/1)
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    now = DateTime.utc_now()

    for reservation <- failed_cancels(org, mission),
        not open?(reservation, now),
        {action, at} = resolution(reservation),
        DateTime.compare(at, since) != :lt do
      %{
        id: reservation.provider_reservation_id,
        source: @source,
        resolved_by: %{"kind" => "system"},
        action: action,
        resolved_at: at
      }
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(items(org, mission)), acknowledged: 0}

  defp failed_cancels(org, mission) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and
        fragment("? -> 'value' -> 'cancel_failure' IS NOT NULL", r.metadata)
    )
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
  end

  defp open?(%ProviderReservation{} = reservation, now),
    do:
      reservation.lifecycle_state not in @ended and
        DateTime.compare(reservation.ends_at, now) == :gt

  # Stable times only: a canceled or otherwise ended reservation isn't reconciled again.
  defp resolution(%ProviderReservation{lifecycle_state: :canceled} = reservation),
    do: {"canceled", reservation.updated_at}

  defp resolution(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in @ended,
       do: {"booking ended", reservation.updated_at}

  defp resolution(%ProviderReservation{} = reservation), do: {"pass ended", reservation.ends_at}

  defp item(%ProviderReservation{} = reservation) do
    failure = (reservation.metadata || %{})["cancel_failure"] || %{}

    %{
      id: reservation.provider_reservation_id,
      source: @source,
      conflict: "cancel_failed",
      state: "open",
      reason: failure["outcome"],
      outcome: failure["outcome"],
      provider_reason: failure["reason"],
      provider_message: provider_message(failure["reason"]),
      spacecraft_id: reservation.spacecraft_id,
      contact_id: reservation.scheduled_contact_id,
      provider_reservation_id: reservation.provider_reservation_id,
      provider_contact_ref: reservation.provider_contact_ref,
      ground_station_ref: ground_station_ref(reservation),
      provider_id: reservation.provider_id,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      raised_at: raised_at(failure["recorded_at"])
    }
  end

  defp provider_message(%{"detail" => detail}) when is_binary(detail), do: detail
  defp provider_message(reason) when is_binary(reason), do: reason
  defp provider_message(nil), do: nil
  defp provider_message(reason), do: inspect(reason)

  defp raised_at(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp raised_at(_at), do: nil

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end
end
