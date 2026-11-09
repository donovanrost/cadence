defmodule Cadence.Reads.CommandGroups do
  @moduledoc """
  Command groups for the console (docs/apogee/domain/group-requests.md §6):
  the list (with `awaiting_me` for the Approve queue) and one group with its
  events and per-target progress for Uplink & verify.

  A member's `stage` comes from the existing command status
  (`Cadence.Reads.Commands`), so Uplink shows exactly what the commands pages
  show:

      awaiting_go | queued_for_contact | radiating | executed | verified
      | no_verifier | verify_failed | release_failed | indeterminate
      | canceled | rejected | excluded

  `end_reason` says why a member ended without radiating (`aborted`,
  `release_basis_changed`, `earlier_command_failed`, `expired`, `excluded_at_review`,
  `canceled`, `rejected`). A target's `stage` is the stage of its first
  unfinished member, or of its last member when all are finished.
  """

  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.Reads.Commands

  @finished ~w(verified no_verifier verify_failed release_failed indeterminate canceled rejected excluded)a

  @spec list(binary(), binary(), binary() | nil, keyword()) :: [map()]
  def list(org, mission, viewer_id, opts \\ []) do
    groups =
      GroupStore.list(org, mission,
        states: Keyword.get(opts, :states),
        limit: Keyword.get(opts, :limit, 100)
      )

    groups
    |> Enum.map(&Map.put(summary(&1), :awaiting_me, awaiting?(&1, viewer_id)))
    |> filter(Keyword.get(opts, :awaiting_me), Keyword.get(opts, :mine), viewer_id)
  end

  @spec fetch_by_operation(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def fetch_by_operation(org, mission, operation_id) do
    with {:ok, group} <- GroupStore.fetch_by_operation(org, mission, operation_id),
         do: {:ok, summary(group)}
  end

  @spec get(binary(), binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :command_group_not_found}
  def get(org, mission, id, viewer_id) do
    with {:ok, group} <- GroupStore.fetch(org, mission, id) do
      members = GroupStore.members(org, mission, id)
      rows = command_rows(org, mission, members)
      excluded = excluded_indexes(group)

      member_views =
        Enum.map(members, fn request ->
          member(request, Map.get(rows, request.command_request_id), excluded)
        end)

      targets = targets(group, member_views)

      {:ok,
       group
       |> summary()
       |> Map.merge(%{
         awaiting_me: awaiting?(group, viewer_id),
         group: group,
         targets: targets,
         progress: Enum.frequencies_by(targets, & &1.stage),
         events: GroupStore.events(mission, id)
       })}
    end
  end

  @doc "Whether `viewer_id` may give this group its second GO."
  @spec awaiting?(CommandGroup.t(), binary() | nil) :: boolean()
  def awaiting?(%CommandGroup{} = group, viewer_id) do
    group.state == :approval_pending and is_binary(viewer_id) and
      group.requested_by["user_id"] != viewer_id and
      group.requested_approver_user_id in [nil, viewer_id]
  end

  defp summary(%CommandGroup{} = group) do
    %{
      id: group.command_group_id,
      state: group.state,
      title: group.title,
      requested_by: group.requested_by,
      requested_at: group.requested_at,
      requested_approver_user_id: group.requested_approver_user_id,
      member_count: group.member_count,
      target_count: length(group.targets),
      command_count: length(group.commands),
      second_go_required: group.policy["second_go_required"] == true,
      operation_id: group.operation_id
    }
  end

  defp filter(groups, true, _mine, _viewer), do: Enum.filter(groups, & &1.awaiting_me)

  defp filter(groups, _awaiting, true, viewer),
    do: Enum.filter(groups, &(&1.requested_by["user_id"] == viewer))

  defp filter(groups, _awaiting, _mine, _viewer), do: groups

  defp command_rows(_org, _mission, []), do: %{}

  defp command_rows(org, mission, members) do
    org
    |> Commands.snapshot(mission,
      requests: fn _org, _mission, _opts -> members end,
      target_names: fn _, _, _ -> %{} end
    )
    |> Map.fetch!(:rows)
    |> Map.new(&{&1.command_request_id, &1})
  end

  defp excluded_indexes(
         %CommandGroup{decision: %{"kind" => "go_excluding", "excluded" => excluded}} = group
       ) do
    group.targets
    |> Enum.filter(&(&1["spacecraft_id"] in excluded))
    |> MapSet.new(& &1["index"])
  end

  defp excluded_indexes(_group), do: MapSet.new()

  defp member(request, row, excluded) do
    group = request.metadata["group"]
    stage = stage(request, row, MapSet.member?(excluded, group["target_index"]))

    %{
      position: group["position"],
      target_index: group["target_index"],
      request_id: request.command_request_id,
      command_id: request.command_id,
      command_name: request.command_name,
      stage: stage,
      end_reason: end_reason(request, stage),
      verify_by: verify_by(row),
      occurred_at: row && row.occurred_at
    }
  end

  defp stage(%{lifecycle_state: :approval_pending}, _row, _excluded), do: :awaiting_go
  defp stage(%{lifecycle_state: :rejected}, _row, true), do: :excluded
  defp stage(%{lifecycle_state: :rejected}, _row, false), do: :rejected
  defp stage(%{lifecycle_state: :canceled}, _row, _excluded), do: :canceled
  defp stage(_request, nil, _excluded), do: :queued_for_contact
  defp stage(_request, row, _excluded), do: row_stage(row)

  defp row_stage(%{status: :release_pending}), do: :radiating
  defp row_stage(%{status: :in_flight}), do: :executed
  defp row_stage(%{status: :indeterminate}), do: :indeterminate

  defp row_stage(%{status: :failed, release_attempt: %{lifecycle_state: :release_failed}}),
    do: :release_failed

  defp row_stage(%{status: :failed}), do: :verify_failed
  defp row_stage(%{status: :released, verification_state: :satisfied}), do: :verified
  defp row_stage(%{status: :released}), do: :no_verifier
  defp row_stage(_row), do: :queued_for_contact

  defp end_reason(request, :canceled) do
    case request.metadata["cancellation"]["reason"] do
      "aborted: " <> _ -> :aborted
      "release_basis_changed" -> :release_basis_changed
      "earlier_command_failed" <> _ -> :earlier_command_failed
      "expired" -> :expired
      _other -> :canceled
    end
  end

  defp end_reason(_request, :excluded), do: :excluded_at_review
  defp end_reason(_request, :rejected), do: :rejected
  defp end_reason(_request, _stage), do: nil

  defp verify_by(%{verifier_instances: [_ | _] = instances}) do
    instances
    |> Enum.map(& &1.timeout_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp verify_by(_row), do: nil

  defp targets(group, members) do
    by_target = Enum.group_by(members, & &1.target_index)

    Enum.map(group.targets, fn target ->
      own = by_target |> Map.get(target["index"], []) |> Enum.sort_by(& &1.position)

      %{
        spacecraft_id: target["spacecraft_id"],
        name: target["name"],
        scid: target["scid"],
        stage: target_stage(own),
        members: own,
        last_event_at:
          own
          |> Enum.map(& &1.occurred_at)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(DateTime, fn -> nil end),
        blocked: nil
      }
    end)
  end

  defp target_stage([]), do: :excluded

  defp target_stage(members) do
    case Enum.find(members, &(&1.stage not in @finished)) do
      nil -> List.last(members).stage
      unfinished -> unfinished.stage
    end
  end
end
