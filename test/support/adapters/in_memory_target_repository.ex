defmodule Cadence.Test.Adapters.InMemoryTargetRepository do
  @moduledoc """
  In-memory target repository for testing.

  Implements `Cadence.Ports.Repository.Targeting.TargetRepository` behavior by storing
  targets in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, pid} = InMemoryTargetRepository.start_link()
        on_exit(fn -> InMemoryTargetRepository.stop(pid) end)
        {:ok, repo: pid}
      end

      test "finds target by id", %{repo: pid} do
        target = build_target()
        {:ok, saved} = InMemoryTargetRepository.save(target)

        {:ok, found} = InMemoryTargetRepository.find(saved.id, saved.mission_id)
        assert found.id == saved.id
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Targeting.TargetRepository

  alias Cadence.Domain.Targeting.Entities.Target

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  @doc """
  Starts the in-memory target repository agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Stops the in-memory target repository agent.
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
  # Core CRUD Operations
  # ============================================================================

  @impl true
  def find(id, mission_id) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_found}
      target when target.mission_id == mission_id -> {:ok, target}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def find_unscoped(id) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_found}
      target -> {:ok, target}
    end
  end

  @impl true
  def find_by_identifier(mission_id, identifier) do
    Agent.get(__MODULE__, fn targets ->
      result =
        targets
        |> Map.values()
        |> Enum.find(fn target ->
          target.mission_id == mission_id && target.identifier == identifier
        end)

      case result do
        nil -> {:error, :not_found}
        target -> {:ok, target}
      end
    end)
  end

  @impl true
  def save(%Target{id: nil} = target) do
    target = %{target | id: Ecto.UUID.generate()}
    now = DateTime.utc_now()
    target = %{target | inserted_at: now, updated_at: now}

    Agent.update(__MODULE__, fn targets ->
      Map.put(targets, target.id, target)
    end)

    {:ok, target}
  end

  def save(%Target{id: id} = target) do
    Agent.get_and_update(__MODULE__, fn targets ->
      case Map.get(targets, id) do
        nil ->
          {{:error, :not_found}, targets}

        _existing ->
          updated = %{target | updated_at: DateTime.utc_now()}
          {{:ok, updated}, Map.put(targets, id, updated)}
      end
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn targets ->
      case Map.pop(targets, id) do
        {nil, targets} -> {{:error, :not_found}, targets}
        {target, targets} -> {{:ok, target}, targets}
      end
    end)
  end

  # ============================================================================
  # Query Operations
  # ============================================================================

  @impl true
  def list(mission_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    type_filter = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn targets ->
      targets
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
      |> filter_by_status(status_filter)
      |> filter_by_type(type_filter)
      |> Enum.sort_by(& &1.name)
      |> Enum.drop(offset)
      |> Enum.take(limit)
    end)
  end

  @impl true
  def list_by_definition_set(definition_set_id) do
    Agent.get(__MODULE__, fn targets ->
      targets
      |> Map.values()
      |> Enum.filter(&(&1.definition_set_id == definition_set_id))
      |> Enum.sort_by(& &1.name)
    end)
  end

  # ============================================================================
  # Circuit Breaker Operations
  # ============================================================================

  @impl true
  def update_circuit_breaker(id, changes) do
    Agent.get_and_update(__MODULE__, fn targets ->
      case Map.get(targets, id) do
        nil ->
          {{:error, :not_found}, targets}

        target ->
          updated =
            target
            |> maybe_update(:circuit_breaker_status, Map.get(changes, :status))
            |> maybe_update(:circuit_breaker_failures, Map.get(changes, :failures))
            |> maybe_update(:circuit_breaker_opened_at, Map.get(changes, :opened_at))
            |> Map.put(:updated_at, DateTime.utc_now())

          {{:ok, updated}, Map.put(targets, id, updated)}
      end
    end)
  end

  # ============================================================================
  # Definition Set Operations
  # ============================================================================

  @impl true
  def get_definition_set_id(mission_id, identifier) do
    case find_by_identifier(mission_id, identifier) do
      {:ok, target} -> {:ok, target.definition_set_id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @impl true
  def get_definition_set_id_by_target_id(id) do
    case find_unscoped(id) do
      {:ok, target} -> {:ok, target.definition_set_id}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @impl true
  def find_with_definition_set(id) do
    # In-memory doesn't have associations, just return the target
    find_unscoped(id)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all targets in the repository.
  """
  def all(pid \\ __MODULE__) do
    Agent.get(pid, &Map.values/1)
  end

  @doc """
  Returns the count of targets in the repository.
  """
  def count(pid \\ __MODULE__) do
    Agent.get(pid, &map_size/1)
  end

  @doc """
  Clears all targets from the repository.
  """
  def clear(pid \\ __MODULE__) do
    Agent.update(pid, fn _ -> %{} end)
  end

  @doc """
  Inserts a target directly (bypassing save logic).

  Useful for setting up test state.
  """
  def insert(target, pid \\ __MODULE__) do
    target =
      if target.id do
        target
      else
        %{target | id: Ecto.UUID.generate()}
      end

    now = DateTime.utc_now()

    target =
      target
      |> Map.put(:inserted_at, target.inserted_at || now)
      |> Map.put(:updated_at, target.updated_at || now)

    Agent.update(pid, fn targets -> Map.put(targets, target.id, target) end)
    target
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_status(targets, nil), do: targets

  defp filter_by_status(targets, statuses) when is_list(statuses) do
    Enum.filter(targets, &(&1.status in statuses))
  end

  defp filter_by_status(targets, status) when is_atom(status) do
    Enum.filter(targets, &(&1.status == status))
  end

  defp filter_by_type(targets, nil), do: targets

  defp filter_by_type(targets, types) when is_list(types) do
    Enum.filter(targets, &(&1.type in types))
  end

  defp filter_by_type(targets, type) when is_atom(type) do
    Enum.filter(targets, &(&1.type == type))
  end

  defp maybe_update(target, _key, nil), do: target
  defp maybe_update(target, key, value), do: Map.put(target, key, value)
end
