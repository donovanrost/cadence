defmodule Cadence.Reads.EventContacts do
  @moduledoc """
  Contact facts for event-log sentences (ux timeline review). A cancelled
  scheduled contact's event carries neither its spacecraft nor its station,
  so they're read from the scheduled contact: the spacecraft from its
  `spacecraft_runtime:<id>` endpoint ref, the station from its transport.
  One lookup per contact on the page; stations and transports once.
  """

  alias Cadence.Comms.{StationRefs, TransportStore}
  alias Cadence.Contacts
  alias Cadence.MissionEvents.Entry

  @kinds ~w(scheduled_contact_canceled)

  @doc "Entries with their contact's spacecraft filled in, and `%{contact_id => facts}`."
  @spec enrich(binary(), binary(), [Entry.t()]) :: {[Entry.t()], map()}
  def enrich(organization_id, mission_id, entries) do
    ids =
      entries
      |> Enum.filter(&(to_string(&1.kind) in @kinds))
      |> Enum.map(&(&1.scheduled_contact_id || &1.subject_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    facts = facts(organization_id, mission_id, ids)

    entries =
      Enum.map(entries, fn entry ->
        case Map.get(facts, entry.scheduled_contact_id || entry.subject_id) do
          %{spacecraft_id: id} when is_nil(entry.spacecraft_id) and is_binary(id) ->
            %{entry | spacecraft_id: id}

          _other ->
            entry
        end
      end)

    {entries, facts}
  end

  @doc """
  `%{scheduled_contact_id => %{spacecraft_id, station: %{name, code} | nil, starts_at, ends_at}}`
  for `ids` (also the runtime item's next pass, U91).
  """
  @spec contact_facts(binary(), binary(), [binary()]) :: map()
  def contact_facts(organization_id, mission_id, ids), do: facts(organization_id, mission_id, ids)

  defp facts(_organization_id, _mission_id, []), do: %{}

  defp facts(organization_id, mission_id, ids) do
    contacts =
      Enum.flat_map(ids, fn id ->
        case Contacts.fetch_scheduled_contact(organization_id, mission_id, id) do
          {:ok, contact} -> [contact]
          _missing -> []
        end
      end)

    transport_ids =
      contacts |> Enum.map(&transport_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    stations_by_transport =
      case TransportStore.fetch_transports(organization_id, mission_id, transport_ids) do
        {:ok, transports} -> Map.new(transports, fn {id, t} -> {id, t.ground_station_id} end)
        _none -> %{}
      end

    stations = StationRefs.index(organization_id, mission_id)

    Map.new(contacts, fn contact ->
      station =
        StationRefs.resolve(Map.get(stations_by_transport, transport_id(contact)), stations)

      {contact.scheduled_contact_id,
       %{
         spacecraft_id: spacecraft_id(contact),
         station: station.name && %{name: station.name, code: station.code},
         starts_at: contact.starts_at,
         ends_at: contact.ends_at
       }}
    end)
  end

  defp transport_id(contact), do: (contact.metadata || %{})["transport_id"]

  defp spacecraft_id(contact) do
    Enum.find_value(contact.source_endpoint_refs || [], fn
      "spacecraft_runtime:" <> id -> id
      _other -> nil
    end)
  end
end
