defmodule Cadence.Commanding.Groups.Waiting do
  @moduledoc """
  Command groups waiting on an uplink (#58): which source endpoints a group targets, and which
  groups still have queued members on given endpoints. The console uses these to say which
  pass a group waits for, and whether a blocked pass holds any group back.
  """

  import Ecto.Query

  alias Cadence.Commanding.CommandRequestRow
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
end
