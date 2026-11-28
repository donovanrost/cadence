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
  `release_basis_changed`, `earlier_command_failed`, `expired`, `catalog_changed`,
  `spacecraft_archived`, `excluded_at_review`, `canceled`, `rejected`). A target's `stage` is the
  stage of its first unfinished member, or of its last member when all are finished.
  """

  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore, MemberCheck}
  alias Cadence.Reads.{CommandCatalog, Commands}
  alias Cadence.Reads.CommandGroups.{Expiry, ReleaseRefusals, VerifyTimes, WithdrawnAfterGo}
  alias Cadence.Reads.CommandPreflight.{ResolvedArguments, VerifierGroups}

  # Final member stages. `indeterminate` (an uncertain release) isn't: an operator must resolve
  # it, so its group isn't finished (and gets no `completed` event, DECISIONS #51).
  @finished ~w(verified no_verifier verify_failed release_failed canceled rejected excluded)a

  @spec list(binary(), binary(), binary() | nil, keyword()) :: [map()]
  def list(org, mission, viewer_id, opts \\ []) do
    groups =
      GroupStore.list(org, mission,
        states: Keyword.get(opts, :states),
        limit: Keyword.get(opts, :limit, 100)
      )

    org
    |> rows(mission, groups, viewer_id)
    |> filter(Keyword.get(opts, :awaiting_me), Keyword.get(opts, :mine), viewer_id)
  end

  @doc """
  The armed groups with a member still waiting for its contact on a craft that runs `revision_id`
  (a withdrawn model approval's reach; E2, #546): `%{groups, total}`, newest GO first, `limit`
  50 by default (at most 200). See `CommandGroups.GoUnreleased`.
  """
  @spec go_unreleased(binary(), binary(), binary(), keyword()) ::
          %{groups: [map()], total: non_neg_integer()}
  defdelegate go_unreleased(org, mission, revision_id, opts \\ []),
    to: Cadence.Reads.CommandGroups.GoUnreleased,
    as: :read

  @doc """
  U69 A5: the Commands list, searched and paged (`CommandGroups.Search`): `{:ok, %{groups,
  next_cursor}}` or `{:error, :invalid_cursor}`.
  """
  @spec page(binary(), binary(), binary() | nil, keyword()) ::
          {:ok, %{groups: [map()], next_cursor: binary() | nil}} | {:error, :invalid_cursor}
  defdelegate page(org, mission, viewer_id, opts), to: Cadence.Reads.CommandGroups.Search

  @doc false
  # List rows for `groups`: the summary, awaiting_me, and a queued group's delivery progress.
  def rows(org, mission, groups, viewer_id) do
    delivery = delivery(org, mission, groups)

    Enum.map(groups, fn group ->
      group
      |> summary()
      |> Map.put(:awaiting_me, awaiting?(group, viewer_id))
      |> Map.merge(
        Map.get(delivery, group.command_group_id, %{progress: nil, finished: nil, expiry: nil})
      )
    end)
  end

  # Group state is the approval lifecycle only, so a delivered group still reads `queued`.
  # List rows of queued groups carry the same `progress` as the show plus `finished` (every
  # target at a final stage), so the list can say "delivered" without opening each group.
  # Other states get `nil`: their state already says how they ended.
  defp delivery(org, mission, groups) do
    queued = Enum.filter(groups, &(&1.state == :queued))
    members = GroupStore.members_of(org, mission, Enum.map(queued, & &1.command_group_id))
    rows = command_rows(org, mission, members |> Map.values() |> List.flatten())

    Map.new(queued, fn group ->
      targets =
        target_views(group, Map.get(members, group.command_group_id, []), rows, fn _, _ ->
          nil
        end)

      {group.command_group_id,
       %{
         progress: Enum.frequencies_by(targets, & &1.stage),
         finished: Enum.all?(targets, &(&1.stage in @finished)),
         # U75: how its expiry went, when it did.
         expiry: Expiry.summary(group, targets)
       }}
    end)
  end

  defp target_views(group, members, rows, blocked_fun) do
    excluded = excluded_indexes(group)

    member_views =
      Enum.map(members, fn request ->
        member(request, Map.get(rows, request.command_request_id), excluded)
      end)

    targets(group, member_views, blocked_fun)
  end

  @spec fetch_by_operation(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def fetch_by_operation(org, mission, operation_id) do
    with {:ok, group} <- GroupStore.fetch_by_operation(org, mission, operation_id) do
      delivery = delivery(org, mission, [group])

      {:ok,
       group
       |> summary()
       |> Map.merge(
         Map.get(delivery, group.command_group_id, %{progress: nil, finished: nil, expiry: nil})
       )}
    end
  end

  @spec get(binary(), binary(), binary(), binary() | nil) ::
          {:ok, map()} | {:error, :command_group_not_found}
  def get(org, mission, id, viewer_id) do
    with {:ok, group} <- GroupStore.fetch(org, mission, id) do
      members = GroupStore.members(org, mission, id)
      rows = command_rows(org, mission, members)
      held = held_lanes(org, mission, members)
      lanes = Map.new(members, &{&1.group_slot.target_index, &1.source_endpoint_ref})
      events = GroupStore.events(mission, id)

      {targets, withdrawn_after_go} =
        group
        |> target_views(members, rows, &blocked(&1, &2, lanes, held))
        |> ReleaseRefusals.put(events, org, mission)
        |> WithdrawnAfterGo.put(org, mission)

      revision_id = members |> List.first() |> then(&(&1 && &1.mission_model_revision_id))

      {:ok,
       group
       |> summary()
       |> Map.merge(%{
         awaiting_me: awaiting?(group, viewer_id),
         catalog_revision: CommandCatalog.catalog_revision(org, mission, revision_id),
         group: group,
         targets: targets,
         withdrawn_after_go: withdrawn_after_go,
         progress: Enum.frequencies_by(targets, & &1.stage),
         finished: Enum.all?(targets, &(&1.stage in @finished)),
         expiry: Expiry.summary(group, targets),
         events: events,
         # U2: per stacked command, which targets share which verifiers (as Compose's preflight).
         verifier_groups: VerifierGroups.for_group(org, mission, group, members),
         # U68 R1: where the server's values differ from what was entered.
         resolved_arguments: ResolvedArguments.for_group(org, mission, group, members)
       })
       # #120 (ux U92 "Up front"): the GO refusal's own member test, from the rows loaded above.
       |> Map.merge(MemberCheck.read_fields(group, members))}
    end
  end

  @doc "The draft a group was submitted from (Compose clones it; review re-runs preflight on it)."
  @spec draft_of(CommandGroup.t()) :: map()
  def draft_of(%CommandGroup{} = group) do
    %{
      title: group.title,
      log_entry: group.log_entry,
      requested_approver_user_id: group.requested_approver_user_id,
      target_query: group.target_query,
      targets:
        Enum.map(
          group.targets,
          &%{spacecraft_id: &1["spacecraft_id"], source_endpoint_id: &1["source_endpoint_id"]}
        ),
      commands:
        group.commands
        |> Enum.sort_by(& &1["position"])
        |> Enum.map(
          &%{
            command_id: &1["command_id"],
            argument_values: &1["argument_values"] || %{},
            per_target: &1["per_target"] || %{}
          }
        ),
      not_before: parse_time(group.release["not_before"]),
      expires_at: parse_time(group.release["expires_at"]),
      priority: group.release["priority"] || 3
    }
  end

  defp parse_time(nil), do: nil
  defp parse_time(%DateTime{} = at), do: at

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _error -> nil
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
      operation_id: group.operation_id,
      # U68: the Commands list tags High / Low (0..9, lower releases sooner in its lane).
      priority: (group.release || %{})["priority"]
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
    stage = stage(request, row, MapSet.member?(excluded, request.group_slot.target_index))

    %{
      position: request.group_slot.position,
      target_index: request.group_slot.target_index,
      request_id: request.command_request_id,
      command_id: request.command_id,
      command_name: request.command_name,
      stage: stage,
      end_reason: end_reason(request, stage),
      caused_by: caused_by(request),
      occurred_at: row && row.occurred_at
    }
    # verify_by, and (U69 A4a) verified_at, timed_out_at, failed_at.
    |> Map.merge(VerifyTimes.fields(row))
  end

  defp stage(%{lifecycle_state: :approval_pending}, _row, _excluded), do: :awaiting_go
  defp stage(%{lifecycle_state: :rejected}, _row, true), do: :excluded
  defp stage(%{lifecycle_state: :rejected}, _row, false), do: :rejected
  # A release refused by the uplink (#33) cancels the request and fails its attempt.
  defp stage(
         %{lifecycle_state: :canceled},
         %{release_attempt: %{lifecycle_state: :release_failed}},
         _
       ),
       do: :release_failed

  defp stage(%{lifecycle_state: :canceled}, _row, _excluded), do: :canceled
  defp stage(_request, nil, _excluded), do: :queued_for_contact
  defp stage(_request, row, _excluded), do: row_stage(row)

  # A command status row's member stage (also Investigate's Uplink tab, released rows).
  @doc false
  def row_stage(%{status: :release_pending}), do: :radiating
  def row_stage(%{status: :in_flight}), do: :executed
  def row_stage(%{status: :indeterminate}), do: :indeterminate

  def row_stage(%{status: :failed, release_attempt: %{lifecycle_state: :release_failed}}),
    do: :release_failed

  def row_stage(%{status: :failed}), do: :verify_failed
  def row_stage(%{status: :released, verification_state: :satisfied}), do: :verified
  def row_stage(%{status: :released}), do: :no_verifier
  def row_stage(_row), do: :queued_for_contact

  defp end_reason(request, :canceled) do
    case request.metadata["cancellation"]["reason"] do
      "aborted: " <> _ -> :aborted
      "release_basis_changed" -> :release_basis_changed
      # E2 (#546): a lane draining itself found a withdrawal its GO hadn't seen.
      "model_approval_withdrawn_after_go" -> :model_approval_withdrawn_after_go
      "earlier_command_failed" <> _ -> :earlier_command_failed
      "expired" -> :expired
      # DECISIONS #65: a catalog change set canceled it before release.
      "catalog_changed" <> _ -> :catalog_changed
      # L22: its spacecraft was archived before it released; it never goes out.
      "spacecraft_archived" -> :spacecraft_archived
      _other -> :canceled
    end
  end

  defp end_reason(_request, :excluded), do: :excluded_at_review
  defp end_reason(_request, :rejected), do: :rejected
  defp end_reason(_request, _stage), do: nil

  # The earlier member whose failure stopped this one (stop on failure per target).
  defp caused_by(request) do
    case request.metadata["cancellation"]["reason"] do
      "earlier_command_failed: " <> id -> id
      _other -> nil
    end
  end

  # Lanes held by a release whose outcome is unknown (`release_uncertain`): nothing behind it
  # releases until an operator resolves it. `%{lane => command_request_id}`.
  defp held_lanes(_org, _mission, []), do: %{}

  defp held_lanes(org, mission, members) do
    lanes = members |> MapSet.new(& &1.source_endpoint_ref)

    org
    |> Cadence.Commanding.list_command_release_attempts(mission)
    |> Enum.filter(&(&1.lifecycle_state == :release_uncertain))
    |> Enum.map(&{&1.source_endpoint_ref, &1.command_request_id})
    |> Enum.filter(fn {lane, _id} -> MapSet.member?(lanes, lane) end)
    |> Map.new()
  end

  # A target waiting for its contact is blocked when its lane is held by another request's
  # uncertain release.
  defp blocked(target_index, :queued_for_contact, lanes, held) do
    case Map.fetch(held, Map.get(lanes, target_index)) do
      {:ok, request_id} -> %{reason: :lane_release_uncertain, command_request_id: request_id}
      :error -> nil
    end
  end

  defp blocked(_target_index, _stage, _lanes, _held), do: nil

  defp targets(group, members, blocked_fun) do
    by_target = Enum.group_by(members, & &1.target_index)

    Enum.map(group.targets, fn target ->
      own = by_target |> Map.get(target["index"], []) |> Enum.sort_by(& &1.position)

      %{
        index: target["index"],
        spacecraft_id: target["spacecraft_id"],
        name: target["name"],
        scid: target["scid"],
        stage: target_stage(own),
        members: own,
        blocked: blocked_fun.(target["index"], target_stage(own)),
        last_event_at:
          own
          |> Enum.map(& &1.occurred_at)
          |> Enum.reject(&is_nil/1)
          |> Enum.max(DateTime, fn -> nil end)
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
