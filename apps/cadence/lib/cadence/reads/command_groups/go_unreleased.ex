defmodule Cadence.Reads.CommandGroups.GoUnreleased do
  @moduledoc """
  The groups a withdrawn model approval touches after their GO (E2, #546; the CTO's addition):
  `queued` groups (a group's only armed state) with at least one member still waiting for its
  contact (stage `queued_for_contact`: a queued request whose queue entry is `pending`) on a craft
  that runs the revision. Mission-model's withdraw answer lists them as `affected_groups`.

  The craft are those `Control.WithdrawnPins.affected/2` names for the mission, so a revision of
  another mission, or one no craft runs, is `%{groups: [], total: 0}`. A fixed number of queries
  for any number of craft or groups: the withdrawal's own, then a count, a page and the page's
  waiting members. Newest GO first.
  """

  import Ecto.Query

  alias Cadence.Commanding.{CommandQueueEntryRow, CommandRequestRow}
  alias Cadence.Commanding.Groups.CommandGroupRow
  alias Cadence.Control.WithdrawnPins
  alias Cadence.Repo

  @default_limit 50
  @max_limit 200

  @type group :: %{
          group_id: binary(),
          name: binary(),
          spacecraft_ids: [binary()],
          go_at: DateTime.t(),
          state: :queued
        }

  @spec read(binary(), binary(), binary(), keyword()) :: %{groups: [group()], total: integer()}
  def read(organization_id, mission_id, revision_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> clamp()

    case organization_id |> WithdrawnPins.affected(mission_id) |> Map.get(revision_id, []) do
      [] -> %{groups: [], total: 0}
      craft -> page(organization_id, mission_id, craft, limit)
    end
  end

  defp page(organization_id, mission_id, craft, limit) do
    query = waiting(organization_id, mission_id, craft)

    rows =
      query
      |> order_by([g], desc: coalesce(g.decided_at, g.requested_at), desc: g.command_group_id)
      |> limit(^limit)
      |> Repo.all()

    waiting_indexes = waiting_indexes(Enum.map(rows, & &1.command_group_id))
    named = MapSet.new(craft)

    %{
      groups: Enum.map(rows, &group(&1, waiting_indexes, named)),
      total: Repo.aggregate(query, :count)
    }
  end

  # Armed groups with a member waiting for its contact on one of the craft.
  defp waiting(organization_id, mission_id, craft) do
    from(g in CommandGroupRow,
      where:
        g.organization_id == ^organization_id and g.mission_id == ^mission_id and
          g.state == "queued",
      where:
        fragment(
          """
          EXISTS (
            SELECT 1 FROM command_requests r
            JOIN command_queue_entries q ON q.command_request_id = r.command_request_id
            WHERE r.command_group_id = ? AND r.lifecycle_state = 'queued'
              AND q.lifecycle_state = 'pending'
              AND r.group_target_index IN (
                SELECT (t->>'index')::int
                FROM jsonb_array_elements(
                  CASE WHEN jsonb_typeof(?->'value') = 'array' THEN ?->'value' ELSE '[]'::jsonb END
                ) t
                WHERE t->>'spacecraft_id' = ANY(?))
          )
          """,
          g.command_group_id,
          g.targets_document,
          g.targets_document,
          ^craft
        )
    )
  end

  # `%{group_id => MapSet of target indexes with a member waiting for its contact}`.
  defp waiting_indexes([]), do: %{}

  defp waiting_indexes(group_ids) do
    from(r in CommandRequestRow,
      join: q in CommandQueueEntryRow,
      on: q.command_request_id == r.command_request_id,
      where:
        r.command_group_id in ^group_ids and r.lifecycle_state == "queued" and
          q.lifecycle_state == "pending",
      distinct: true,
      select: {r.command_group_id, r.group_target_index}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, indexes} -> {id, MapSet.new(indexes)} end)
  end

  defp group(row, waiting_indexes, named) do
    group = CommandGroupRow.to_domain(row)
    indexes = Map.get(waiting_indexes, group.command_group_id, MapSet.new())

    craft =
      for target <- group.targets,
          MapSet.member?(indexes, target["index"]),
          MapSet.member?(named, target["spacecraft_id"]),
          do: target["spacecraft_id"]

    %{
      group_id: group.command_group_id,
      name: group.title,
      spacecraft_ids: craft,
      go_at: group.decided_at || group.requested_at,
      state: :queued
    }
  end

  defp clamp(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp clamp(_other), do: @default_limit
end
