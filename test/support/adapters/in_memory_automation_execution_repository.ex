defmodule Cadence.Test.Adapters.InMemoryAutomationExecutionRepository do
  @moduledoc """
  In-memory automation execution repository for testing.

  Implements `Cadence.Ports.Repository.Automations.AutomationExecutionRepository` behavior
  by storing executions in an Agent, allowing tests to run without a database.
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Automations.AutomationExecutionRepository

  alias Cadence.Domain.Automations.Entities.AutomationExecution

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{executions: %{}, idempotency_keys: MapSet.new()} end, name: name)
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
  # AutomationExecutionRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.executions, id) end) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  @impl true
  def find_with_automation(id) do
    # In-memory doesn't support preloading, just return the execution
    find(id)
  end

  @impl true
  def list(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)
    automation_id = Keyword.get(opts, :automation_id)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    Agent.get(__MODULE__, fn state ->
      state.executions
      |> Map.values()
      |> maybe_filter(:organization_id, organization_id)
      |> maybe_filter(:mission_id, mission_id)
      |> maybe_filter(:automation_id, automation_id)
      |> maybe_filter(:status, status)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.take(limit)
    end)
  end

  @impl true
  def count_recent(automation_id, since) do
    Agent.get(__MODULE__, fn state ->
      state.executions
      |> Map.values()
      |> Enum.count(fn e ->
        e.automation_id == automation_id &&
          e.created_at != nil &&
          DateTime.compare(e.created_at, since) != :lt
      end)
    end)
  end

  @impl true
  def save(%AutomationExecution{id: nil} = execution) do
    # Check for duplicate idempotency key
    if execution.idempotency_key do
      Agent.get_and_update(__MODULE__, fn state ->
        if MapSet.member?(state.idempotency_keys, execution.idempotency_key) do
          {{:error, :duplicate}, state}
        else
          now = DateTime.utc_now()

          execution = %{
            execution
            | id: Ecto.UUID.generate(),
              created_at: now,
              updated_at: now
          }

          new_state = %{
            state
            | executions: Map.put(state.executions, execution.id, execution),
              idempotency_keys: MapSet.put(state.idempotency_keys, execution.idempotency_key)
          }

          {{:ok, execution}, new_state}
        end
      end)
    else
      now = DateTime.utc_now()

      execution = %{
        execution
        | id: Ecto.UUID.generate(),
          created_at: now,
          updated_at: now
      }

      Agent.update(__MODULE__, fn state ->
        %{state | executions: Map.put(state.executions, execution.id, execution)}
      end)

      {:ok, execution}
    end
  end

  def save(%AutomationExecution{id: id} = execution) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.executions, id) do
        nil ->
          {{:error, :not_found}, state}

        _existing ->
          updated = %{execution | updated_at: DateTime.utc_now()}
          new_state = %{state | executions: Map.put(state.executions, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all executions in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.executions) end)
  end

  @doc """
  Returns the count of executions in the repository.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.executions) end)
  end

  @doc """
  Clears all executions from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{executions: %{}, idempotency_keys: MapSet.new()} end)
  end

  @doc """
  Inserts an execution directly (bypassing validation).
  """
  def insert(%AutomationExecution{} = execution) do
    execution =
      if execution.id do
        execution
      else
        %{execution | id: Ecto.UUID.generate()}
      end

    now = DateTime.utc_now()
    execution = %{execution | created_at: execution.created_at || now, updated_at: now}

    Agent.update(__MODULE__, fn state ->
      new_keys =
        if execution.idempotency_key do
          MapSet.put(state.idempotency_keys, execution.idempotency_key)
        else
          state.idempotency_keys
        end

      %{
        state
        | executions: Map.put(state.executions, execution.id, execution),
          idempotency_keys: new_keys
      }
    end)

    execution
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_filter(executions, _field, nil), do: executions

  defp maybe_filter(executions, field, value) do
    Enum.filter(executions, fn e -> Map.get(e, field) == value end)
  end
end
