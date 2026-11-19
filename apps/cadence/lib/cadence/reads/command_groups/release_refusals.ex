defmodule Cadence.Reads.CommandGroups.ReleaseRefusals do
  @moduledoc """
  A member's `release_refusal` (api U46): why a named release stopped at it, while it still
  waits. Taken from the latest `released_on_contact` event that names the member's pending queue
  entry: a stop there gives `%{code, details, at, realized_contact_id, booked}`; a later event that
  released it or didn't reach it clears it. A member that's no longer pending has none (one the
  stop closed says why on its own row: `end_reason`).
  """

  alias Cadence.Commanding.Groups.GroupStore

  @spec put([map()], [map()], binary(), binary()) :: [map()]
  def put(targets, events, org, mission) do
    releases = Enum.filter(events, &(&1.kind in [:released_on_contact, "released_on_contact"]))

    if releases == [] do
      Enum.map(targets, &put_members(&1, %{}, []))
    else
      ids = for target <- targets, member <- target.members, do: member.request_id
      pending = GroupStore.pending_entry_ids(org, mission, ids)
      Enum.map(targets, &put_members(&1, pending, Enum.reverse(releases)))
    end
  end

  defp put_members(target, pending, latest_first) do
    members =
      Enum.map(target.members, fn member ->
        Map.put(
          member,
          :release_refusal,
          refusal(Map.get(pending, member.request_id), latest_first)
        )
      end)

    %{target | members: members}
  end

  defp refusal(nil, _latest_first), do: nil

  defp refusal(entry_id, latest_first) do
    case Enum.find(latest_first, &names?(&1.payload, entry_id)) do
      %{payload: %{"stopped" => %{"command_queue_entry_id" => ^entry_id} = stopped}} = event ->
        reason = stopped["reason"] || %{}

        %{
          code: reason["code"] || "unknown",
          details: reason["details"] || %{},
          at: event.at,
          realized_contact_id: event.payload["realized_contact_id"],
          booked: event.payload["booked"] == true
        }

      _released_or_not_reached ->
        nil
    end
  end

  defp names?(%{} = payload, entry_id) do
    match?(%{"command_queue_entry_id" => ^entry_id}, payload["stopped"]) or
      entry_id in (payload["released_entry_ids"] || []) or
      entry_id in (payload["not_attempted_entry_ids"] || [])
  end

  defp names?(_payload, _entry_id), do: false
end
