defmodule Cadence.Control.Commanding.GroupDecision do
  @moduledoc """
  The second operator's decision on a command group
  (docs/apogee/domain/group-requests.md §3): `go`, `go_excluding` (named
  targets' members are rejected "excluded at review"), `send_back` or `no_go`.

  One decision covers every member: a `command_approvals` row per member keeps
  per-request audit intact, then approved members are enqueued in stack order
  per lane. The approver is the authenticated human, never the requester, and
  the named approver when the requester picked one. Decisions re-check the
  command-catalog snapshot under its lock; if the activation changed since
  submit the group must be resubmitted.
  """

  alias Cadence.Commanding.{
    AuthoringIdentity,
    CommandApproval,
    Dispatcher,
    ProcessNamespace,
    RequestValidation
  }

  alias Cadence.Commanding.Groups.{Admission, CommandGroup, GroupStore}
  alias Cadence.Governance.Accountability
  alias Cadence.Management.Commanding.{ApprovedCommand, RequestAuthoring, RequestReview}
  alias Cadence.Platform.ScopedReadUpdates

  @kinds ~w(go go_excluding send_back no_go)a
  @group_states %{go: :queued, go_excluding: :queued, send_back: :sent_back, no_go: :rejected}

  @doc """
  Token for optimistic review: changes whenever the group's reviewable content does, including
  WHICH requests are its members (#117 step 4a, the members digest: swapping one member for
  another at the same count changes it). Recomputed, never stored, so no stored hash moves (#108).
  """
  @spec review_token(CommandGroup.t()) :: binary()
  def review_token(%CommandGroup{} = group),
    do:
      AuthoringIdentity.digest(
        {group.command_group_id, group.state, group.preflight, group.member_count,
         members_digest(group)}
      )

  @doc """
  The members digest (four-eyes design, 'Command groups: the members digest'): over the group's
  member request ids, sorted, each with that request's own review token
  (`RequestReview.review_token/1`, its content digest; the public route to it, as QueueSubmission's).
  """
  @spec members_digest(CommandGroup.t()) :: binary()
  def members_digest(%CommandGroup{} = group) do
    entries =
      group.organization_id
      |> GroupStore.members(group.mission_id, group.command_group_id)
      |> Enum.map(&[&1.command_request_id, RequestReview.review_token(&1)])
      |> Enum.sort()

    AuthoringIdentity.digest({:command_group_members_v1, entries})
  end

  @spec decide(Cadence.Auth.Scope.t(), binary(), binary(), map()) ::
          {:ok, CommandGroup.t()} | {:error, term()}
  # todo(authz): Cedar should decide who may GO / NO-GO / send back this group (DECISIONS #62:
  # any mission operator today, minus self-approval), e.g. by hazard, fleet reach or subsystem.
  def decide(scope, mission_id, group_id, decision) do
    with {:ok, fresh, _mission} <- RequestAuthoring.authorize(scope, mission_id),
         :ok <- valid_decision(decision) do
      org = fresh.organization_id
      actor = %{"actor_kind" => "user", "user_id" => fresh.user.user_id}
      # #117 step 4b: the record's admin_mode, from the decider's own scope.
      decision = Map.put(decision, :admin_mode, fresh.admin_mode? == true)

      org
      |> RequestValidation.with_authoring_catalog(
        mission_id,
        &locked(&1, org, mission_id, group_id, actor, decision)
      )
      |> after_commit(org, mission_id)
    end
  end

  defp valid_decision(%{kind: kind} = decision) when kind in @kinds do
    cond do
      kind != :go and blank?(Map.get(decision, :note)) ->
        {:error, :note_required}

      kind == :go_excluding and Map.get(decision, :excluded, []) == [] ->
        {:error, :exclusions_required}

      true ->
        :ok
    end
  end

  defp valid_decision(_decision), do: {:error, :invalid_decision}

  defp locked(snapshot, org, mission, group_id, actor, decision) do
    with {:ok, group} <- GroupStore.fetch(org, mission, group_id, lock: true),
         :ok <- decidable(group, actor, decision),
         :ok <- same_basis(group, snapshot),
         :ok <- members_as_submitted(group, decision) do
      apply_decision(group, actor, decision)
    end
  end

  defp decidable(group, actor, decision) do
    with :ok <- pending(group),
         :ok <- separated(group, actor),
         do: decidable_rest(group, actor, decision)
  end

  defp pending(%{state: :approval_pending}), do: :ok
  defp pending(_group), do: {:error, :command_group_not_pending}

  # #622 (#280): the requester counts as people, as on a single request (LifecyclePolicy): a service
  # requester is its issuer and rotators, and a service nobody is accountable for refuses everyone.
  # ca-security on #626: a decider who isn't a person is refused here, on its own (fail closed).
  defp separated(_group, %{"user_id" => id}) when not is_binary(id) or id == "",
    do: {:error, :command_group_self_approval_not_allowed}

  defp separated(_group, actor) when not is_map_key(actor, "user_id"),
    do: {:error, :command_group_self_approval_not_allowed}

  defp separated(group, actor) do
    group.organization_id
    |> Accountability.separate({:user, actor["user_id"]}, separation_authors(group))
    |> Accountability.refusal(
      :command_group_self_approval_not_allowed,
      :command_group_approver_authors_unknown
    )
  end

  # The authors the separation check is given (the requester, as stored); #117 step 4b records
  # exactly these as each member approval's separated_from (domain).
  defp separation_authors(group), do: [group.requested_by]

  defp separated_from(group), do: group |> separation_authors() |> Accountability.ids()

  defp decidable_rest(group, actor, decision) do
    cond do
      group.requested_approver_user_id not in [nil, actor["user_id"]] ->
        {:error, :not_the_requested_approver}

      stale?(group, decision) ->
        {:error, :command_group_review_stale}

      not known_targets?(group, Map.get(decision, :excluded, [])) ->
        {:error, :unknown_excluded_target}

      true ->
        :ok
    end
  end

  # #117 step 4a (domain, ca-security): a GO, with or without exclusions, must carry the token the
  # reviewer saw (fail closed: the console always sends it), recomputed here under the group lock.
  # Send back and NO-GO keep it optional, as before.
  defp stale?(group, %{kind: kind} = decision) when kind in [:go, :go_excluding],
    do: Map.get(decision, :expected_review) != review_token(group)

  defp stale?(group, decision),
    do: Map.get(decision, :expected_review) not in [nil, review_token(group)]

  defp known_targets?(group, excluded) do
    ids = MapSet.new(group.targets, & &1["spacecraft_id"])
    Enum.all?(excluded, &MapSet.member?(ids, &1))
  end

  # A GO acts on the group's member rows, but the review token covers only the group row's
  # member_count, not the member ids. A GO on a group whose member rows no longer match what
  # submission recorded is refused (four-eyes audit 11-17, P0, defence in depth). Send back and
  # NO-GO stay allowed: they release nothing, and a group nobody can stop is worse (ux U92).
  defp members_as_submitted(group, %{kind: kind}) when kind in [:go, :go_excluding] do
    current =
      group.organization_id
      |> GroupStore.members(group.mission_id, group.command_group_id)
      |> length()

    if current == group.member_count,
      do: :ok,
      else: {:error, {:command_group_members_changed, group.member_count, current}}
  end

  defp members_as_submitted(_group, _decision), do: :ok

  defp same_basis(group, snapshot) do
    if group.basis["token"] == snapshot.token,
      do: :ok,
      else: {:error, :command_group_basis_changed}
  end

  defp apply_decision(group, actor, decision) do
    now = DateTime.utc_now()
    # Before anything changes: the members the decider's token covered (#117 step 4b records it).
    members_digest = members_digest(group)
    members = GroupStore.members(group.organization_id, group.mission_id, group.command_group_id)
    {approved, rejected} = split(members, group, decision)
    note = Map.get(decision, :note)
    record = %{separated_from: separated_from(group), admin_mode: decision.admin_mode}

    approvals =
      Enum.map(approved, &approval(&1, :approved, actor, now, note, record)) ++
        Enum.map(
          rejected,
          &approval(&1, :rejected, actor, now, rejection_reason(decision, note), record)
        )

    :ok = GroupStore.insert_approvals(approvals)

    :ok =
      GroupStore.set_member_state(
        group.organization_id,
        group.mission_id,
        Enum.map(rejected, & &1.command_request_id),
        :rejected
      )

    approved_by_id = Map.new(approvals, &{&1.command_request_id, &1})
    queued = Enum.map(approved, &%{&1 | lifecycle_state: :queued})

    :ok =
      GroupStore.set_member_state(
        group.organization_id,
        group.mission_id,
        Enum.map(queued, & &1.command_request_id),
        :queued
      )

    entries =
      Admission.enqueue(
        queued,
        actor,
        &approved_hash(&1, Map.fetch!(approved_by_id, &1.command_request_id))
      )

    with {:ok, updated} <-
           GroupStore.update_group(%{
             group
             | state: Map.fetch!(@group_states, decision.kind),
               decided_by: actor,
               decided_at: now,
               decision: %{
                 "kind" => to_string(decision.kind),
                 "excluded" => Map.get(decision, :excluded, []),
                 "note" => note,
                 # #117 step 4b (required): which members were decided, and which a GO excluded.
                 "members_digest" => members_digest,
                 "excluded_request_ids" => excluded_request_ids(decision, rejected)
               }
           }) do
      :ok =
        GroupStore.append_events([
          %{
            command_group_id: group.command_group_id,
            mission_id: group.mission_id,
            kind: event_kind(decision.kind),
            actor: actor,
            at: now,
            payload: %{
              "note" => note,
              "excluded" => Map.get(decision, :excluded, []),
              "approved" => length(approved)
            }
          }
          | hold_events(group, actor, now, Map.get(decision, :hold_acks, []))
        ])

      {:ok, %{group: updated, lanes: entries |> Enum.map(& &1.queue_lane_key) |> Enum.uniq()}}
    end
  end

  # DECISIONS #61: HOLDs the approver acknowledged at GO (new or changed since the submitter's),
  # each its own event with the approver as actor.
  defp hold_events(group, actor, at, acks) do
    Enum.map(acks, fn ack ->
      %{
        command_group_id: group.command_group_id,
        mission_id: group.mission_id,
        kind: :hold_acknowledged,
        actor: actor,
        at: at,
        payload: %{
          "key" => ack.key,
          "note" => ack.note,
          "hold_basis" => ack.hold_basis,
          "preflight_digest" => Map.get(ack, :preflight_digest),
          "evidence" => ack |> Map.get(:evidence, %{}) |> Jason.encode!() |> Jason.decode!(),
          "at_decision" => true
        }
      }
    end)
  end

  defp split(members, _group, %{kind: kind}) when kind in [:send_back, :no_go], do: {[], members}

  defp split(members, group, decision) do
    excluded =
      group.targets
      |> Enum.filter(&(&1["spacecraft_id"] in Map.get(decision, :excluded, [])))
      |> MapSet.new(& &1["index"])

    Enum.split_with(
      members,
      &(not MapSet.member?(excluded, &1.metadata["group"]["target_index"]))
    )
  end

  defp excluded_request_ids(%{kind: :go_excluding}, rejected),
    do: rejected |> Enum.map(& &1.command_request_id) |> Enum.sort()

  defp excluded_request_ids(_decision, _rejected), do: []

  # #117 step 4b: each member's approval names its own review token (what the GO covered).
  defp approval(request, decision, actor, now, reason, record) do
    CommandApproval.new(%{
      subject_digest: RequestReview.review_token(request),
      separated_from: record.separated_from,
      admin_mode: record.admin_mode,
      organization_id: request.organization_id,
      mission_id: request.mission_id,
      command_request_id: request.command_request_id,
      decision: decision,
      decided_by: actor,
      decided_at: now,
      reason: reason,
      metadata: %{"command_group_id" => request.metadata["group"]["id"]}
    })
  end

  defp approved_hash(request, approval) do
    {:ok, approved} = ApprovedCommand.new(%{request | lifecycle_state: :approved}, approval)
    %{"approved_content_sha256" => approved.content_sha256}
  end

  defp rejection_reason(%{kind: :go_excluding}, note), do: "Excluded at review: #{note}"
  defp rejection_reason(%{kind: :send_back}, note), do: "Sent back: #{note}"
  defp rejection_reason(_decision, note), do: note

  defp event_kind(:go), do: :approved
  defp event_kind(:go_excluding), do: :approved_with_exclusions
  defp event_kind(:send_back), do: :sent_back
  defp event_kind(:no_go), do: :rejected

  defp after_commit({:ok, %{group: group, lanes: lanes}}, org, mission) do
    ScopedReadUpdates.publish(:commanding_changed, org, mission)
    Enum.each(lanes, &Dispatcher.kick_lane(ProcessNamespace.default(), org, mission, &1))
    {:ok, group}
  end

  defp after_commit({:error, reason}, _org, _mission), do: {:error, reason}

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
end
