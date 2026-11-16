defmodule Cadence.Reads.EventLog.ById do
  @moduledoc """
  U69 A8b: one Timeline entry by the id its row carries, for a permalink. Stored mission and
  operational events come from `MissionTimeline.fetch_for_mission/3`; the rows the Timeline
  merges in (applied configuration revisions, off-plan bookings) are rebuilt from their own
  records, whose ids are `mission_event:<mission>:<kind>:<record id>`.
  """

  alias Cadence.Reads.{ConfigRevisionEvents, MissionTimeline, OffPlanBookingEvents}

  @spec entry(binary(), binary(), binary()) :: {:ok, map()} | :error
  def entry(organization_id, mission_id, id) do
    case MissionTimeline.fetch_for_mission(organization_id, mission_id, id) do
      {:ok, entry} -> {:ok, entry}
      {:error, _not_stored} -> merged(organization_id, mission_id, id)
    end
  end

  defp merged(organization_id, mission_id, id) do
    prefix = "mission_event:" <> mission_id <> ":"

    case String.split_at(id, String.length(prefix)) do
      {^prefix, "off_plan_booking:" <> pass_id} ->
        OffPlanBookingEvents.entry_for(organization_id, mission_id, pass_id)

      {^prefix, "config_revision:" <> number} ->
        case Integer.parse(number) do
          {n, ""} when n > 0 -> ConfigRevisionEvents.entry_for(organization_id, mission_id, n)
          _invalid -> :error
        end

      _other ->
        :error
    end
  end
end
