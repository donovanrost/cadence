defmodule CadenceWeb.Console.ActionQueueJSON do
  @moduledoc "Wire shape of the console action queue. Contract: docs/apogee/api/ops.md."

  alias CadenceWeb.Console.WireValue

  @spec queue(map()) :: map()
  def queue(queue) do
    %{
      observed_at: queue.observed_at,
      stale_after_s: queue.stale_after_s,
      failure_lookback_s: queue.failure_lookback_s,
      counts: queue.counts,
      items: Enum.map(queue.items, &item/1)
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
      plane: item.plane,
      command: item.command,
      outcome: item.outcome && Atom.to_string(item.outcome),
      command_requests: Enum.map(item.command_requests, &request/1),
      finding: finding(item.finding)
    }
  end

  defp member(member), do: %{member | value: WireValue.encode(member.value)}

  defp request(request), do: %{request | status: to_string(request.status)}

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
