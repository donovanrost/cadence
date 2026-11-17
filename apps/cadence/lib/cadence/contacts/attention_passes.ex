defmodule Cadence.Contacts.AttentionPasses do
  @moduledoc """
  The pass behind a realized contact, for attention sources that name it (ingress_backpressure,
  replay_conflict): the contact's record and its booking, looked up once per read.
  """

  import Ecto.Query

  alias Cadence.Contacts.{ContactStore, RealizedContact}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @doc "Each contact's record and its booking, looked up once per read."
  @spec context(binary(), binary(), [binary()]) :: map()
  def context(org, mission, contact_ids) do
    contacts =
      contact_ids
      |> Enum.uniq()
      |> Enum.flat_map(fn id ->
        case ContactStore.fetch_realized(org, mission, id) do
          {:ok, %RealizedContact{} = contact} -> [{id, contact}]
          _missing -> []
        end
      end)
      |> Map.new()

    %{contacts: contacts, reservations: reservations(org, mission, Map.values(contacts))}
  end

  @doc "The scheduled contact a realized contact belongs to, or nil."
  @spec scheduled_contact_id(map(), binary()) :: binary() | nil
  def scheduled_contact_id(context, contact) do
    case Map.get(context.contacts, contact) do
      %RealizedContact{scheduled_contact_id: id} -> id
      nil -> nil
    end
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

  @doc "The pass the contact realizes, from its booking; nil fields for a contact without one."
  @spec pass(map(), binary()) :: map()
  def pass(context, contact) do
    case Map.get(context.reservations, scheduled_contact_id(context, contact)) do
      nil ->
        %{
          spacecraft_id: nil,
          provider_reservation_id: nil,
          ground_station_ref: nil,
          provider_id: nil,
          starts_at: nil,
          ends_at: nil
        }

      reservation ->
        %{
          spacecraft_id: reservation.spacecraft_id,
          provider_reservation_id: reservation.provider_reservation_id,
          ground_station_ref:
            Enum.find_value(
              [reservation.provider_confirmed_snapshot_document, reservation.request_document],
              &(is_map(&1) && &1["ground_station_ref"])
            ),
          provider_id: reservation.provider_id,
          starts_at: reservation.starts_at,
          ends_at: reservation.ends_at
        }
    end
  end
end
