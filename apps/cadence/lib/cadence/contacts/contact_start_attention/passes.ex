defmodule Cadence.Contacts.ContactStartAttention.Passes do
  @moduledoc """
  The booking behind a `contact_start` item (ux U45): its reservation, and the pass fields the
  item carries from it. Shared by realized and unrealized items (`ContactStartAttention`,
  `ContactStartAttention.Unrealized`).
  """

  import Ecto.Query

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  def reservations(_org, _mission, []), do: %{}

  def reservations(org, mission, contacts) do
    ids = contacts |> Enum.map(& &1.scheduled_contact_id) |> Enum.reject(&is_nil/1)

    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          row.scheduled_contact_id in ^ids
    )
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
    |> Map.new(&{&1.scheduled_contact_id, &1})
  end

  def pass(nil) do
    %{
      spacecraft_id: nil,
      provider_reservation_id: nil,
      ground_station_ref: nil,
      provider_id: nil,
      starts_at: nil,
      ends_at: nil
    }
  end

  def pass(reservation) do
    %{
      spacecraft_id: reservation.spacecraft_id,
      provider_reservation_id: reservation.provider_reservation_id,
      ground_station_ref: ground_station_ref(reservation),
      provider_id: reservation.provider_id,
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at
    }
  end

  defp ground_station_ref(reservation) do
    Enum.find_value(
      [reservation.provider_confirmed_snapshot_document, reservation.request_document],
      &(is_map(&1) && &1["ground_station_ref"])
    )
  end

  def timestamp(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  def timestamp(_at), do: nil
end
