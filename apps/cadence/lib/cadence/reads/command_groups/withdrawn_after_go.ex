defmodule Cadence.Reads.CommandGroups.WithdrawnAfterGo do
  @moduledoc """
  Which targets of a group are on a withdrawn model approval its GO didn't know about (E2, #546;
  the release panel's caution). The same comparison the unattended release refuses on
  (`Commanding.release_command_queue_entry/6`): a target is flagged when its craft's active
  generation runs a withdrawn revision and a member still waiting for its contact has an approval
  row that recorded a different withdrawal (or none, or predates the record).

  Computed once per group read, from one `Control.WithdrawnPins.for_spacecraft/3` over the group's
  craft and one read of the waiting members' approval rows: a fixed number of queries for any
  number of targets. Each target row carries `withdrawn_after_go` (nil, or `%{revision_id,
  decision: %{kind, by: %{id, name}, at, reason}}`), and the group gets a summary over every
  target, not a page: `%{count, latest}` (the newest decision by `at`), or nil.
  """

  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Control.WithdrawnPins

  @type flag :: %{revision_id: binary(), decision: map()}
  @type summary :: %{count: pos_integer(), latest: flag()} | nil

  @spec put([map()], binary(), binary()) :: {[map()], summary()}
  def put(targets, org, mission) do
    pins = WithdrawnPins.for_spacecraft(org, mission, Enum.map(targets, & &1.spacecraft_id))

    if pins == %{} do
      {Enum.map(targets, &Map.put(&1, :withdrawn_after_go, nil)), nil}
    else
      seen = seen(targets, pins, org, mission)
      flagged = Enum.map(targets, &Map.put(&1, :withdrawn_after_go, flag(&1, pins, seen)))
      {flagged, summary(flagged)}
    end
  end

  # What the GO recorded for the members still waiting for their contact on a withdrawn craft.
  defp seen(targets, pins, org, mission) do
    ids =
      for target <- targets,
          Map.has_key?(pins, target.spacecraft_id),
          member <- waiting(target),
          do: member.request_id

    GroupStore.withdrawn_seen_for(org, mission, ids)
  end

  defp waiting(target), do: Enum.filter(target.members, &(&1.stage == :queued_for_contact))

  defp flag(target, pins, seen) do
    with %{} = pin <- Map.get(pins, target.spacecraft_id),
         true <-
           Enum.any?(
             waiting(target),
             &(Map.get(seen, &1.request_id, :unrecorded) != pin.hold_basis)
           ) do
      %{
        revision_id: pin.revision_id,
        decision: %{
          kind: pin.decision.kind,
          by: Map.take(pin.decision.by || %{}, [:id, :name]),
          at: pin.decision.at,
          reason: pin.decision.reason
        }
      }
    else
      _none -> nil
    end
  end

  defp summary(targets) do
    case for(%{withdrawn_after_go: %{} = flag} <- targets, do: flag) do
      [] -> nil
      flags -> %{count: length(flags), latest: Enum.max_by(flags, & &1.decision.at, DateTime)}
    end
  end
end
