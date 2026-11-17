defmodule Cadence.Reads.ActionQueue.ContactStartItem do
  @moduledoc """
  The `contact_start` attention source on the wire (ux U45; domain's
  `Cadence.Contacts.ContactStartAttention`): a contact that failed to start. `not_started` while
  the pass is on (P1, due at LOS), `missed` once its window ended (P2, until marked as seen).

  The item's own keys are flattened as for `contact_settlement`. `holder`, the pass still holding
  the station listener (`listener_in_use` only), is named like a pass: spacecraft and station.
  """

  @keys [
    :reason,
    :failure_message,
    :provider_profile_id,
    :provider_profile_name,
    :realized_contact_id,
    :spacecraft_id,
    :ends_at,
    :retry,
    :attempts,
    :last_attempt_at,
    :expires_at,
    # listen_endpoint_claimed (ux U81): the port another mission listens on, and the transport
    # whose port it is (id and name, each nil if the binding doesn't say); nil for every other
    # reason.
    :listen_port,
    :transport_id,
    :transport_name,
    # U91: for no_runtime_spec, no_configuration (the mission's to fix) or
    # configuration_unverifiable (Cadence's); nil otherwise and on failures stored before it.
    :reason_detail
  ]

  @doc "The source's wire keys, `holder` serialized with `station` (a `StationRefs` resolver)."
  @spec fields(map(), map(), (term() -> map())) :: map()
  def fields(attention, spacecraft, station) do
    attention
    |> Map.take(@keys)
    |> Map.put(:holder, holder(Map.get(attention, :holder), spacecraft, station))
  end

  @doc "Spacecraft ids the item names: its own and its holder's."
  @spec spacecraft_ids(map()) :: [binary()]
  def spacecraft_ids(attention) do
    [Map.get(attention, :spacecraft_id), get_in(attention, [:holder, :spacecraft_id])]
    |> Enum.filter(&is_binary/1)
  end

  defp holder(nil, _spacecraft, _station), do: nil

  defp holder(holder, spacecraft, station) do
    id = holder.spacecraft_id

    %{
      realized_contact_id: holder.realized_contact_id,
      contact_id: holder.contact_id,
      reservation_id: holder.provider_reservation_id,
      spacecraft: id && %{id: id, name: name(Map.get(spacecraft, id))},
      station: station.(holder.ground_station_ref),
      starts_at: holder.starts_at,
      ends_at: holder.ends_at
    }
  end

  defp name(%{name: name}), do: name
  defp name(_unknown), do: nil
end
