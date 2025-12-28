defmodule Cadence.Test.Adapters.InMemoryQueueRepository do
  @moduledoc """
  In-memory queue repository for testing.

  Implements `Cadence.Ports.Repository.Commanding.QueueRepository` behavior
  by storing queue entries in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryQueueRepository.start_link()
        Application.put_env(:cadence, :queue_repository, InMemoryQueueRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :queue_repository)
          InMemoryQueueRepository.stop()
        end)
        :ok
      end

      test "enqueues a command" do
        {:ok, cmd} = QueuedCommand.new(valid_attrs())
        {:ok, saved} = InMemoryQueueRepository.enqueue(cmd)
        assert saved.sequence_number != nil
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Commanding.QueueRepository

  alias Cadence.Domain.Commanding.Entities.QueuedCommand

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{entries: %{}, sequence: 0} end, name: name)
  end

  def stop(pid \\ __MODULE__) do
    try do
      Agent.stop(pid)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  # ============================================================================
  # Behaviour Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.entries, id) end) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @impl true
  def save(entry) do
    entry =
      if entry.id do
        entry
      else
        %{entry | id: Ecto.UUID.generate()}
      end

    Agent.update(__MODULE__, fn state ->
      %{state | entries: Map.put(state.entries, entry.id, entry)}
    end)

    {:ok, entry}
  end

  @impl true
  def list(mission_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    target_id = Keyword.get(opts, :target_id)
    priority = Keyword.get(opts, :priority)
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn state ->
      state.entries
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> filter_by_status(status_filter)
      |> filter_by_target(target_id)
      |> filter_by_priority(priority)
      |> sort_by_priority_and_sequence()
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def list_for_target(target_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn state ->
      state.entries
      |> Map.values()
      |> Enum.filter(&(&1.target_id == target_id))
      |> filter_by_status(status_filter)
      |> sort_by_priority_and_sequence()
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def claim_next(target_id) do
    now = DateTime.utc_now()

    Agent.get_and_update(__MODULE__, fn state ->
      # Find the next pending entry
      next =
        state.entries
        |> Map.values()
        |> Enum.filter(fn entry ->
          entry.target_id == target_id &&
            entry.status == :pending &&
            (entry.scheduled_at == nil || DateTime.compare(entry.scheduled_at, now) != :gt) &&
            (entry.expires_at == nil || DateTime.compare(entry.expires_at, now) != :lt)
        end)
        |> sort_by_priority_and_sequence()
        |> List.first()

      case next do
        nil ->
          {{:error, :queue_empty}, state}

        entry ->
          claimed = %{entry | status: :executing}
          new_entries = Map.put(state.entries, entry.id, claimed)
          {{:ok, claimed}, %{state | entries: new_entries}}
      end
    end)
  end

  @impl true
  def count_by_status(target_id) do
    Agent.get(__MODULE__, fn state ->
      initial = %{pending: 0, executing: 0, completed: 0, failed: 0, cancelled: 0, expired: 0}

      state.entries
      |> Map.values()
      |> Enum.filter(&(&1.target_id == target_id))
      |> Enum.reduce(initial, fn entry, acc ->
        Map.update(acc, entry.status, 1, &(&1 + 1))
      end)
    end)
  end

  @impl true
  def count_by_status_for_mission(mission_id) do
    Agent.get(__MODULE__, fn state ->
      initial = %{pending: 0, executing: 0, completed: 0, failed: 0, cancelled: 0, expired: 0}

      state.entries
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> Enum.reduce(initial, fn entry, acc ->
        Map.update(acc, entry.status, 1, &(&1 + 1))
      end)
    end)
  end

  @impl true
  def enqueue(entry) do
    Agent.get_and_update(__MODULE__, fn state ->
      next_seq = state.sequence + 1

      entry =
        entry
        |> Map.put(:id, entry.id || Ecto.UUID.generate())
        |> Map.put(:sequence_number, next_seq)

      new_entries = Map.put(state.entries, entry.id, entry)
      {{:ok, entry}, %{state | entries: new_entries, sequence: next_seq}}
    end)
  end

  @impl true
  def list_pending(target_id, opts \\ []) do
    include_scheduled = Keyword.get(opts, :include_scheduled, false)
    limit = Keyword.get(opts, :limit)
    now = DateTime.utc_now()

    Agent.get(__MODULE__, fn state ->
      state.entries
      |> Map.values()
      |> Enum.filter(fn entry ->
        entry.target_id == target_id &&
          entry.status == :pending &&
          (include_scheduled || entry.scheduled_at == nil ||
             DateTime.compare(entry.scheduled_at, now) != :gt)
      end)
      |> sort_by_priority_and_sequence()
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def cancel_all_pending(target_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      {count, new_entries} =
        state.entries
        |> Enum.reduce({0, state.entries}, fn {id, entry}, acc ->
          cancel_pending_entry({id, entry}, target_id, acc)
        end)

      {{:ok, count}, %{state | entries: new_entries}}
    end)
  end

  @impl true
  def expire_old_entries(cutoff_time) do
    Agent.get_and_update(__MODULE__, fn state ->
      {count, new_entries} =
        state.entries
        |> Enum.reduce({0, state.entries}, fn {id, entry}, acc ->
          expire_entry_if_needed({id, entry}, cutoff_time, acc)
        end)

      {{:ok, count}, %{state | entries: new_entries}}
    end)
  end

  defp cancel_pending_entry({id, entry}, target_id, {count, entries}) do
    if pending_for_target?(entry, target_id) do
      cancelled = %{entry | status: :cancelled}
      {count + 1, Map.put(entries, id, cancelled)}
    else
      {count, entries}
    end
  end

  defp expire_entry_if_needed({id, entry}, cutoff_time, {count, entries}) do
    if expired_pending_entry?(entry, cutoff_time) do
      expired = %{entry | status: :expired}
      {count + 1, Map.put(entries, id, expired)}
    else
      {count, entries}
    end
  end

  defp pending_for_target?(entry, target_id) do
    entry.target_id == target_id and entry.status == :pending
  end

  defp expired_pending_entry?(entry, cutoff_time) do
    entry.status == :pending &&
      entry.expires_at != nil &&
      DateTime.compare(entry.expires_at, cutoff_time) == :lt
  end

  @impl true
  def reorder(reorder_list) do
    Agent.update(__MODULE__, fn state ->
      new_entries = apply_reorder(state.entries, reorder_list)
      %{state | entries: new_entries}
    end)

    :ok
  end

  defp apply_reorder(entries, reorder_list) do
    Enum.reduce(reorder_list, entries, fn {id, new_seq}, acc ->
      case Map.get(acc, id) do
        nil -> acc
        entry -> Map.put(acc, id, %{entry | sequence_number: new_seq})
      end
    end)
  end

  @impl true
  def list_expired do
    now = DateTime.utc_now()

    Agent.get(__MODULE__, fn state ->
      state.entries
      |> Map.values()
      |> Enum.filter(fn entry ->
        entry.status == :pending &&
          entry.expires_at != nil &&
          DateTime.compare(entry.expires_at, now) == :lt
      end)
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.entries, id) do
        {nil, _} -> {{:error, :not_found}, state}
        {entry, new_entries} -> {{:ok, entry}, %{state | entries: new_entries}}
      end
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all entries in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.entries) end)
  end

  @doc """
  Returns the count of entries in the repository.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.entries) end)
  end

  @doc """
  Clears all entries from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{entries: %{}, sequence: 0} end)
  end

  @doc """
  Inserts an entry directly with a specific sequence number.
  """
  def insert(%QueuedCommand{} = entry) do
    Agent.get_and_update(__MODULE__, fn state ->
      entry = if entry.id, do: entry, else: %{entry | id: Ecto.UUID.generate()}
      seq = entry.sequence_number || state.sequence + 1
      entry = %{entry | sequence_number: seq}
      new_entries = Map.put(state.entries, entry.id, entry)
      new_seq = max(state.sequence, seq)
      {entry, %{state | entries: new_entries, sequence: new_seq}}
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_status(entries, nil), do: entries

  defp filter_by_status(entries, statuses) when is_list(statuses) do
    Enum.filter(entries, &(&1.status in statuses))
  end

  defp filter_by_status(entries, status) when is_atom(status) do
    Enum.filter(entries, &(&1.status == status))
  end

  defp filter_by_target(entries, nil), do: entries

  defp filter_by_target(entries, target_id) do
    Enum.filter(entries, &(&1.target_id == target_id))
  end

  defp filter_by_priority(entries, nil), do: entries

  defp filter_by_priority(entries, priorities) when is_list(priorities) do
    Enum.filter(entries, &(&1.priority in priorities))
  end

  defp filter_by_priority(entries, priority) when is_integer(priority) do
    Enum.filter(entries, &(&1.priority == priority))
  end

  defp sort_by_priority_and_sequence(entries) do
    Enum.sort_by(entries, fn e -> {e.priority, e.sequence_number} end)
  end

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, limit), do: Enum.take(entries, limit)
end
