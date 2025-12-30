defmodule Cadence.Application.Commanding.QueuePersistence do
  @moduledoc """
  Control-plane persistence bridge for data-plane queue events.

  TargetQueue emits events to this module so the control plane can
  update the database and broadcast queue state changes.
  """

  use GenServer

  import Ecto.Query

  alias Cadence.Adapters.Messaging.PhoenixEventPublisher
  alias Cadence.Application.Commanding.{CommandQueries, ManageQueue}
  alias Cadence.Commands.QueueEntry
  alias Cadence.Ports.Repository.Commanding.QueueRepository
  alias Cadence.Repo

  @topic "queue:persistence"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def notify(event) do
    if enabled?() do
      Phoenix.PubSub.broadcast(Cadence.PubSub, @topic, {:queue_persist, event})
    else
      :ok
    end
  end

  defp enabled? do
    Application.get_env(:cadence, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, @topic)
    {:ok, state}
  end

  @impl true
  def handle_info({:queue_persist, event}, state) do
    apply_event(event)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp repo do
    QueueRepository.impl()
  end

  defp publish_event(target_id, event) do
    PhoenixEventPublisher.publish("target:#{target_id}:queue", event)
  end

  defp apply_event({:enqueue, entry}) do
    case repo().save(entry) do
      {:ok, saved} -> publish_event(saved.target_id, {:command_enqueued, saved})
      _ -> :ok
    end
  end

  defp apply_event({:mark_executing, entry_id, attempts, claimed_at}) do
    with {:ok, entry} <- CommandQueries.find(entry_id) do
      updated = %{entry | status: :executing, attempts: attempts, last_attempt_at: claimed_at}

      case repo().save(updated) do
        {:ok, saved} -> publish_event(saved.target_id, {:command_claimed, saved})
        _ -> :ok
      end
    end
  end

  defp apply_event({:attach_command_log, entry_id, command_log_id}) do
    with {:ok, entry} <- CommandQueries.find(entry_id) do
      updated = %{entry | command_log_id: command_log_id}
      _ = repo().save(updated)
      :ok
    end
  end

  defp apply_event({:complete, entry_id, command_log_id}) do
    _ = ManageQueue.complete(entry_id, command_log_id)
    :ok
  end

  defp apply_event({:failed, entry_id, error_msg}) do
    _ = ManageQueue.fail(entry_id, error_msg)
    :ok
  end

  defp apply_event({:return_to_pending, entry_id, reason}) do
    with {:ok, entry} <- CommandQueries.find(entry_id) do
      updated = %{entry | status: :pending, last_error: reason}

      case repo().save(updated) do
        {:ok, saved} -> publish_event(saved.target_id, {:command_retried, saved})
        _ -> :ok
      end
    end
  end

  defp apply_event({:cancel, entry_id}) do
    _ = ManageQueue.cancel(entry_id)
    :ok
  end

  defp apply_event({:clear_pending, target_id}) do
    _ = ManageQueue.cancel_all_pending(target_id)
    :ok
  end

  defp apply_event({:priority_changed, entry_id, new_priority}) do
    _ = ManageQueue.set_priority(entry_id, new_priority)
    :ok
  end

  defp apply_event({:expire_entries, []}), do: :ok

  defp apply_event({:expire_entries, entry_ids}) do
    now = DateTime.utc_now()

    from(e in QueueEntry, where: e.id in ^entry_ids)
    |> Repo.update_all(set: [status: :expired, updated_at: now])

    :ok
  end

  defp apply_event(_event), do: :ok
end
