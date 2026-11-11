defmodule Cadence.Contacts.ContactSettlementAttention do
  @moduledoc """
  The `contact_settlement` source of the mission attention read (DECISIONS #71, ux U37): an
  ended contact whose telemetry is still in its on-disk journal, not yet stored
  (`settlement.state` `"unsettled"`). Conflict `unsettled`; `reason` is `settle_deadline` or
  `settle_failed`, and `failure_kind` groups same-cause items.

  Derived from the durable settlement, so there's nothing to acknowledge. The journal is never
  pruned past its processing cursor, so the item has no expiry (`expires_at` nil, always P2).
  Cadence retries by itself (`retry` `"automatic"`): the item resolves (`resolved_by` kind
  `system`, action `replayed`) when replaying the journal settles the contact.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @source "contact_settlement"
  @epoch ~U[1970-01-01 00:00:00Z]

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    contacts = in_state(org, mission, "unsettled")
    reservations = reservations(org, mission, contacts)

    contacts
    |> Enum.map(&item(&1, Map.get(reservations, &1.scheduled_contact_id)))
    |> Enum.sort_by(&(&1.raised_at || @epoch), DateTime)
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    for contact <- in_state(org, mission, "settled"),
        replayed_at = timestamp(contact.metadata["settlement"]["replayed_at"]),
        replayed_at != nil and DateTime.compare(replayed_at, since) != :lt do
      %{
        id: contact.realized_contact_id,
        source: @source,
        resolved_by: %{"kind" => "system"},
        action: "replayed",
        resolved_at: replayed_at
      }
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission) do
    open =
      org
      |> state_query(mission, "unsettled")
      |> select([row], count(row.realized_contact_id))
      |> Repo.one()

    %{open: open, acknowledged: 0}
  end

  defp in_state(org, mission, state) do
    org
    |> state_query(mission, state)
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  defp state_query(org, mission, state) do
    from(row in RealizedContactRow,
      where:
        row.organization_id == ^org and row.mission_id == ^mission and
          fragment("? -> 'value' -> 'settlement' ->> 'state' = ?", row.metadata, ^state)
    )
  end

  defp reservations(_org, _mission, []), do: %{}

  defp reservations(org, mission, contacts) do
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

  defp item(%RealizedContact{} = contact, reservation) do
    settlement = contact.metadata["settlement"] || %{}

    %{
      id: contact.realized_contact_id,
      source: @source,
      conflict: "unsettled",
      state: "open",
      reason: settlement["reason"],
      failure_kind: settlement["failure_kind"],
      failure_message: settlement["failure_message"],
      contact_id: contact.scheduled_contact_id,
      realized_contact_id: contact.realized_contact_id,
      raised_at: timestamp(settlement["unsettled_at"]),
      deadline_at: timestamp(settlement["deadline_at"]),
      backlog: backlog(settlement["backlog"] || %{}),
      expires_at: nil,
      retry: "automatic",
      next_attempt_at: nil,
      acknowledged_by: nil,
      provider_message: nil,
      resolution: nil
    }
    |> Map.merge(pass(reservation))
  end

  defp backlog(backlog) do
    %{
      entries: Map.get(backlog, "entries", 0),
      bytes: Map.get(backlog, "bytes", 0),
      journals: Map.get(backlog, "journals", 0)
    }
  end

  # The pass the contact realized, from its booking; nil fields for a contact without one.
  defp pass(nil) do
    %{
      spacecraft_id: nil,
      provider_reservation_id: nil,
      ground_station_ref: nil,
      provider_id: nil,
      starts_at: nil,
      ends_at: nil
    }
  end

  defp pass(reservation) do
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

  defp timestamp(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp timestamp(_at), do: nil
end
