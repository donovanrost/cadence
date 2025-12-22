defmodule Cadence.Test.Adapters.InMemoryTargetInterfaceRepository do
  @moduledoc """
  In-memory target-interface repository for testing.

  Implements `Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository` behavior
  by storing routings in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryTargetInterfaceRepository.start_link()
        Application.put_env(:cadence, :target_interface_repository, InMemoryTargetInterfaceRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :target_interface_repository)
          InMemoryTargetInterfaceRepository.stop()
        end)
        :ok
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Interfaces.TargetInterfaceRepository

  alias Cadence.Domain.Interfaces.Entities.TargetInterface

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn -> %{routings: %{}} end,
      name: name
    )
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
  # TargetInterfaceRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.routings, id) end) do
      nil -> {:error, :not_found}
      routing -> {:ok, routing}
    end
  end

  @impl true
  def find_by_target_and_interface(target_id, interface_id) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.routings
        |> Map.values()
        |> Enum.find(fn r ->
          r.target_id == target_id && r.interface_id == interface_id
        end)

      case result do
        nil -> {:error, :not_found}
        routing -> {:ok, routing}
      end
    end)
  end

  @impl true
  def save(%TargetInterface{} = routing) do
    now = DateTime.utc_now()

    routing =
      if routing.id do
        %{routing | updated_at: now}
      else
        %{routing | id: Ecto.UUID.generate(), created_at: now, updated_at: now}
      end

    # Check for uniqueness
    case check_uniqueness(routing) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{state | routings: Map.put(state.routings, routing.id, routing)}
        end)

        {:ok, routing}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.routings, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {routing, new_routings} ->
          {{:ok, routing}, %{state | routings: new_routings}}
      end
    end)
  end

  @impl true
  def delete_by_target_and_interface(target_id, interface_id) do
    Agent.update(__MODULE__, fn state ->
      new_routings =
        state.routings
        |> Enum.reject(fn {_id, r} ->
          r.target_id == target_id && r.interface_id == interface_id
        end)
        |> Map.new()

      %{state | routings: new_routings}
    end)

    :ok
  end

  # ============================================================================
  # Listing Operations
  # ============================================================================

  @impl true
  def list_for_interface(interface_id) do
    Agent.get(__MODULE__, fn state ->
      state.routings
      |> Map.values()
      |> Enum.filter(&(&1.interface_id == interface_id))
    end)
  end

  @impl true
  def list_for_target(target_id) do
    Agent.get(__MODULE__, fn state ->
      state.routings
      |> Map.values()
      |> Enum.filter(&(&1.target_id == target_id))
    end)
  end

  @impl true
  def get_target_ids_for_interface(interface_id) do
    Agent.get(__MODULE__, fn state ->
      state.routings
      |> Map.values()
      |> Enum.filter(&(&1.interface_id == interface_id))
      |> Enum.map(& &1.target_id)
    end)
  end

  @impl true
  def get_interface_ids_for_target(target_id) do
    Agent.get(__MODULE__, fn state ->
      state.routings
      |> Map.values()
      |> Enum.filter(&(&1.target_id == target_id))
      |> Enum.map(& &1.interface_id)
    end)
  end

  # ============================================================================
  # Batch Operations
  # ============================================================================

  @impl true
  def replace_for_interface(interface_id, routings) do
    delete_all_for_interface(interface_id)

    results =
      Enum.map(routings, fn routing ->
        routing = %{routing | interface_id: interface_id}
        save(routing)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, r} -> r end)}
    else
      hd(errors)
    end
  end

  @impl true
  def delete_all_for_interface(interface_id) do
    Agent.update(__MODULE__, fn state ->
      new_routings =
        state.routings
        |> Enum.reject(fn {_id, r} -> r.interface_id == interface_id end)
        |> Map.new()

      %{state | routings: new_routings}
    end)

    :ok
  end

  @impl true
  def delete_all_for_target(target_id) do
    Agent.update(__MODULE__, fn state ->
      new_routings =
        state.routings
        |> Enum.reject(fn {_id, r} -> r.target_id == target_id end)
        |> Map.new()

      %{state | routings: new_routings}
    end)

    :ok
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all routings in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.routings) end)
  end

  @doc """
  Returns the count of routings.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.routings) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{routings: %{}} end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_uniqueness(%TargetInterface{
         id: id,
         target_id: target_id,
         interface_id: interface_id
       }) do
    Agent.get(__MODULE__, fn state ->
      existing =
        state.routings
        |> Map.values()
        |> Enum.find(fn r ->
          r.target_id == target_id && r.interface_id == interface_id && r.id != id
        end)

      case existing do
        nil -> :ok
        _ -> {:error, :already_exists}
      end
    end)
  end
end
