defmodule Cadence.Test.Adapters.InMemoryScheduleRepository do
  @moduledoc """
  In-memory implementation of ScheduleRepository for testing.

  Uses an Agent to store schedules, allowing for fast, isolated tests
  without database dependencies.

  ## Usage

  Configure in test environment:

      config :cadence, :schedule_repository, Cadence.Test.Adapters.InMemoryScheduleRepository

  Start the repository in test setup:

      setup do
        {:ok, _pid} = Cadence.Test.Adapters.InMemoryScheduleRepository.start_link()
        :ok
      end
  """

  @behaviour Cadence.Ports.Repository.Schedules.ScheduleRepository

  use Agent

  alias Cadence.Domain.Schedules.Entities.Schedule

  @doc """
  Starts the in-memory repository.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Resets the repository state. Useful for test cleanup.
  """
  def reset(name \\ __MODULE__) do
    Agent.update(name, fn _ -> %{} end)
  end

  @doc """
  Returns all schedules in the repository. Useful for test assertions.
  """
  def all(name \\ __MODULE__) do
    Agent.get(name, fn state -> Map.values(state) end)
  end

  # ===========================================================================
  # ScheduleRepository Implementation
  # ===========================================================================

  @impl true
  def find(id, organization_id, name \\ __MODULE__) do
    Agent.get(name, fn state ->
      case Map.get(state, id) do
        nil -> {:error, :not_found}
        %Schedule{organization_id: ^organization_id} = schedule -> {:ok, schedule}
        _ -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def find_unscoped(id, name \\ __MODULE__) do
    Agent.get(name, fn state ->
      case Map.get(state, id) do
        nil -> {:error, :not_found}
        schedule -> {:ok, schedule}
      end
    end)
  end

  @impl true
  def list(organization_id, opts \\ [], name \\ __MODULE__) do
    mission_id = Keyword.get(opts, :mission_id)
    procedure_id = Keyword.get(opts, :procedure_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(name, fn state ->
      state
      |> Map.values()
      |> Enum.filter(&(&1.organization_id == organization_id))
      |> apply_filters(
        mission_id: mission_id,
        procedure_id: procedure_id,
        enabled_only: enabled_only
      )
      |> Enum.sort_by(& &1.name)
      |> Enum.drop(offset)
      |> maybe_take(limit)
    end)
  end

  @impl true
  def list_enabled_cron(name \\ __MODULE__) do
    Agent.get(name, fn state ->
      state
      |> Map.values()
      |> Enum.filter(&(&1.enabled && &1.schedule_type == :cron && &1.cron_expression))
      |> Enum.map(&schedule_to_cron_job/1)
    end)
  end

  @impl true
  def list_due_once(name \\ __MODULE__) do
    now = DateTime.utc_now()

    Agent.get(name, fn state ->
      state
      |> Map.values()
      |> Enum.filter(fn schedule ->
        schedule.enabled &&
          schedule.schedule_type == :once &&
          schedule.scheduled_at &&
          DateTime.compare(schedule.scheduled_at, now) != :gt &&
          is_nil(schedule.last_run_at)
      end)
    end)
  end

  @impl true
  def save(%Schedule{id: nil} = schedule, name \\ __MODULE__) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    schedule_with_id = %{
      schedule
      | id: id,
        inserted_at: now,
        updated_at: now
    }

    Agent.update(name, fn state ->
      Map.put(state, id, schedule_with_id)
    end)

    {:ok, schedule_with_id}
  end

  def save(%Schedule{id: id} = schedule, name) when not is_nil(id) do
    now = DateTime.utc_now()
    updated_schedule = %{schedule | updated_at: now}

    name
    |> Agent.get_and_update(&update_existing_schedule(&1, id, updated_schedule))
    |> normalize_save_result()
  end

  defp update_existing_schedule(state, id, updated_schedule) do
    if Map.has_key?(state, id) do
      {{:ok, updated_schedule}, Map.put(state, id, updated_schedule)}
    else
      {{:error, :not_found}, state}
    end
  end

  defp normalize_save_result({:ok, schedule}), do: {:ok, schedule}
  defp normalize_save_result({:error, :not_found}), do: {:error, :not_found}

  @impl true
  def delete(%Schedule{id: id}, name \\ __MODULE__) do
    Agent.get_and_update(name, fn state ->
      case Map.pop(state, id) do
        {nil, state} -> {{:error, :not_found}, state}
        {deleted, state} -> {{:ok, deleted}, state}
      end
    end)
  end

  @impl true
  def record_run(%Schedule{id: id}, next_run_at \\ nil, name \\ __MODULE__) do
    now = DateTime.utc_now()

    Agent.get_and_update(name, fn state ->
      case Map.get(state, id) do
        nil ->
          {{:error, :not_found}, state}

        schedule ->
          updated = %{
            schedule
            | last_run_at: now,
              next_run_at: next_run_at,
              run_count: (schedule.run_count || 0) + 1,
              updated_at: now
          }

          {{:ok, updated}, Map.put(state, id, updated)}
      end
    end)
  end

  @impl true
  def enable(%Schedule{id: id}, name \\ __MODULE__) do
    now = DateTime.utc_now()

    Agent.get_and_update(name, fn state ->
      case Map.get(state, id) do
        nil ->
          {{:error, :not_found}, state}

        schedule ->
          updated = %{schedule | enabled: true, updated_at: now}
          {{:ok, updated}, Map.put(state, id, updated)}
      end
    end)
  end

  @impl true
  def disable(%Schedule{id: id}, name \\ __MODULE__) do
    now = DateTime.utc_now()

    Agent.get_and_update(name, fn state ->
      case Map.get(state, id) do
        nil ->
          {{:error, :not_found}, state}

        schedule ->
          updated = %{schedule | enabled: false, updated_at: now}
          {{:ok, updated}, Map.put(state, id, updated)}
      end
    end)
  end

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  @doc """
  Inserts a schedule directly for testing. Bypasses validation.
  """
  def insert!(%Schedule{} = schedule, name \\ __MODULE__) do
    id = schedule.id || Ecto.UUID.generate()
    now = DateTime.utc_now()

    schedule_with_id = %{
      schedule
      | id: id,
        inserted_at: schedule.inserted_at || now,
        updated_at: schedule.updated_at || now
    }

    Agent.update(name, fn state ->
      Map.put(state, id, schedule_with_id)
    end)

    schedule_with_id
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(schedules, filters) do
    Enum.reduce(filters, schedules, fn
      {:mission_id, nil}, acc ->
        acc

      {:mission_id, mission_id}, acc ->
        Enum.filter(acc, &(&1.mission_id == mission_id || is_nil(&1.mission_id)))

      {:procedure_id, nil}, acc ->
        acc

      {:procedure_id, procedure_id}, acc ->
        Enum.filter(acc, &(&1.procedure_id == procedure_id))

      {:enabled_only, false}, acc ->
        acc

      {:enabled_only, true}, acc ->
        Enum.filter(acc, & &1.enabled)
    end)
  end

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, limit), do: Enum.take(list, limit)

  defp schedule_to_cron_job(%Schedule{} = schedule) do
    {schedule.cron_expression,
     {Cadence.Schedules.Workers.ExecuteScheduleWorker,
      [schedule_id: schedule.id, name: "schedule:#{schedule.id}"]}}
  end
end
