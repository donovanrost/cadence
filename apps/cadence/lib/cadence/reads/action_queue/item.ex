defmodule Cadence.Reads.ActionQueue.Item do
  @moduledoc "Shared item and member shapes for `Cadence.Reads.ActionQueue`."

  @doc "An item with every field present; fields that don't apply to its kind are `nil` / `[]`."
  @spec new(map()) :: map()
  def new(fields) do
    Map.merge(
      %{
        since: nil,
        due_at: nil,
        spacecraft: [],
        point: nil,
        condition: nil,
        source: nil,
        acknowledged: nil,
        plane: nil,
        command: nil,
        outcome: nil,
        command_requests: [],
        command_groups: [],
        finding: nil,
        attention: nil,
        missed_passes: nil,
        next_contact: nil,
        station_issue: nil,
        event: nil,
        change_set: nil
      },
      fields
    )
  end

  @doc "A spacecraft member of an item, from a `Cadence.Reads.FleetStatus` row."
  @spec member(map()) :: map()
  def member(craft) do
    %{
      id: craft.id,
      name: craft.name,
      scid: craft.scid,
      plane: craft.plane,
      stale: craft.stale,
      last_received_at: craft.last_received_at,
      violating_points: craft.violating_points,
      value: nil,
      first_crossed_at: nil,
      episode_id: nil,
      status: nil,
      acknowledged_by: nil,
      assignee: nil
    }
  end

  @doc "`a` is no later than `b`; `nil` sorts last."
  @spec earlier?(DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  def earlier?(nil, _b), do: false
  def earlier?(_a, nil), do: true
  def earlier?(a, b), do: DateTime.compare(a, b) != :gt

  @spec min_datetime([DateTime.t() | nil]) :: DateTime.t() | nil
  def min_datetime(datetimes) do
    case Enum.reject(datetimes, &is_nil/1) do
      [] -> nil
      present -> Enum.min(present, DateTime)
    end
  end
end
