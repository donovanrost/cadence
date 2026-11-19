defmodule Cadence.Reads.PassUplink do
  @moduledoc """
  Uplink readiness for the console (ux U33, DECISIONS #58), from domain's live readiness view
  (`Cadence.Control.UplinkReadiness`, refreshed every 15 s):

    * on pass rows: `uplink_readiness` `%{state, reason, since, command_groups_queued}`, or
      `nil` when the pass has no live uplink session (future, downlink-only, not booked);
    * on queued command groups: `uplink` `%{pass, readiness, next_pass}` for the pass the group
      will release on, named by reservation and station, plus U46's `spacecraft`, `contact` and
      the pass's contact fields (`Cadence.Reads.UplinkContacts`).

  `command_groups_queued` is known for a blocked pass (the `uplink_blocked` attention item lists
  the groups it holds back; none listed means none queued) and `nil` otherwise.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.UplinkPasses
  alias Cadence.Control.Contacts
  alias Cadence.Control.UplinkReadiness
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.{CommandGroups, Passes, UplinkContacts}

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

    drops = drops_by_contact(org, mission, passes)

    Enum.map(passes, fn pass ->
      view =
        case Map.get(drops, pass.scheduled_contact_id) do
          nil -> readiness_view(Map.get(readiness, pass.scheduled_contact_id), pass, blocked)
          drop -> dropped_view(org, mission, pass, drop)
        end

      Map.put(pass, :uplink_readiness, view)
    end)
  end

  @doc """
  U46: the passes among `rows` (pass rows: `id` = reservation id) whose uplink leg an accepted
  change dropped, `%{scheduled_contact_id => %{at, change_id, provider_id, reason}}`.
  """
  @spec drops_by_contact(binary(), binary(), [map()]) :: %{binary() => map()}
  def drops_by_contact(org, mission, rows) do
    drops =
      Contacts.uplink_drops(
        org,
        mission,
        rows |> Enum.map(&Map.get(&1, :id)) |> Enum.filter(&is_binary/1) |> Enum.uniq()
      )

    for row <- rows, drop = Map.get(drops, Map.get(row, :id)), into: %{} do
      {row.scheduled_contact_id, drop}
    end
  end

  # U46: blocked for its whole window (not only while a session runs), since the drop. Gone
  # once the pass has ended, as any readiness.
  defp dropped_view(org, mission, pass, drop) do
    if ended?(pass),
      do: nil,
      else: %{
        state: "blocked",
        reason: "uplink_leg_dropped",
        since: drop.at,
        command_groups_queued: queued_for_pass(org, mission, pass).count
      }
  end

  defp ended?(%{ends_at: %DateTime{} = ends_at}),
    do: DateTime.compare(ends_at, DateTime.utc_now()) != :gt

  defp ended?(_pass), do: false

  defp readiness_view(nil, _pass, _blocked), do: nil

  # An ended pass has no uplink to be ready (qa #41).
  defp readiness_view(%{ends_at: %DateTime{} = ends_at} = view, pass, blocked) do
    if DateTime.compare(ends_at, DateTime.utc_now()) == :gt,
      do: live_view(view, pass, blocked),
      else: nil
  end

  defp readiness_view(view, pass, blocked), do: live_view(view, pass, blocked)

  defp live_view(view, pass, blocked) do
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

  @doc """
  For one pass row (the D2 Release sheet): how many queued, unfinished command groups will release
  on it, whatever its readiness, and the spacecraft's next commandable pass after it, where they'd
  go if it were released. `%{count, next_pass | nil}`.
  """
  @spec queued_for_pass(binary(), binary(), map()) :: %{
          count: non_neg_integer(),
          next_pass: map() | nil
        }
  def queued_for_pass(org, mission, %{scheduled_contact_id: contact_id} = pass)
      when is_binary(contact_id) do
    group_ids =
      for %{finished: false, id: id} <- CommandGroups.list(org, mission, nil, states: [:queued]),
          do: id

    count =
      org
      |> Groups.for_command_groups(mission, group_ids)
      |> Enum.count(fn {_id, %{targets: targets}} ->
        Enum.any?(targets, &(target_pass_id(&1) == contact_id))
      end)

    %{count: count, next_pass: next_after(org, mission, pass)}
  end

  def queued_for_pass(_org, _mission, _pass), do: %{count: 0, next_pass: nil}

  defp target_pass_id(%{contact: %{scheduled_contact_id: id}}), do: id
  defp target_pass_id(%{next_contact: %{scheduled_contact_id: id}}), do: id
  defp target_pass_id(_target), do: nil

  defp next_after(org, mission, pass) do
    org
    |> UplinkPasses.upcoming(mission, [pass.spacecraft_id], pass.starts_at, 3)
    |> Map.get(pass.spacecraft_id, [])
    |> Enum.reject(&(&1.scheduled_contact_id == pass.scheduled_contact_id))
    |> List.first()
    |> case do
      nil ->
        nil

      next ->
        refs = pass_refs(org, mission, [Map.put(next, :ground_station_ref, nil)])
        pass_ref(Map.put(next, :ground_station_ref, nil), refs)
    end
  end

  @doc "`%{group_id => uplink | nil}` for the given (queued) groups."
  @spec for_groups(binary(), binary(), [binary()]) :: %{binary() => map() | nil}
  def for_groups(_org, _mission, []), do: %{}

  def for_groups(org, mission, group_ids) do
    now = DateTime.utc_now()

    # qa #41: a live entry whose pass has ended isn't the group's pass any more (the readiness
    # view can still hold it until the driver forgets it).
    waiting =
      org
      |> Groups.for_command_groups(mission, group_ids)
      |> Map.new(fn {id, entry} -> {id, drop_ended(entry, now)} end)

    passes = waiting |> Map.values() |> Enum.flat_map(&[&1.contact, &1.next_contact])
    refs = pass_refs(org, mission, Enum.reject(passes, &is_nil/1))
    drops = drops_by_contact(org, mission, Map.values(refs.rows))
    # U46: the block describes the group's first target; its contacts and armed groups.
    first = Map.new(waiting, fn {id, entry} -> {id, first_target(entry)} end)
    contacts = UplinkContacts.load(org, mission, first |> Map.values() |> Enum.reject(&is_nil/1))

    Map.new(group_ids, fn id ->
      {id,
       waiting
       |> Map.get(id)
       |> without_drops(drops)
       |> group_uplink(refs)
       |> UplinkContacts.decorate(Map.get(first, id), contacts, refs.stations)}
    end)
  end

  defp first_target(%{targets: [%{spacecraft_id: id} | _rest]}), do: id
  defp first_target(_entry), do: nil

  # U46: domain's next_contact already skips dropped passes; the live contact the group is on
  # shows a drop as its readiness (fe-ops).
  defp without_drops(nil, _drops), do: nil

  defp without_drops(entry, drops) do
    case entry.contact && Map.get(drops, entry.contact.scheduled_contact_id) do
      nil -> entry
      drop -> %{entry | contact: Map.put(entry.contact, :dropped, drop)}
    end
  end

  # The pass a group releases on is its spacecraft's live pass, else the next booked one that
  # can command; `next_pass` is the one after a live pass (where a blocked group goes next).
  defp drop_ended(%{contact: %{ends_at: %DateTime{} = ends_at}} = entry, now) do
    if DateTime.compare(ends_at, now) == :gt, do: entry, else: %{entry | contact: nil}
  end

  defp drop_ended(entry, _now), do: entry

  defp group_uplink(nil, _refs), do: nil
  defp group_uplink(%{contact: nil, next_contact: nil}, _refs), do: nil

  defp group_uplink(%{contact: nil, next_contact: next}, refs),
    do: %{pass: pass_ref(next, refs), readiness: nil, next_pass: nil}

  defp group_uplink(%{contact: contact, next_contact: next}, refs) do
    %{
      pass: pass_ref(contact, refs),
      readiness: group_readiness(contact),
      next_pass: next && pass_ref(next, refs)
    }
  end

  defp group_readiness(%{dropped: drop}),
    do: %{state: "blocked", reason: "uplink_leg_dropped", since: drop.at}

  defp group_readiness(contact), do: contact.readiness && wire_readiness(contact.readiness)

  @doc false
  def pass_ref(pass, refs) do
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
  @doc false
  def pass_refs(org, mission, []), do: %{rows: %{}, stations: StationRefs.index(org, mission)}

  def pass_refs(org, mission, passes) do
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
      reason: reason_key(view.reason),
      since: view.since
    }
  end

  # qa #41: a readiness reason can be a provider error struct, not only a key. The wire carries a
  # key the console can word (unknown keys show in sentence case).
  @doc false
  @spec reason_key(term()) :: binary() | nil
  def reason_key(nil), do: nil
  def reason_key(reason) when is_atom(reason) or is_binary(reason), do: to_string(reason)

  def reason_key(%{category: category}) when is_atom(category) and not is_nil(category),
    do: "provider_" <> Atom.to_string(category)

  def reason_key({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  def reason_key(_other), do: "unknown"
end
