defmodule Cadence.Commanding.Groups.Waiting do
  @moduledoc """
  Command groups waiting on an uplink (#58): which source endpoints a group targets, and which
  groups still have queued members on given endpoints. The console uses these to say which
  pass a group waits for, and whether a blocked pass holds any group back.
  """

  import Ecto.Query

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Commanding.Groups.CommandGroupRow
  alias Cadence.Repo

  @doc "`%{group_id => [source_endpoint_ref]}` in target order."
  @spec endpoints(binary(), binary(), [binary()]) :: %{binary() => [binary()]}
  def endpoints(_org, _mission, []), do: %{}

  def endpoints(org, mission, group_ids) do
    from(r in CommandRequestRow,
      where:
        r.organization_id == ^org and r.mission_id == ^mission and
          r.command_group_id in ^group_ids,
      distinct: true,
      order_by: [asc: r.command_group_id, asc: r.group_target_index],
      select: {r.command_group_id, r.group_target_index, r.source_endpoint_ref}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 2))
    |> Map.new(fn {group_id, refs} -> {group_id, Enum.uniq(refs)} end)
  end

  @doc "Ids of groups with members still queued on any of `source_endpoint_refs`."
  @spec queued_on(binary(), binary(), [binary()]) :: [binary()]
  def queued_on(_org, _mission, []), do: []

  def queued_on(org, mission, source_endpoint_refs) do
    from(r in CommandRequestRow,
      where:
        r.organization_id == ^org and r.mission_id == ^mission and
          not is_nil(r.command_group_id) and r.lifecycle_state == "queued" and
          r.source_endpoint_ref in ^source_endpoint_refs,
      distinct: true,
      order_by: r.command_group_id,
      select: r.command_group_id
    )
    |> Repo.all()
  end

  @doc """
  Armed groups (`queued`, with members still queued) on the given source endpoints, oldest GO
  first: `[{source_endpoint_ref, group_id}]` (api U46 `armed_group_ids`, the order a named release
  sends them in).
  """
  @spec armed_on(binary(), binary(), [binary()]) :: [{binary(), binary()}]
  def armed_on(_org, _mission, []), do: []

  def armed_on(org, mission, source_endpoint_refs) do
    from(r in CommandRequestRow,
      join: g in CommandGroupRow,
      on:
        g.organization_id == r.organization_id and g.mission_id == r.mission_id and
          g.command_group_id == r.command_group_id,
      where:
        r.organization_id == ^org and r.mission_id == ^mission and g.state == "queued" and
          r.lifecycle_state == "queued" and r.source_endpoint_ref in ^source_endpoint_refs,
      distinct: true,
      select:
        {r.source_endpoint_ref, r.command_group_id, [g.decided_at, g.resolved_at, g.requested_at]}
    )
    |> Repo.all()
    # Sorted here, bytewise on ties (#56: no collation-dependent order).
    |> Enum.sort_by(fn {_ref, id, times} -> {armed_at(times), id} end)
    |> Enum.map(fn {ref, id, _times} -> {ref, id} end)
  end

  # When the group was armed: its GO, else when it was resolved or requested.
  defp armed_at(times) do
    case Enum.find(times, &match?(%DateTime{}, &1)) do
      nil -> 0
      at -> DateTime.to_unix(at, :microsecond)
    end
  end
end
