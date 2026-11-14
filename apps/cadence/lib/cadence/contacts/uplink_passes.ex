defmodule Cadence.Contacts.UplinkPasses do
  @moduledoc """
  A spacecraft's upcoming booked passes that can command (a scheduled contact with a
  `:command_window`, #44/#58), soonest first. The console names the pass a blocked command
  group will go on next. A pass whose uplink leg an accepted change dropped can't command
  (`Contacts.UplinkLegs.dropped?/1`, director 11-14), so it isn't one of them.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @live ~w(requesting pending confirmed active unknown)

  @doc """
  `%{spacecraft_id => [%{scheduled_contact_id, starts_at, ends_at, ground_station_ref}]}`, at
  most `limit` each.
  """
  @spec upcoming(binary(), binary(), [binary()], DateTime.t(), pos_integer()) :: map()
  def upcoming(org, mission, spacecraft_ids, now, limit \\ 2)

  def upcoming(_org, _mission, [], _now, _limit), do: %{}

  def upcoming(org, mission, spacecraft_ids, %DateTime{} = now, limit) do
    from(r in ProviderReservationRow,
      join: s in ScheduledContactRow,
      on: s.scheduled_contact_id == r.scheduled_contact_id and s.mission_id == r.mission_id,
      where:
        r.organization_id == ^org and r.mission_id == ^mission and
          r.spacecraft_id in ^spacecraft_ids and r.lifecycle_state in ^@live and
          s.lifecycle_state == "scheduled" and s.starts_at > ^now and
          fragment("'command_window' = ANY(?)", s.contact_intents) and
          not fragment(
            "(? -> 'value' -> 'uplink') IS NOT NULL AND coalesce(? -> 'value' -> 'uplink' ->> 'status', 'included') <> 'included'",
            r.request_document,
            r.cadence_accepted_snapshot_document
          ),
      order_by: [asc: s.starts_at, asc: s.scheduled_contact_id],
      select:
        {r.spacecraft_id, s.scheduled_contact_id, s.starts_at, s.ends_at,
         fragment(
           "coalesce(? -> 'value' ->> 'ground_station_ref', ? -> 'value' ->> 'ground_station_ref')",
           r.provider_confirmed_snapshot_document,
           r.request_document
         )}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_sc, id, starts_at, ends_at, station} ->
      %{
        scheduled_contact_id: id,
        starts_at: starts_at,
        ends_at: ends_at,
        ground_station_ref: station
      }
    end)
    |> Map.new(fn {spacecraft_id, passes} -> {spacecraft_id, Enum.take(passes, limit)} end)
  end
end
