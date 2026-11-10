defmodule Cadence.Reads.PassUplink do
  @moduledoc """
  Uplink readiness for the console (ux U33, DECISIONS #58), from domain's live readiness view
  (`Cadence.Control.UplinkReadiness`, refreshed every 15 s):

    * on pass rows: `uplink_readiness` `%{state, reason, since, command_groups_queued}`, or
      `nil` when the pass has no live uplink session (future, downlink-only, not booked);
    * on queued command groups: `uplink` `%{pass, readiness, next_pass}` for the pass the group
      will release on, named by reservation and station.

  `command_groups_queued` is known for a blocked pass (the `uplink_blocked` attention item lists
  the groups it holds back; none listed means none queued) and `nil` otherwise.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Control.UplinkReadiness
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.Passes

  @doc """
  Puts `uplink_readiness` on pass rows. `blocked` is the mission's `uplink_blocked` attention
  items (`contact_id` => item), for the group counts.
  """
  @spec put_readiness(binary(), binary(), [map()], %{binary() => map()}) :: [map()]
  def put_readiness(org, mission, passes, blocked \\ %{}) do
    readiness =
      UplinkReadiness.for_contacts(
        org,
        mission,
        passes |> Enum.map(& &1.scheduled_contact_id) |> Enum.reject(&is_nil/1)
      )

    Enum.map(passes, fn pass ->
      Map.put(
        pass,
        :uplink_readiness,
        readiness_view(Map.get(readiness, pass.scheduled_contact_id), pass, blocked)
      )
    end)
  end

  defp readiness_view(nil, _pass, _blocked), do: nil

  defp readiness_view(view, pass, blocked) do
    view
    |> wire_readiness()
    |> Map.put(:command_groups_queued, queued(view, pass, blocked))
  end

  defp queued(%{state: :blocked}, pass, blocked) do
    case Map.get(blocked, pass.scheduled_contact_id) do
      %{command_group_ids: ids} -> length(ids)
      _none -> 0
    end
  end

  defp queued(_view, _pass, _blocked), do: nil

  @doc "`%{group_id => uplink | nil}` for the given (queued) groups."
  @spec for_groups(binary(), binary(), [binary()]) :: %{binary() => map() | nil}
  def for_groups(_org, _mission, []), do: %{}

  def for_groups(org, mission, group_ids) do
    waiting = Groups.for_command_groups(org, mission, group_ids)
    passes = waiting |> Map.values() |> Enum.flat_map(&[&1.contact, &1.next_contact])
    refs = pass_refs(org, mission, Enum.reject(passes, &is_nil/1))

    Map.new(group_ids, fn id ->
      {id, waiting |> Map.get(id) |> group_uplink(refs)}
    end)
  end

  # The pass a group releases on is its spacecraft's live pass, else the next booked one that
  # can command; `next_pass` is the one after a live pass (where a blocked group goes next).
  defp group_uplink(nil, _refs), do: nil
  defp group_uplink(%{contact: nil, next_contact: nil}, _refs), do: nil

  defp group_uplink(%{contact: nil, next_contact: next}, refs),
    do: %{pass: pass_ref(next, refs), readiness: nil, next_pass: nil}

  defp group_uplink(%{contact: contact, next_contact: next}, refs) do
    %{
      pass: pass_ref(contact, refs),
      readiness: contact.readiness && wire_readiness(contact.readiness),
      next_pass: next && pass_ref(next, refs)
    }
  end

  defp pass_ref(pass, refs) do
    row = Map.get(refs.rows, pass.scheduled_contact_id)

    %{
      reservation_id: row && row.id,
      contact_id: pass.scheduled_contact_id,
      station:
        (row && row.station) || StationRefs.resolve(pass.ground_station_ref, refs.stations),
      starts_at: pass.starts_at,
      ends_at: pass.ends_at
    }
  end

  # Reservations of those passes, by scheduled contact, from the window they span.
  defp pass_refs(org, mission, []), do: %{rows: %{}, stations: StationRefs.index(org, mission)}

  defp pass_refs(org, mission, passes) do
    from = passes |> Enum.map(& &1.starts_at) |> Enum.min(DateTime)
    to = passes |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)
    wanted = MapSet.new(passes, & &1.scheduled_contact_id)

    rows =
      org
      |> Passes.load(mission, from, DateTime.add(to, 1))
      |> Map.fetch!(:passes)
      |> Enum.filter(&MapSet.member?(wanted, &1.scheduled_contact_id))
      |> Map.new(&{&1.scheduled_contact_id, &1})

    %{rows: rows, stations: StationRefs.index(org, mission)}
  end

  defp wire_readiness(view) do
    %{
      state: view.state && to_string(view.state),
      reason: view.reason && to_string(view.reason),
      since: view.since
    }
  end
end
