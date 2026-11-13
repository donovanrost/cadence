defmodule CadenceWeb.Console.ActionQueueJSON do
  @moduledoc "Wire shape of the console action queue. Contract: docs/apogee/api/ops.md."

  alias CadenceWeb.Console.WireValue

  @spec queue(map()) :: map()
  def queue(queue) do
    %{
      observed_at: queue.observed_at,
      stale_after_s: queue.stale_after_s,
      failure_lookback_s: queue.failure_lookback_s,
      alarms_truncated: queue.alarms_truncated,
      counts: queue.counts,
      items: Enum.map(queue.items, &item/1),
      resolved: Map.get(queue, :resolved, []),
      missed_pass_horizon_s: Map.get(queue, :missed_pass_horizon_s)
    }
  end

  defp item(item) do
    %{
      id: item.id,
      priority: item.priority,
      kind: Atom.to_string(item.kind),
      state: Atom.to_string(item.state),
      since: item.since,
      due_at: item.due_at,
      count: item.count,
      spacecraft: Enum.map(item.spacecraft, &member/1),
      point: item.point,
      condition: item.condition,
      source: item.source && to_string(item.source),
      acknowledged: item.acknowledged,
      plane: item.plane,
      command: item.command,
      outcome: item.outcome && Atom.to_string(item.outcome),
      command_requests: Enum.map(item.command_requests, &request/1),
      command_groups: item.command_groups,
      finding: finding(item.finding),
      attention: item.attention,
      missed_passes: item.missed_passes,
      next_contact: item.next_contact,
      station_issue: station_issue(item.station_issue),
      event: item.event,
      change_set: item.change_set
    }
  end

  defp member(member) do
    %{
      member
      | value: WireValue.encode(member.value),
        status: member.status && Atom.to_string(member.status)
    }
  end

  defp request(request), do: %{request | status: to_string(request.status)}

  defp station_issue(nil), do: nil

  defp station_issue(%{window: window} = issue),
    do: %{issue | window: %{window | kind: to_string(window.kind)}}

  defp finding(nil), do: nil

  defp finding(finding) do
    %{
      id: finding.id,
      area: to_string(finding.area),
      severity: to_string(finding.severity),
      cause: to_string(finding.cause),
      title: finding.title,
      body: finding.body,
      affected_count: finding.affected_count,
      fix: finding.fix
    }
  end
end
