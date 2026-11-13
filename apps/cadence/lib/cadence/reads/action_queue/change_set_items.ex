defmodule Cadence.Reads.ActionQueue.ChangeSetItems do
  @moduledoc """
  The `change_set_stale` item of the action queue (BACKLOG §8 8d; ux Changes.md §2: "In Ops,
  nothing about staging shows, except a Now P3 item when a change set has been sitting for more
  than 24 h"). P3, state `off`, at most one per mission: the mission's active change set (open
  or in review) when its oldest staged change was staged more than 24 h ago. A set whose
  changes were all withdrawn has nothing staged and raises nothing.
  """

  alias Cadence.Configuration.Status
  alias Cadence.Reads.ActionQueue.Item

  @stale_after_s 24 * 3_600

  @doc "How long a staged change sits before the item appears (seconds)."
  @spec stale_after_s() :: pos_integer()
  def stale_after_s, do: @stale_after_s

  # todo(authz): the queue's caller authorized operate_mission; Setup shows the staged set to
  # everyone who can see Setup. Cedar should decide whether Ops viewers see change-set authors.
  @spec load(binary(), binary(), DateTime.t()) :: [map()]
  def load(organization_id, mission_id, now) do
    items(Status.current(organization_id, mission_id).change_set, now)
  end

  @doc "Pure: the item for `change_set` (`Status.current/2`'s view, or nil) at `now`."
  @spec items(map() | nil, DateTime.t()) :: [map()]
  def items(nil, _now), do: []

  def items(%{changes: changes} = set, now) do
    case changes |> Enum.map(& &1.staged_at) |> Item.min_datetime() do
      %DateTime{} = oldest ->
        if DateTime.diff(now, oldest) > @stale_after_s, do: [item(set, oldest)], else: []

      nil ->
        []
    end
  end

  defp item(set, oldest) do
    Item.new(%{
      id: "change_set_stale:#{set.id}",
      priority: 3,
      kind: :change_set_stale,
      state: :off,
      since: oldest,
      count: set.staged_count,
      change_set: %{
        id: set.id,
        state: set.state,
        staged_count: set.staged_count,
        base_revision: set.base_revision,
        opened_at: set.opened_at,
        oldest_staged_at: oldest,
        submitted_at: set.submitted_at,
        authors: set.authors
      }
    })
  end
end
