defmodule Cadence.Spacecraft.ConfigKinds.ArchiveHolds do
  @moduledoc """
  HOLDs for a change set that archives spacecraft (#49/#50, L22). Sentences are ux's (U40):

  - `spacecraft_commands_waiting` (blocking): command requests still wait to release to it.
    Release or cancel them first, so nothing can be sent to a spacecraft nobody lists.
  - `spacecraft_passes_booked` (acknowledge): passes still booked ahead stay booked after the
    archive. Details carry the count and the earliest start.
  - `spacecraft_has_traffic` (acknowledge): it has had traffic; it's archived, not removed.

  The traffic reads come through the `:spacecraft_traffic` adapter, so the spacecraft kind keeps
  no compile-time edge to contacts or commanding.
  """

  @spec holds(binary(), binary(), [map()]) :: [map()]
  def holds(organization_id, mission_id, entries) do
    names =
      for %{kind: "spacecraft", op: :delete, entity_id: id} = entry <- entries,
          into: %{},
          do: {id, (Map.get(entry, :previous) || %{})["display_name"] || id}

    case {Map.keys(names), Application.get_env(:cadence, :spacecraft_traffic)} do
      {[], _traffic} ->
        []

      {_ids, nil} ->
        []

      {ids, traffic} ->
        busy = traffic.with_traffic(organization_id, mission_id, ids)
        blockers = traffic.archive_blockers(organization_id, mission_id, ids)

        Enum.flat_map(ids, &spacecraft_holds(&1, names[&1], Map.get(blockers, &1), busy))
    end
  end

  defp spacecraft_holds(id, name, blockers, busy) do
    past = if MapSet.member?(busy, id), do: [past_traffic(id, name)], else: []
    ahead(id, name, blockers) ++ past
  end

  defp ahead(_id, _name, nil), do: []

  defp ahead(id, name, blockers) do
    waiting =
      if blockers.waiting_requests > 0,
        do: [
          item(id, :spacecraft_commands_waiting, true, blockers, waiting_sentence(name, blockers))
        ],
        else: []

    booked =
      if blockers.booked_passes > 0,
        do: [
          item(id, :spacecraft_passes_booked, false, blockers, booked_sentence(name, blockers))
        ],
        else: []

    waiting ++ booked
  end

  defp past_traffic(id, name),
    do:
      item(
        id,
        :spacecraft_has_traffic,
        false,
        nil,
        "#{name} has had passes booked or commands requested. Archiving it takes it out of " <>
          "the mission's lists, fleet and planning when this is applied. Its history stays."
      )

  defp waiting_sentence(name, %{waiting_requests: 1}),
    do: "#{name} has 1 command request waiting. Release or cancel it first."

  defp waiting_sentence(name, %{waiting_requests: n}),
    do: "#{name} has #{n} command requests waiting. Release or cancel them first."

  defp booked_sentence(name, %{booked_passes: 1, earliest_pass_at: at}),
    do:
      "1 booked pass#{when_text(" on", at)} stays booked after #{name} is archived. " <>
        "Release it in Contacts if it isn't needed."

  defp booked_sentence(name, %{booked_passes: n, earliest_pass_at: at}),
    do:
      "#{n} booked passes#{when_text(" from", at)} stay booked after #{name} is archived. " <>
        "Release them in Contacts if they're not needed."

  # §4 short time, e.g. "11-15 03:00Z"; left out when unknown.
  defp when_text(_word, nil), do: ""
  defp when_text(word, %DateTime{} = at), do: "#{word} #{Calendar.strftime(at, "%m-%d %H:%MZ")}"

  defp item(id, reason, blocking, blockers, sentence) do
    base = %{
      op_id: nil,
      change_id: nil,
      kind: "spacecraft",
      entity_id: id,
      reason: reason,
      blocking: blocking,
      sentence: sentence
    }

    if blockers,
      do:
        Map.put(
          base,
          :details,
          Map.take(blockers, ~w(waiting_requests booked_passes earliest_pass_at)a)
        ),
      else: base
  end
end
