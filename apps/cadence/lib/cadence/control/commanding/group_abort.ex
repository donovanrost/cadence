defmodule Cadence.Control.Commanding.GroupAbort do
  @moduledoc """
  Abort a command group and cancel a single request (M20, DECISIONS #31).

  Abort is a safing action: any mission operator may do it (not two-person),
  with a required reason that is audited. It cancels every member that hasn't
  started to radiate and reports the ones that had (`already_started`), which
  keep running. A single request can be canceled under the same rule.
  """

  alias Cadence.Accounts.User
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Commanding.{Cancellation, Dispatcher, ProcessNamespace}
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore, Timeline}
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @abortable [:approval_pending, :queued]

  @spec abort(Cadence.Auth.Scope.t(), binary(), binary(), binary()) ::
          {:ok, CommandGroup.t()} | {:error, term()}
  def abort(scope, mission_id, group_id, reason) do
    with {:ok, fresh, _mission} <- authorize(scope, mission_id),
         :ok <- reason_given(reason) do
      org = fresh.organization_id
      actor = actor(fresh)

      fn -> abort_locked(org, mission_id, group_id, String.trim(reason), actor) end
      |> Repo.transaction()
      |> after_commit(org, mission_id)
    end
  end

  @spec cancel_request(Cadence.Auth.Scope.t(), binary(), binary(), binary()) ::
          {:ok, map()} | {:error, term()}
  def cancel_request(scope, mission_id, request_id, reason) do
    with {:ok, fresh, _mission} <- authorize(scope, mission_id),
         :ok <- reason_given(reason) do
      org = fresh.organization_id
      actor = actor(fresh)

      fn -> cancel_locked(org, mission_id, request_id, String.trim(reason), actor) end
      |> Repo.transaction()
      |> after_commit(org, mission_id)
    end
  end

  defp abort_locked(org, mission, group_id, reason, actor) do
    with {:ok, group} <- GroupStore.fetch(org, mission, group_id, lock: true),
         :ok <- abortable(group) do
      ids = org |> GroupStore.members(mission, group_id) |> Enum.map(& &1.command_request_id)
      outcome = Cancellation.cancel(org, mission, ids, "aborted: " <> reason, actor)
      now = DateTime.utc_now()

      result = %{
        "canceled" => length(outcome.canceled),
        "already_started" => outcome.already_started
      }

      {:ok, updated} =
        GroupStore.update_group(%{
          group
          | state: :aborted,
            aborted_by: actor,
            aborted_at: now,
            abort_reason: reason,
            abort_result: result
        })

      :ok =
        GroupStore.append_events([
          %{
            command_group_id: group_id,
            mission_id: mission,
            kind: :aborted,
            actor: actor,
            at: now,
            payload: Map.put(result, "reason", reason)
          }
        ])

      %{value: updated, lanes: outcome.lanes}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp cancel_locked(org, mission, request_id, reason, actor) do
    case Cancellation.cancel(org, mission, [request_id], reason, actor) do
      %{canceled: [^request_id], lanes: lanes} ->
        :ok = record_member_cancel(org, mission, request_id, reason, actor)
        %{value: %{command_request_id: request_id, state: :canceled}, lanes: lanes}

      %{already_started: [^request_id]} ->
        Repo.rollback(:command_request_already_started)

      _none ->
        Repo.rollback(:command_request_not_found)
    end
  end

  defp record_member_cancel(org, mission, request_id, reason, actor) do
    case Cadence.Commanding.fetch_command_request(org, mission, request_id) do
      {:ok, request} ->
        GroupStore.append_events([
          %{
            command_group_id: request.command_group_id,
            mission_id: mission,
            kind: :member_canceled,
            actor: actor,
            payload: %{"command_request_id" => request_id, "reason" => reason}
          }
        ])

      {:error, _unreadable} ->
        :ok
    end
  end

  @doc """
  `command.abort` for the console (DECISIONS #42), from the check `abort/4`
  and `cancel_request/4` enforce: an active human who can operate the mission.
  The check needs a real mission, so for an organization-level answer it's
  evaluated against the organization's missions (held if any passes; an
  organization without missions has nothing to abort).
  """
  @spec capabilities(Scope.t()) :: [binary()]
  def capabilities(
        %Scope{actor_kind: :user, user: %User{lifecycle_state: :active}, organization_id: org} =
          scope
      )
      when is_binary(org) do
    missions =
      case scope.mission_id do
        nil -> org |> Cadence.Missions.list_missions() |> Enum.map(& &1.mission_id)
        mission_id -> [mission_id]
      end

    if Enum.any?(missions, &(operate(scope, &1) == :ok)), do: ["command.abort"], else: []
  end

  def capabilities(%Scope{}), do: []

  # Abort is safing: any mission operator, not only commanding admins (DECISIONS #31, #42).
  defp authorize(
         %Scope{actor_kind: :user, user: %{user_id: _}, organization_id: org} = scope,
         mission_id
       )
       when is_binary(org) and is_binary(mission_id) do
    with :ok <- operate(scope, mission_id),
         {:ok, _mission} <- Cadence.Missions.fetch_mission(org, mission_id) do
      {:ok, scope, mission_id}
    else
      _denied -> {:error, :unavailable}
    end
  end

  defp authorize(_scope, _mission_id), do: {:error, :unavailable}

  # todo(authz): Cedar should decide who may abort or cancel (any mission operator today, #42),
  # e.g. per target set or only for groups in their area.
  defp operate(scope, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp abortable(%CommandGroup{state: state}) when state in @abortable, do: :ok
  defp abortable(%CommandGroup{}), do: {:error, :command_group_not_abortable}

  defp reason_given(reason) when is_binary(reason) do
    if String.trim(reason) == "", do: {:error, :reason_required}, else: :ok
  end

  defp reason_given(_reason), do: {:error, :reason_required}

  defp actor(fresh), do: %{"actor_kind" => "user", "user_id" => fresh.user.user_id}

  defp after_commit({:ok, %{value: value, lanes: lanes}}, org, mission) do
    ScopedReadUpdates.publish(:commanding_changed, org, mission)
    settle_timeline(value, org, mission)
    Dispatcher.kick_lanes(ProcessNamespace.default(), org, mission, lanes)
    {:ok, value}
  end

  defp after_commit({:error, reason}, _org, _mission), do: {:error, reason}

  # Canceling the last open members can finish the group (DECISIONS #51).
  defp settle_timeline(%CommandGroup{command_group_id: id}, org, mission),
    do: Timeline.settle_group(org, mission, id)

  defp settle_timeline(%{command_request_id: id}, org, mission),
    do: Timeline.settle_requests(org, mission, [id])
end
