defmodule Cadence.Control.Commanding.GroupAbort do
  @moduledoc """
  Abort a command group and cancel a single request (M20, DECISIONS #31).

  Abort is a safing action: any mission operator may do it (not two-person),
  with a required reason that is audited. It cancels every member that hasn't
  started to radiate and reports the ones that had (`already_started`), which
  keep running. A single request can be canceled under the same rule.
  """

  alias Cadence.Commanding.{Cancellation, Dispatcher, ProcessNamespace}
  alias Cadence.Commanding.Groups.{CommandGroup, GroupStore}
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @abortable [:approval_pending, :queued]

  @spec abort(Cadence.Auth.Scope.t(), binary(), binary(), binary()) ::
          {:ok, CommandGroup.t()} | {:error, term()}
  def abort(scope, mission_id, group_id, reason) do
    with {:ok, fresh, _mission} <- RequestAuthoring.authorize(scope, mission_id),
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
    with {:ok, fresh, _mission} <- RequestAuthoring.authorize(scope, mission_id),
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
    with {:ok, request} <- Cadence.Commanding.fetch_command_request(org, mission, request_id),
         %{"id" => group_id} <- request.metadata["group"] do
      GroupStore.append_events([
        %{
          command_group_id: group_id,
          mission_id: mission,
          kind: :member_canceled,
          actor: actor,
          payload: %{"command_request_id" => request_id, "reason" => reason}
        }
      ])
    else
      _not_a_member -> :ok
    end
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
    Enum.each(lanes, &Dispatcher.kick_lane(ProcessNamespace.default(), org, mission, &1))
    {:ok, value}
  end

  defp after_commit({:error, reason}, _org, _mission), do: {:error, reason}
end
