defmodule Cadence.Test.Adapters.InMemoryMissionsRepository do
  @moduledoc """
  In-memory missions repository for testing.

  Implements `Cadence.Ports.Repository.Missions.MissionsRepository` behavior
  by storing missions and memberships in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryMissionsRepository.start_link()
        Application.put_env(:cadence, :missions_repository, InMemoryMissionsRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :missions_repository)
          InMemoryMissionsRepository.stop()
        end)
        :ok
      end

      test "finds a mission" do
        mission = %Mission{id: Ecto.UUID.generate(), name: "Test Mission"}
        {:ok, _} = InMemoryMissionsRepository.save(mission)
        {:ok, found} = InMemoryMissionsRepository.find(mission.id)
        assert found.name == "Test Mission"
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Missions.MissionsRepository

  alias Cadence.Missions.{Mission, MissionMembership}

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{missions: %{}, memberships: %{}} end, name: name)
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
  # Mission Operations
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.missions, id) end) do
      nil -> {:error, :not_found}
      mission -> {:ok, mission}
    end
  end

  @impl true
  def find_by_org(id, organization_id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.missions, id) end) do
      nil ->
        {:error, :not_found}

      mission ->
        if mission.organization_id == organization_id do
          {:ok, mission}
        else
          {:error, :not_found}
        end
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit)

    Agent.get(__MODULE__, fn state ->
      state.missions
      |> Map.values()
      |> Enum.filter(&(&1.organization_id == organization_id))
      |> filter_by_status(status_filter)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def save(%Mission{} = mission) do
    mission =
      if mission.id do
        mission
      else
        %{mission | id: Ecto.UUID.generate()}
      end

    # Set timestamps if not present
    now = DateTime.utc_now()

    mission =
      mission
      |> maybe_set_timestamp(:inserted_at, now)
      |> maybe_set_timestamp(:updated_at, now)

    Agent.update(__MODULE__, fn state ->
      %{state | missions: Map.put(state.missions, mission.id, mission)}
    end)

    {:ok, mission}
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.missions, id) do
        {nil, _} -> {{:error, :not_found}, state}
        {mission, new_missions} -> {{:ok, mission}, %{state | missions: new_missions}}
      end
    end)
  end

  # ============================================================================
  # Mission Membership Operations
  # ============================================================================

  @impl true
  def find_membership(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.memberships, id) end) do
      nil -> {:error, :not_found}
      membership -> {:ok, membership}
    end
  end

  @impl true
  def list_memberships(mission_id, _opts \\ []) do
    Agent.get(__MODULE__, fn state ->
      state.memberships
      |> Map.values()
      |> Enum.filter(&(&1.mission_id == mission_id))
    end)
  end

  @impl true
  def save_membership(%MissionMembership{} = membership) do
    membership =
      if membership.id do
        membership
      else
        %{membership | id: Ecto.UUID.generate()}
      end

    # Set timestamps if not present
    now = DateTime.utc_now()

    membership =
      membership
      |> maybe_set_timestamp(:inserted_at, now)
      |> maybe_set_timestamp(:updated_at, now)

    Agent.update(__MODULE__, fn state ->
      %{state | memberships: Map.put(state.memberships, membership.id, membership)}
    end)

    {:ok, membership}
  end

  @impl true
  def delete_membership(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.memberships, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {membership, new_memberships} ->
          {{:ok, membership}, %{state | memberships: new_memberships}}
      end
    end)
  end

  @impl true
  def find_user_role(user_id, mission_id) do
    result =
      Agent.get(__MODULE__, fn state ->
        state.memberships
        |> Map.values()
        |> Enum.find(&(&1.user_id == user_id && &1.mission_id == mission_id))
      end)

    case result do
      nil -> {:error, :not_found}
      membership -> {:ok, membership.role}
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all missions in the repository.
  """
  def all_missions do
    Agent.get(__MODULE__, fn state -> Map.values(state.missions) end)
  end

  @doc """
  Returns all memberships in the repository.
  """
  def all_memberships do
    Agent.get(__MODULE__, fn state -> Map.values(state.memberships) end)
  end

  @doc """
  Returns the count of missions in the repository.
  """
  def mission_count do
    Agent.get(__MODULE__, fn state -> map_size(state.missions) end)
  end

  @doc """
  Returns the count of memberships in the repository.
  """
  def membership_count do
    Agent.get(__MODULE__, fn state -> map_size(state.memberships) end)
  end

  @doc """
  Clears all entries from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{missions: %{}, memberships: %{}} end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp filter_by_status(missions, nil), do: missions

  defp filter_by_status(missions, status) do
    Enum.filter(missions, &(&1.status == status))
  end

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, limit), do: Enum.take(entries, limit)

  defp maybe_set_timestamp(struct, field, value) do
    if Map.get(struct, field) do
      struct
    else
      Map.put(struct, field, value)
    end
  end
end
