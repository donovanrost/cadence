defmodule CadenceWeb.Console.SchedulingRunner do
  @moduledoc """
  Runs slow scheduling work (fleet drafts, plan execution) off the request
  path under `CadenceWeb.Console.TaskSupervisor` (DECISIONS #27 v1), and
  broadcasts `{:scheduling_progress, payload}` on the mission's topic so
  `mission:<id>` channels can push it.

  The run or plan row is the durable state. If this node dies mid-task, reads
  report the run as `interrupted` (see `Cadence.Control.Scheduling.draft_state/3`)
  and the client offers Continue.
  """

  require Logger

  @pubsub Cadence.PubSub
  @supervisor CadenceWeb.Console.TaskSupervisor

  @spec topic(binary()) :: binary()
  def topic(mission_id), do: "console:scheduling:" <> mission_id

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(mission_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(mission_id))

  @doc "Starts `work` (a 0-arity fun returning `{:ok, _}` or `{:error, reason}`) and reports progress."
  @spec start(binary(), :draft | :execute, binary(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, pid()} | {:error, term()}
  def start(mission_id, kind, id, work) when is_function(work, 0) do
    Task.Supervisor.start_child(@supervisor, fn ->
      broadcast(mission_id, kind, id, :running, nil)

      case safe(work) do
        {:ok, _result} ->
          broadcast(mission_id, kind, id, :finished, nil)

        {:error, reason} ->
          Logger.warning("console scheduling #{kind} #{id} failed: #{inspect(reason)}")
          broadcast(mission_id, kind, id, :failed, reason_code(reason))
      end
    end)
  end

  defp safe(work) do
    work.()
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp broadcast(mission_id, kind, id, state, reason) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      topic(mission_id),
      {:scheduling_progress,
       %{kind: kind, id: id, state: state, reason: reason, at: DateTime.utc_now()}}
    )
  end

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(reason) when is_binary(reason), do: reason
  defp reason_code({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(_reason), do: "failed"
end
