defmodule Cadence.Test.Adapters.InMemoryOrganizationRepository do
  @moduledoc """
  In-memory organization repository for testing.

  Implements `Cadence.Ports.Repository.Organizations.OrganizationRepository` behavior
  by storing organizations in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryOrganizationRepository.start_link()
        Application.put_env(:cadence, :organization_repository, InMemoryOrganizationRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :organization_repository)
          InMemoryOrganizationRepository.stop()
        end)
        :ok
      end

      test "saves and finds an organization" do
        {:ok, org} = Organization.new(valid_attrs())
        {:ok, saved} = InMemoryOrganizationRepository.save(org)

        {:ok, found} = InMemoryOrganizationRepository.find(saved.id)
        assert found.id == saved.id
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Organizations.OrganizationRepository

  alias Cadence.Domain.Organizations.Entities.Organization

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          organizations: %{},
          # For quota counting, we track related entity counts
          mission_counts: %{},
          user_counts: %{},
          target_counts: %{}
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
  # OrganizationRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.organizations, id) end) do
      nil -> {:error, :not_found}
      organization -> {:ok, organization}
    end
  end

  @impl true
  def find_by_slug(slug) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.organizations
        |> Map.values()
        |> Enum.find(fn org -> org.slug == slug end)

      case result do
        nil -> {:error, :not_found}
        organization -> {:ok, organization}
      end
    end)
  end

  @impl true
  def save(%Organization{} = organization) do
    now = DateTime.utc_now()

    organization =
      if organization.id do
        %{organization | updated_at: now}
      else
        %{organization | id: Ecto.UUID.generate(), created_at: now, updated_at: now}
      end

    # Check for slug uniqueness
    case check_slug_uniqueness(organization) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{state | organizations: Map.put(state.organizations, organization.id, organization)}
        end)

        {:ok, organization}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def list(opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    tier_filter = Keyword.get(opts, :tier)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      state.organizations
      |> Map.values()
      |> filter_by_status(status_filter)
      |> filter_by_tier(tier_filter)
      |> filter_by_search(search)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.drop(offset)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.organizations, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {organization, new_organizations} ->
          # Also clean up related counts
          new_state = %{
            state
            | organizations: new_organizations,
              mission_counts: Map.delete(state.mission_counts, id),
              user_counts: Map.delete(state.user_counts, id)
          }

          {{:ok, organization}, new_state}
      end
    end)
  end

  # ============================================================================
  # Counting Operations
  # ============================================================================

  @impl true
  def count_missions(org_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.mission_counts, org_id, 0)
    end)
  end

  @impl true
  def count_mission_targets(mission_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.target_counts, mission_id, 0)
    end)
  end

  @impl true
  def count_users(org_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.user_counts, org_id, 0)
    end)
  end

  @impl true
  def count_memberships(org_id) do
    # Delegate to membership repository if needed, or track here
    Agent.get(__MODULE__, fn state ->
      Map.get(state.user_counts, org_id, 0)
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Sets the mission count for an organization (for testing quota checks).
  """
  def set_mission_count(org_id, count) do
    Agent.update(__MODULE__, fn state ->
      %{state | mission_counts: Map.put(state.mission_counts, org_id, count)}
    end)
  end

  @doc """
  Sets the user count for an organization (for testing quota checks).
  """
  def set_user_count(org_id, count) do
    Agent.update(__MODULE__, fn state ->
      %{state | user_counts: Map.put(state.user_counts, org_id, count)}
    end)
  end

  @doc """
  Sets the target count for a mission (for testing quota checks).
  """
  def set_target_count(mission_id, count) do
    Agent.update(__MODULE__, fn state ->
      %{state | target_counts: Map.put(state.target_counts, mission_id, count)}
    end)
  end

  @doc """
  Returns all organizations in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.organizations) end)
  end

  @doc """
  Returns the count of organizations.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.organizations) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ ->
      %{
        organizations: %{},
        mission_counts: %{},
        user_counts: %{},
        target_counts: %{}
      }
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_slug_uniqueness(%Organization{id: id, slug: slug}) do
    Agent.get(__MODULE__, fn state ->
      existing =
        state.organizations
        |> Map.values()
        |> Enum.find(fn org -> org.slug == slug && org.id != id end)

      case existing do
        nil -> :ok
        _ -> {:error, {:validation, %{slug: ["has already been taken"]}}}
      end
    end)
  end

  defp filter_by_status(organizations, nil), do: organizations

  defp filter_by_status(organizations, status) do
    Enum.filter(organizations, &(&1.status == status))
  end

  defp filter_by_tier(organizations, nil), do: organizations

  defp filter_by_tier(organizations, tier) do
    Enum.filter(organizations, &(&1.subscription_tier == tier))
  end

  defp filter_by_search(organizations, nil), do: organizations

  defp filter_by_search(organizations, search) do
    search_lower = String.downcase(search)

    Enum.filter(organizations, fn org ->
      String.contains?(String.downcase(org.name || ""), search_lower) ||
        String.contains?(String.downcase(org.slug || ""), search_lower)
    end)
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
