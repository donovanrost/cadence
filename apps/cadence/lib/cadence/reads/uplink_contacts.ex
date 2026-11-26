defmodule Cadence.Reads.UplinkContacts do
  @moduledoc """
  The contact half of a group's uplink block (api U46, fe-ops' named-release reader;
  docs/apogee/api/commanding.md):

    * `spacecraft {id, name}`: the target the block describes (the group's first).
    * `pass` gains `realized_contact_id`, `booked: true`, `started_by`, `started_at` and
      `armed_group_ids` (null/[] before the pass has a contact).
    * `contact`: that spacecraft's live hand-started contact (not a booked pass), else null, with
      the same fields, `booked: false` and no reservation or AOS/LOS.

  `armed_group_ids` are the mission's queued groups with members still queued for that spacecraft,
  oldest GO first: what a named release sends, in that order.
  """

  alias Cadence.Commanding.Groups.Waiting
  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{OpenContacts, RealizedContact}
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.ContactStart
  alias Cadence.SpacecraftStore

  @spec load(binary(), binary(), [binary()]) :: map()
  def load(org, mission, spacecraft_ids) do
    wanted = MapSet.new(spacecraft_ids)
    owners = Groups.spacecraft_by_endpoint(org, mission)
    open = OpenContacts.list(org, mission)
    refs = for {ref, id} <- owners, MapSet.member?(wanted, id), do: ref

    by_scheduled =
      for(%{scheduled_contact_id: id} = c <- open, is_binary(id), into: %{}, do: {id, c})

    hand = hand_started(open, owners)

    %{
      names: names(org, mission, spacecraft_ids),
      by_scheduled: by_scheduled,
      hand: hand,
      # Who started each contact, named only as members (#468): one lookup for the whole read.
      people: ContactStart.people(org, Map.values(by_scheduled) ++ Map.values(hand)),
      armed:
        org
        |> Waiting.armed_on(mission, refs)
        |> Enum.group_by(fn {ref, _id} -> owners[ref] end, &elem(&1, 1))
        |> Map.new(fn {id, groups} -> {id, Enum.uniq(groups)} end)
    }
  end

  @doc "Adds the contact half to a group's uplink block (`nil` when there's neither)."
  @spec decorate(map() | nil, binary() | nil, map(), map()) :: map() | nil
  def decorate(uplink, nil, _ctx, _stations), do: uplink

  def decorate(uplink, spacecraft_id, ctx, stations) do
    contact = Map.get(ctx.hand, spacecraft_id)

    if is_nil(uplink) and is_nil(contact) do
      nil
    else
      armed = Map.get(ctx.armed, spacecraft_id, [])
      base = uplink || %{pass: nil, readiness: nil, next_pass: nil}

      Map.merge(base, %{
        spacecraft: %{id: spacecraft_id, name: Map.get(ctx.names, spacecraft_id, spacecraft_id)},
        pass: base.pass && booked(base.pass, ctx, armed),
        contact: contact && hand(contact, stations, armed, ctx.people)
      })
    end
  end

  defp booked(pass, ctx, armed) do
    realized = Map.get(ctx.by_scheduled, pass.contact_id)

    Map.merge(pass, %{
      realized_contact_id: realized && realized.realized_contact_id,
      booked: true,
      started_by: realized && ContactStart.started_by(realized, ctx.people),
      started_at: realized && started_at(realized),
      armed_group_ids: armed
    })
  end

  defp hand(%RealizedContact{} = contact, stations, armed, people) do
    started_at = started_at(contact)

    %{
      realized_contact_id: contact.realized_contact_id,
      booked: false,
      reservation_id: nil,
      contact_id: nil,
      station: StationRefs.resolve(contact.metadata["ground_station_ref"], stations),
      starts_at: started_at || contact.realized_at,
      ends_at: nil,
      started_by: ContactStart.started_by(contact, people),
      started_at: started_at,
      armed_group_ids: armed
    }
  end

  # A spacecraft's latest live contact that no booked pass realized (a hand start, #84). Only an
  # active one: a hand start that never started has no window to end it (domain's orphan sweep
  # closes booked ones only) and is U45's contact_start item instead.
  defp hand_started(open, owners) do
    open
    |> Enum.filter(&(is_nil(&1.scheduled_contact_id) and &1.lifecycle_state == :active))
    |> Enum.sort_by(&realized_order/1)
    |> Enum.reduce(%{}, fn contact, acc ->
      case contact.source_endpoint_refs |> Enum.map(&owners[&1]) |> Enum.uniq() do
        [spacecraft_id] when is_binary(spacecraft_id) -> Map.put(acc, spacecraft_id, contact)
        _none_or_several -> acc
      end
    end)
  end

  defp realized_order(%RealizedContact{realized_at: %DateTime{} = at} = c),
    do: {DateTime.to_unix(at, :microsecond), c.realized_contact_id}

  defp realized_order(%RealizedContact{} = c), do: {0, c.realized_contact_id}

  # Only while it's live (Uplink's block); History's rows use ContactStart directly.
  defp started_at(%RealizedContact{lifecycle_state: :active} = contact),
    do: ContactStart.went_live_at(contact)

  defp started_at(_contact), do: nil

  defp names(_org, _mission, []), do: %{}

  defp names(org, mission, ids) do
    case SpacecraftStore.display_names(org, mission, Enum.uniq(ids)) do
      {:ok, rows} -> Map.new(rows, &{&1["id"], &1["name"] || &1["id"]})
      _error -> %{}
    end
  end
end
