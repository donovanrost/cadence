defmodule Cadence.CommandMemberFixtures do
  @moduledoc """
  A command request exists only as a command group's member (#708). These give a test one, in a
  group of its own, without the preflight a real submission goes through, so the queue, release
  and verifier tests can set up requests with exact fields.

  - `insert!/3` stores the request as given (no validation), as the only member of a new group.
  - `member/4` validates it against the active command catalog first, as a group submission does,
    and stores it. A request that needs a second GO is `:approval_pending`, any other `:queued`.
  - `queued!/4` stores it `:queued` and puts it on its target's lane, as a submitted group (or
    its GO) does, and returns `%{request: request, queue_entry: entry}`.
  """

  import Ecto.Query, only: [from: 2]

  alias Cadence.Commanding.{
    CommandApproval,
    CommandRequest,
    CommandRequestRow,
    Dispatcher,
    ProcessNamespace,
    RequestDigest,
    RequestStore,
    RequestValidation
  }

  alias Cadence.Commanding.Groups.{Admission, CommandGroup, CommandGroupRow, GroupStore}
  alias Cadence.Ids
  alias Cadence.Management.Commanding.ApprovedCommand
  alias Cadence.Repo

  @at ~U[2026-11-14 07:20:00Z]

  @doc "A group of `member_count` members in `state`, returning its id."
  def group!(org, mission, state \\ :queued, member_count \\ 1) do
    id = Ids.new("command_group_fixture")

    {:ok, _group} =
      GroupStore.insert_group(
        CommandGroup.new(%{
          command_group_id: id,
          organization_id: org,
          mission_id: mission,
          state: state,
          title: "Fixture group",
          requested_by: %{"actor_kind" => "user", "user_id" => "requester"},
          requested_at: @at,
          resolved_at: @at,
          member_count: member_count
        })
      )

    id
  end

  @doc """
  Stores `request` as given. Options: `:group` (an existing group's id, else a new group),
  `:target_index`, `:position`, `:group_state` (a new group's state, default `:queued`).
  """
  def insert!(org, %CommandRequest{} = request, opts \\ []) do
    request = %{request | organization_id: org}

    group =
      Keyword.get_lazy(opts, :group, fn ->
        group!(org, request.mission_id, Keyword.get(opts, :group_state, :queued))
      end)

    %{
      request
      | command_group_id: group,
        group_slot: %{
          target_index: Keyword.get(opts, :target_index, 0),
          position: Keyword.get(opts, :position, 0)
        }
    }
    |> CommandRequestRow.changeset()
    |> Repo.insert!()
    |> CommandRequestRow.to_domain()
  end

  @doc """
  The insert changeset of `request` as the only member of a new group (the group is inserted
  now), for tests that insert request rows themselves. The request's mission supplies the
  organization.
  """
  def changeset(%CommandRequest{} = request, opts \\ []) do
    org =
      request.organization_id ||
        Repo.one!(
          from(m in "missions",
            where: m.mission_id == ^request.mission_id,
            select: m.organization_id
          )
        )

    group = group!(org, request.mission_id, Keyword.get(opts, :group_state, :queued))

    CommandRequestRow.changeset(%{
      request
      | organization_id: org,
        command_group_id: group,
        group_slot: %{target_index: 0, position: 0}
    })
  end

  @doc "`insert!/3` after validating against the active command catalog: `{:ok, request}`."
  def member(org, mission, %CommandRequest{} = request, opts \\ []) do
    with {:ok, enriched} <- validated(org, mission, request) do
      state = Keyword.get(opts, :state, enriched.lifecycle_state)
      group_state = if state == :approval_pending, do: :approval_pending, else: :queued

      {:ok,
       insert!(
         org,
         %{enriched | lifecycle_state: state},
         Keyword.put_new(opts, :group_state, group_state)
       )}
    end
  end

  def member!(org, mission, request, opts \\ []) do
    {:ok, member} = member(org, mission, request, opts)
    member
  end

  @doc """
  Validates, stores `:queued` and enqueues. Options: `:enqueued_by` (an actor map), `:metadata`
  (queue entry metadata), `:process_namespace` and `:kick` (default true: wake the lane's
  dispatcher, as a group's submission does), plus `insert!/3`'s.
  """
  def queued(org, mission, %CommandRequest{} = request, opts \\ []) do
    with {:ok, member} <- member(org, mission, request, Keyword.put(opts, :state, :queued)) do
      {:ok, queue(member, opts)}
    end
  end

  def queued!(org, mission, request, opts \\ []) do
    {:ok, queued} = queued(org, mission, request, opts)
    queued
  end

  @doc "Enqueues an already stored `:queued` member."
  def queue(%CommandRequest{} = member, opts \\ []) do
    actor = Keyword.get(opts, :enqueued_by, %{})
    extra = Keyword.get(opts, :metadata, %{})

    {:ok, [entry]} =
      Repo.transaction(fn ->
        Admission.enqueue([member], actor, fn request ->
          Map.merge(%{"approved_content_sha256" => content_hash(request)}, stringify(extra))
        end)
      end)

    if Keyword.get(opts, :kick, true) do
      Dispatcher.kick_lane(
        Keyword.get_lazy(opts, :process_namespace, &ProcessNamespace.default/0),
        member.organization_id,
        member.mission_id,
        entry.queue_lane_key
      )
    end

    %{request: Map.put(member, :lifecycle_state, :queued), queue_entry: entry}
  end

  @doc """
  Puts an already stored member on its lane, as `:queued`: `{:ok, %{queue_entry: entry,
  command_request: request}}`. `opts` as for `queued/4`; the lane is not kicked unless `kick: true`.
  """
  def enqueue(org, mission, command_request_id, enqueued_by \\ %{}, opts \\ []) do
    {:ok, row} = RequestStore.fetch_request_row(org, mission, command_request_id)

    member =
      row
      |> CommandRequestRow.lifecycle_changeset(:queued)
      |> Repo.update!()
      |> CommandRequestRow.to_domain()

    %{queue_entry: entry} =
      queue(
        member,
        opts |> Keyword.put(:enqueued_by, enqueued_by) |> Keyword.put_new(:kick, false)
      )

    {:ok, %{queue_entry: entry, command_request: member}}
  end

  @doc "`member/4` for a request that names its own mission: `{:ok, request}` or `{:error, reason}`."
  def persist(org, %CommandRequest{mission_id: mission} = request, opts \\ []),
    do: member(org, mission, request, opts)

  @doc """
  Records the second GO of a stored member: `:approved`, with its decision row. Returns
  `{:ok, %{approval: approval, command_request: request}}`. `opts`: `:reason`.
  """
  def approve(org, mission, command_request_id, decided_by, opts \\ []) do
    {:ok, row} = RequestStore.fetch_request_row(org, mission, command_request_id)

    request =
      row
      |> CommandRequestRow.lifecycle_changeset(:approved)
      |> Repo.update!()
      |> CommandRequestRow.to_domain()

    approval =
      CommandApproval.new(%{
        organization_id: org,
        mission_id: mission,
        command_request_id: command_request_id,
        decision: :approved,
        decided_by: decided_by,
        decided_at: DateTime.utc_now(),
        reason: Keyword.get(opts, :reason),
        subject_digest: RequestDigest.digest(request),
        separated_from: [],
        admin_mode: false
      })

    :ok = GroupStore.insert_approvals([approval])

    {1, _} =
      Repo.update_all(
        from(g in CommandGroupRow, where: g.command_group_id == ^request.command_group_id),
        set: [state: "queued"]
      )

    {:ok, %{approval: approval, command_request: request}}
  end

  @doc "`enqueue/5`, then wake the lane's dispatcher as a group's GO does."
  def enqueue_and_kick(org, mission, command_request_id, enqueued_by \\ %{}, opts \\ []) do
    enqueue(org, mission, command_request_id, enqueued_by, Keyword.put_new(opts, :kick, true))
  end

  defp validated(org, mission, request) do
    request = %{request | organization_id: org, mission_id: mission}

    result =
      Repo.transaction(fn ->
        with {:ok, snapshot} <- RequestValidation.authoring_snapshot(org, mission),
             {:ok, enriched, _state} <- RequestValidation.validate_on_snapshot(request, snapshot) do
          enriched
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    result
  end

  defp content_hash(request) do
    {:ok, approved} =
      ApprovedCommand.from_automatic_policy(%{request | lifecycle_state: :validated})

    approved.content_sha256
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
