defmodule Cadence.Test.Adapters.InMemoryInterfaceRepository do
  @moduledoc """
  In-memory interface repository for testing.

  Implements `Cadence.Ports.Repository.Interfaces.InterfaceRepository` behavior
  by storing interfaces in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryInterfaceRepository.start_link()
        Application.put_env(:cadence, :interface_repository, InMemoryInterfaceRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :interface_repository)
          InMemoryInterfaceRepository.stop()
        end)
        :ok
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Interfaces.InterfaceRepository

  alias Cadence.Domain.Interfaces.Entities.Interface

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          interfaces: %{}
        }
      end,
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
  # InterfaceRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.interfaces, id) end) do
      nil -> {:error, :not_found}
      interface -> {:ok, interface}
    end
  end

  @impl true
  def find_by_name(mission_id, name) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.interfaces
        |> Map.values()
        |> Enum.find(fn i -> i.mission_id == mission_id && i.name == name end)

      case result do
        nil -> {:error, :not_found}
        interface -> {:ok, interface}
      end
    end)
  end

  @impl true
  def save(%Interface{} = interface) do
    now = DateTime.utc_now()

    interface =
      if interface.id do
        %{interface | updated_at: now}
      else
        %{interface | id: Ecto.UUID.generate(), created_at: now, updated_at: now}
      end

    # Check for name uniqueness within mission
    case check_name_uniqueness(interface) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{
            state
            | interfaces: Map.put(state.interfaces, interface.id, interface)
          }
        end)

        {:ok, interface}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.interfaces, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {interface, new_interfaces} ->
          new_state = %{state | interfaces: new_interfaces}

          {{:ok, interface}, new_state}
      end
    end)
  end

  # ============================================================================
  # Listing Operations
  # ============================================================================

  @impl true
  def list_for_mission(mission_id, opts \\ []) do
    connection_type = Keyword.get(opts, :connection_type)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      interfaces =
        state.interfaces
        |> Map.values()
        |> Enum.filter(&(&1.mission_id == mission_id))
        |> filter_by_connection_type(connection_type)
        |> Enum.sort_by(& &1.name)
        |> Enum.drop(offset)
        |> maybe_limit(limit)

      interfaces
    end)
  end

  @impl true
  def list(opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    connection_type = Keyword.get(opts, :connection_type)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      interfaces =
        state.interfaces
        |> Map.values()
        |> filter_by_mission(mission_id)
        |> filter_by_connection_type(connection_type)
        |> Enum.sort_by(& &1.name)
        |> Enum.drop(offset)
        |> maybe_limit(limit)

      interfaces
    end)
  end

  # ============================================================================
  # Counting Operations
  # ============================================================================

  @impl true
  def count_for_mission(mission_id) do
    Agent.get(__MODULE__, fn state ->
      state.interfaces
      |> Map.values()
      |> Enum.count(&(&1.mission_id == mission_id))
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all interfaces in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.interfaces) end)
  end

  @doc """
  Returns the count of interfaces.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.interfaces) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ ->
      %{
        interfaces: %{}
      }
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_name_uniqueness(%Interface{id: id, mission_id: mission_id, name: name}) do
    Agent.get(__MODULE__, fn state ->
      existing =
        state.interfaces
        |> Map.values()
        |> Enum.find(fn i ->
          i.mission_id == mission_id && i.name == name && i.id != id
        end)

      case existing do
        nil -> :ok
        _ -> {:error, {:validation, %{name: ["has already been taken"]}}}
      end
    end)
  end

  defp filter_by_mission(interfaces, nil), do: interfaces

  defp filter_by_mission(interfaces, mission_id) do
    Enum.filter(interfaces, &(&1.mission_id == mission_id))
  end

  defp filter_by_connection_type(interfaces, nil), do: interfaces

  defp filter_by_connection_type(interfaces, type) do
    Enum.filter(interfaces, &(&1.connection_type == type))
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
