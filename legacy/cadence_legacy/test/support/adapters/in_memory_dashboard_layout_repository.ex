defmodule Cadence.Test.Adapters.InMemoryDashboardLayoutRepository do
  @moduledoc """
  In-memory dashboard layout repository for testing.

  Implements `Cadence.Ports.Repository.DashboardLayouts.DashboardLayoutRepository` behavior
  by storing layouts in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryDashboardLayoutRepository.start_link()
        Application.put_env(:cadence, :dashboard_layout_repository, InMemoryDashboardLayoutRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :dashboard_layout_repository)
          InMemoryDashboardLayoutRepository.stop()
        end)
        :ok
      end

      test "creates a layout" do
        {:ok, layout} = DashboardLayout.new(%{name: "Test", user_id: "user-1"})
        {:ok, saved} = InMemoryDashboardLayoutRepository.save(layout)
        assert saved.id != nil
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.DashboardLayouts.DashboardLayoutRepository

  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{layouts: %{}} end, name: name)
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
  # DashboardLayoutRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.layouts, id) end) do
      nil -> {:error, :not_found}
      layout -> {:ok, layout}
    end
  end

  @impl true
  def find_for_user(id, user_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.layouts, id) do
        nil -> {:error, :not_found}
        %{user_id: ^user_id} = layout -> {:ok, layout}
        _ -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def find_user_layout(user_id, mission_id) do
    Agent.get(__MODULE__, fn state ->
      layout =
        state.layouts
        |> Map.values()
        |> Enum.filter(fn l -> l.user_id == user_id && l.mission_id == mission_id end)
        |> Enum.sort_by(fn l -> {!l.is_default, l.updated_at} end, :desc)
        |> List.first()

      case layout do
        nil -> {:error, :not_found}
        l -> {:ok, l}
      end
    end)
  end

  @impl true
  def find_user_default(user_id) do
    Agent.get(__MODULE__, fn state ->
      layout =
        state.layouts
        |> Map.values()
        |> Enum.find(fn l ->
          l.user_id == user_id && l.mission_id == nil && l.is_default == true
        end)

      case layout do
        nil -> {:error, :not_found}
        l -> {:ok, l}
      end
    end)
  end

  @impl true
  def list_for_user(user_id, mission_id) do
    Agent.get(__MODULE__, fn state ->
      state.layouts
      |> Map.values()
      |> Enum.filter(fn l -> l.user_id == user_id && l.mission_id == mission_id end)
      |> Enum.sort_by(fn l -> {!l.is_default, l.name} end)
    end)
  end

  @impl true
  def save(%DashboardLayout{id: nil} = layout) do
    now = DateTime.utc_now()

    layout = %{
      layout
      | id: Ecto.UUID.generate(),
        created_at: now,
        updated_at: now
    }

    Agent.update(__MODULE__, fn state ->
      %{state | layouts: Map.put(state.layouts, layout.id, layout)}
    end)

    {:ok, layout}
  end

  def save(%DashboardLayout{id: id} = layout) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state.layouts, id) do
        nil ->
          {{:error, :not_found}, state}

        _existing ->
          updated = %{layout | updated_at: DateTime.utc_now()}
          new_state = %{state | layouts: Map.put(state.layouts, id, updated)}
          {{:ok, updated}, new_state}
      end
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.layouts, id) do
        {nil, _} -> {{:error, :not_found}, state}
        {layout, new_layouts} -> {{:ok, layout}, %{state | layouts: new_layouts}}
      end
    end)
  end

  @impl true
  def unset_other_defaults(user_id, mission_id, exclude_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      {count, new_layouts} = unset_defaults(state.layouts, user_id, mission_id, exclude_id)

      {{:ok, count}, %{state | layouts: new_layouts}}
    end)
  end

  defp unset_defaults(layouts, user_id, mission_id, exclude_id) do
    Enum.reduce(layouts, {0, layouts}, fn {id, layout}, {count, acc} ->
      if unset_default?(layout, id, user_id, mission_id, exclude_id) do
        updated = %{layout | is_default: false}
        {count + 1, Map.put(acc, id, updated)}
      else
        {count, acc}
      end
    end)
  end

  defp unset_default?(layout, id, user_id, mission_id, exclude_id) do
    layout.user_id == user_id &&
      layout.mission_id == mission_id &&
      id != exclude_id &&
      layout.is_default
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all layouts in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.layouts) end)
  end

  @doc """
  Returns the count of layouts in the repository.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.layouts) end)
  end

  @doc """
  Clears all layouts from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{layouts: %{}} end)
  end

  @doc """
  Inserts a layout directly (bypassing new validation).
  """
  def insert(%DashboardLayout{} = layout) do
    layout =
      if layout.id do
        layout
      else
        %{layout | id: Ecto.UUID.generate()}
      end

    now = DateTime.utc_now()
    layout = %{layout | created_at: layout.created_at || now, updated_at: now}

    Agent.update(__MODULE__, fn state ->
      %{state | layouts: Map.put(state.layouts, layout.id, layout)}
    end)

    layout
  end
end
