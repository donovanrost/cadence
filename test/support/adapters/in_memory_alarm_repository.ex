defmodule Cadence.Test.Adapters.InMemoryAlarmRepository do
  @moduledoc """
  In-memory alarm repository for testing.

  Implements `Cadence.Ports.Repository.Alerting.AlarmRepository` behavior by storing
  alarms in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, pid} = InMemoryAlarmRepository.start_link()
        on_exit(fn -> InMemoryAlarmRepository.stop(pid) end)
        {:ok, repo: pid}
      end

      test "finds alarm by id", %{repo: pid} do
        alarm = build_alarm()
        {:ok, saved} = InMemoryAlarmRepository.save(alarm)

        {:ok, found} = InMemoryAlarmRepository.find(saved.id)
        assert found.id == saved.id
      end

  ## Note on Domain Entities

  This adapter is designed to work with `Cadence.Domain.Alerting.Entities.Alarm`
  domain entities (Phase 1 of the refactoring). Until those are created, it will
  work with maps that have the expected structure.
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Alerting.AlarmRepository

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  @doc """
  Starts the in-memory alarm repository agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Stops the in-memory alarm repository agent.
  """
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
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_found}
      alarm -> {:ok, alarm}
    end
  end

  @impl true
  def find_active_by_source(mission_id, target_id, source_type, source_id) do
    Agent.get(__MODULE__, fn alarms ->
      result =
        alarms
        |> Map.values()
        |> Enum.find(fn alarm ->
          alarm.mission_id == mission_id &&
            alarm.source_type == source_type &&
            alarm.source_id == source_id &&
            (target_id == nil || alarm.target_id == target_id) &&
            alarm.status in [:active, :acknowledged, :shelved]
        end)

      case result do
        nil -> {:error, :not_found}
        alarm -> {:ok, alarm}
      end
    end)
  end

  @impl true
  def save(alarm) do
    # Generate ID if not present
    alarm =
      if alarm.id do
        alarm
      else
        Map.put(alarm, :id, Ecto.UUID.generate())
      end

    Agent.update(__MODULE__, fn alarms ->
      Map.put(alarms, alarm.id, alarm)
    end)

    {:ok, alarm}
  end

  @impl true
  def list(mission_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    severity_filter = Keyword.get(opts, :severity)
    target_id = Keyword.get(opts, :target_id)
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn alarms ->
      alarms
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> filter_by_status(status_filter)
      |> filter_by_severity(severity_filter)
      |> filter_by_target(target_id)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def list_active(mission_id, opts \\ []) do
    list(mission_id, Keyword.put(opts, :status, [:active, :acknowledged, :shelved]))
  end

  @impl true
  def count_by_status(mission_id) do
    Agent.get(__MODULE__, fn alarms ->
      alarms
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> Enum.reduce(%{active: 0, acknowledged: 0, shelved: 0, cleared: 0}, fn alarm, acc ->
        Map.update(acc, alarm.status, 1, &(&1 + 1))
      end)
    end)
  end

  @impl true
  def list_expired_shelved do
    now = DateTime.utc_now()

    Agent.get(__MODULE__, fn alarms ->
      alarms
      |> Map.values()
      |> Enum.filter(fn alarm ->
        alarm.status == :shelved &&
          alarm.shelved_until &&
          DateTime.compare(now, alarm.shelved_until) == :gt
      end)
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn alarms ->
      case Map.pop(alarms, id) do
        {nil, alarms} -> {{:error, :not_found}, alarms}
        {alarm, alarms} -> {{:ok, alarm}, alarms}
      end
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all alarms in the repository.
  """
  def all(pid \\ __MODULE__) do
    Agent.get(pid, &Map.values/1)
  end

  @doc """
  Returns the count of alarms in the repository.
  """
  def count(pid \\ __MODULE__) do
    Agent.get(pid, &map_size/1)
  end

  @doc """
  Clears all alarms from the repository.
  """
  def clear(pid \\ __MODULE__) do
    Agent.update(pid, fn _ -> %{} end)
  end

  @doc """
  Inserts an alarm directly (bypassing save logic).

  Useful for setting up test state.
  """
  def insert(alarm, pid \\ __MODULE__) do
    alarm =
      if alarm.id do
        alarm
      else
        Map.put(alarm, :id, Ecto.UUID.generate())
      end

    Agent.update(pid, fn alarms -> Map.put(alarms, alarm.id, alarm) end)
    alarm
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_status(alarms, nil), do: alarms

  defp filter_by_status(alarms, statuses) when is_list(statuses) do
    Enum.filter(alarms, &(&1.status in statuses))
  end

  defp filter_by_status(alarms, status) when is_atom(status) do
    Enum.filter(alarms, &(&1.status == status))
  end

  defp filter_by_severity(alarms, nil), do: alarms

  defp filter_by_severity(alarms, severities) when is_list(severities) do
    Enum.filter(alarms, &(&1.severity in severities))
  end

  defp filter_by_severity(alarms, severity) when is_atom(severity) do
    Enum.filter(alarms, &(&1.severity == severity))
  end

  defp filter_by_target(alarms, nil), do: alarms

  defp filter_by_target(alarms, target_id) do
    Enum.filter(alarms, &(&1.target_id == target_id))
  end

  defp maybe_limit(alarms, nil), do: alarms
  defp maybe_limit(alarms, limit), do: Enum.take(alarms, limit)
end
