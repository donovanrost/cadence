defmodule Cadence.Control.Activations.Resume do
  @moduledoc """
  Resume an approved activation whose apply failed or stalled midway (L10; director, 2026-11-13):
  an approver's manual `Retry apply`. There's no automatic sweep: re-applying a configuration
  unattended needs the user's say.

  Resumable: the request is approved and its execution `:failed`, or `:in_progress` for more
  than #{div(10 * 60_000, 60_000)} minutes with no executor holding its lock (stalled), or never
  started that long after approval. The resume runs `Control.Activations.execute/2` again under
  the same execution lock, so it can't interleave with a live execution or another resume; every
  step of an execution is idempotent. Each resume is audited as an `activation_resumed`
  operational event naming who resumed it.

  Errors: `{:nothing_to_resume, state}` (`"succeeded"`, `"in_progress"`, or the request's state
  when it isn't approved), `:activation_execution_in_progress` (an executor holds the lock),
  `:activation_request_not_found`, `:forbidden`; otherwise `execute/2`'s own result.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.ExecutionLock
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  @stalled_after_ms 10 * 60_000

  @doc "How long an execution runs without an executor before it counts as stalled."
  def stalled_after_ms, do: @stalled_after_ms

  # todo(authz): resume uses the approval permission (:approve_activation), like approve.
  def run(%Scope{} = scope, mission_id, request_id, opts) when is_binary(request_id) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    with :ok <- authorize(scope, mission_id),
         {:ok, request} <- request(scope, mission_id, request_id),
         {:ok, approved} <- approved(request),
         :ok <- resumable(request, now) do
      ControlActivations.execute(
        approved,
        Keyword.merge(opts,
          executor_actor_document: executor(scope),
          on_locked: fn -> audit(scope, request, now) end
        )
      )
    end
  end

  def run(_scope, _mission_id, _request_id, _opts), do: {:error, :activation_request_not_found}

  defp authorize(scope, mission_id) do
    case ManagementActivations.authorize_review(scope, mission_id) do
      :ok -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  # Management.Activations.fetch/2 checks only the organization.
  defp request(scope, mission_id, request_id) do
    case ManagementActivations.fetch(scope, request_id) do
      {:ok, %{mission_id: ^mission_id} = request} -> {:ok, request}
      _missing -> {:error, :activation_request_not_found}
    end
  end

  defp approved(%{state: :approved} = request),
    do: ManagementActivations.fetch_approved(request.activation_request_id)

  defp approved(request), do: {:error, {:nothing_to_resume, to_string(request.state)}}

  defp resumable(request, now) do
    case ControlActivations.fetch_execution(request.activation_request_id) do
      {:ok, %{status: :failed}} ->
        :ok

      {:ok, %{status: :succeeded}} ->
        {:error, {:nothing_to_resume, "succeeded"}}

      {:ok, %{status: :in_progress, started_at: started_at}} ->
        stalled(request, started_at, now)

      {:error, :activation_execution_not_found} ->
        stalled(request, request.decided_at || request.requested_at, now)
    end
  end

  defp stalled(request, since, now) do
    if stalled?(since, now) and ExecutionLock.free?(request.activation_request_id),
      do: :ok,
      else: {:error, {:nothing_to_resume, "in_progress"}}
  end

  @doc "Whether an execution running since `since` has stalled by `now`."
  def stalled?(%DateTime{} = since, %DateTime{} = now),
    do: DateTime.diff(now, since, :millisecond) > @stalled_after_ms

  def stalled?(_since, _now), do: false

  defp executor(%Scope{user: user}) when is_map(user),
    do: %{
      "kind" => "user",
      "id" => user.user_id,
      "display_name" => Map.get(user, :display_name)
    }

  defp executor(_scope),
    do: %{"kind" => "service", "id" => "cadence:activation_executor"}

  # One event per resume that ran (it holds the lock), so each attempt has its own record.
  defp audit(scope, request, now) do
    actor = executor(scope)
    attempt = "#{request.activation_request_id}:resume:#{DateTime.to_unix(now, :microsecond)}"

    {:ok, _event} =
      %{
        event_id: "operational_event:activation_request:#{attempt}",
        organization_id: request.organization_id,
        mission_id: request.mission_id,
        occurred_at: now,
        recorded_at: now,
        effective_at: now,
        category: :runtime,
        kind: :activation_resumed,
        severity: :info,
        actor: %{
          kind: if(actor["kind"] == "user", do: :user, else: :service),
          id: actor["id"],
          display_name: actor["display_name"]
        },
        subject: %{kind: :binding_set, id: request.binding_set_id},
        causality: %{
          correlation_id: request.activation_request_id,
          source_record_kind: :activation_request,
          source_record_id: attempt
        },
        payload: %{
          activation_request_id: request.activation_request_id,
          binding_set_id: request.binding_set_id,
          binding_set_version: request.binding_set_version
        }
      }
      |> Event.new()
      |> OperationalEvents.persist_event()

    :ok
  end
end
