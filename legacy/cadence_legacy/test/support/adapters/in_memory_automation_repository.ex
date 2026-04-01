defmodule Cadence.Test.Adapters.InMemoryAutomationRepository do
  @moduledoc """
  In-memory automation repository for testing.

  Implements `Cadence.Ports.Repository.Automations.AutomationRepository` behavior
  by storing automations in an Agent, allowing tests to run without a database.
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Automations.AutomationRepository

  alias Cadence.Domain.Automations.Entities.Automation

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{automations: %{}} end, name: name)
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
  # AutomationRepository Implementation
  # ============================================================================

  @impl true
  def find(id, organization_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.automations, id) do
        nil -> {:error, :not_found}
        %{organization_id: ^organization_id} = automation -> {:ok, automation}
        _ -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def find_unscoped(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.automations, id) end) do
      nil -> {:error, :not_found}
      automation -> {:ok, automation}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    enabled_only = Keyword.get(opts, :enabled_only, false)
    trigger_type = Keyword.get(opts, :trigger_type)

    Agent.get(__MODULE__, fn state ->
      state.automations
      |> Map.values()
      |> Enum.filter(fn a -> a.organization_id == organization_id end)
      |> maybe_filter_by_mission(mission_id)
      |> maybe_filter_enabled(enabled_only)
      |> maybe_filter_trigger_type(trigger_type)
      |> Enum.sort_by(& &1.name)
    end)
  end

  @impl true
  def list_enabled_for_mission(organization_id, mission_id) do
    Agent.get(__MODULE__, fn state ->
      state.automations
      |> Map.values()
      |> Enum.filter(fn a ->
        a.organization_id == organization_id &&
          (a.mission_id == mission_id || is_nil(a.mission_id)) &&
          a.enabled == true
      end)
      |> Enum.sort_by(& &1.name)
    end)
  end

  @impl true
  def save(%Automation{id: nil} = automation) do
    now = DateTime.utc_now()

    automation = %{
      automation
      | id: Ecto.UUID.generate(),
        created_at: now,
        updated_at: now
    }

    Agent.update(__MODULE__, fn state ->
      %{state | automations: Map.put(state.automations, automation.id, automation)}
    end)

    {:ok, automation}
  end

  def save(%Automation{id: id} = automation) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.automations, id) do
        nil ->
          {{:error, :not_found}, state}

        _existing ->
          updated = %{automation | updated_at: DateTime.utc_now()}
          new_state = %{state | automations: Map.put(state.automations, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  @impl true
  def delete(%Automation{id: nil}) do
    {:error, :not_persisted}
  end

  def delete(%Automation{id: id}) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.automations, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {automation, new_automations} ->
          {{:ok, automation}, %{state | automations: new_automations}}
      end
    end)
  end

  @impl true
  def record_trigger(%Automation{id: nil}) do
    {:error, :not_persisted}
  end

  def record_trigger(%Automation{id: id} = automation) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.automations, id) do
        nil ->
          {{:error, :not_found}, state}

        _existing ->
          updated = %{
            automation
            | last_triggered_at: DateTime.utc_now(),
              trigger_count: automation.trigger_count + 1,
              updated_at: DateTime.utc_now()
          }

          new_state = %{state | automations: Map.put(state.automations, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  @impl true
  def enable(%Automation{id: nil}) do
    {:error, :not_persisted}
  end

  def enable(%Automation{id: id}) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.automations, id) do
        nil ->
          {{:error, :not_found}, state}

        automation ->
          updated = %{automation | enabled: true, updated_at: DateTime.utc_now()}
          new_state = %{state | automations: Map.put(state.automations, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  @impl true
  def disable(%Automation{id: nil}) do
    {:error, :not_persisted}
  end

  def disable(%Automation{id: id}) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.automations, id) do
        nil ->
          {{:error, :not_found}, state}

        automation ->
          updated = %{automation | enabled: false, updated_at: DateTime.utc_now()}
          new_state = %{state | automations: Map.put(state.automations, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all automations in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.automations) end)
  end

  @doc """
  Returns the count of automations in the repository.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.automations) end)
  end

  @doc """
  Clears all automations from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{automations: %{}} end)
  end

  @doc """
  Inserts an automation directly (bypassing validation).
  """
  def insert(%Automation{} = automation) do
    automation =
      if automation.id do
        automation
      else
        %{automation | id: Ecto.UUID.generate()}
      end

    now = DateTime.utc_now()
    automation = %{automation | created_at: automation.created_at || now, updated_at: now}

    Agent.update(__MODULE__, fn state ->
      %{state | automations: Map.put(state.automations, automation.id, automation)}
    end)

    automation
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_filter_by_mission(automations, nil), do: automations

  defp maybe_filter_by_mission(automations, mission_id) do
    Enum.filter(automations, fn a ->
      a.mission_id == mission_id || is_nil(a.mission_id)
    end)
  end

  defp maybe_filter_enabled(automations, false), do: automations
  defp maybe_filter_enabled(automations, true), do: Enum.filter(automations, & &1.enabled)

  defp maybe_filter_trigger_type(automations, nil), do: automations

  defp maybe_filter_trigger_type(automations, trigger_type) do
    Enum.filter(automations, fn a -> a.trigger_type == trigger_type end)
  end
end
