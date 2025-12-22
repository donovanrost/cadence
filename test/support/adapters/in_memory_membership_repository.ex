defmodule Cadence.Test.Adapters.InMemoryMembershipRepository do
  @moduledoc """
  In-memory membership repository for testing.

  Implements `Cadence.Ports.Repository.Organizations.MembershipRepository` behavior
  by storing memberships in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryMembershipRepository.start_link()
        Application.put_env(:cadence, :membership_repository, InMemoryMembershipRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :membership_repository)
          InMemoryMembershipRepository.stop()
        end)
        :ok
      end

      test "saves and finds a membership" do
        {:ok, membership} = OrganizationMembership.new(valid_attrs())
        {:ok, saved} = InMemoryMembershipRepository.save(membership)

        {:ok, found} = InMemoryMembershipRepository.find(saved.id)
        assert found.id == saved.id
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Organizations.MembershipRepository

  alias Cadence.Domain.Organizations.Entities.OrganizationMembership

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          memberships: %{}
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
  # MembershipRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.memberships, id) end) do
      nil -> {:error, :not_found}
      membership -> {:ok, membership}
    end
  end

  @impl true
  def find_by_user_and_org(user_id, organization_id) do
    Agent.get(__MODULE__, fn state ->
      result =
        state.memberships
        |> Map.values()
        |> Enum.find(fn m ->
          m.user_id == user_id && m.organization_id == organization_id
        end)

      case result do
        nil -> {:error, :not_found}
        membership -> {:ok, membership}
      end
    end)
  end

  @impl true
  def save(%OrganizationMembership{} = membership) do
    now = DateTime.utc_now()

    membership =
      if membership.id do
        %{membership | updated_at: now}
      else
        %{membership | id: Ecto.UUID.generate(), created_at: now, updated_at: now}
      end

    # Check for uniqueness (user can only have one membership per org)
    case check_uniqueness(membership) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{state | memberships: Map.put(state.memberships, membership.id, membership)}
        end)

        {:ok, membership}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def list_for_organization(organization_id, opts \\ []) do
    role_filter = Keyword.get(opts, :role)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      state.memberships
      |> Map.values()
      |> Enum.filter(&(&1.organization_id == organization_id))
      |> filter_by_role(role_filter)
      |> Enum.sort_by(& &1.created_at)
      |> Enum.drop(offset)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      state.memberships
      |> Map.values()
      |> Enum.filter(&(&1.user_id == user_id))
      |> Enum.sort_by(& &1.created_at)
      |> Enum.drop(offset)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def delete(id) do
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
  def delete_all_for_user(user_id) do
    Agent.update(__MODULE__, fn state ->
      new_memberships =
        state.memberships
        |> Enum.reject(fn {_id, m} -> m.user_id == user_id end)
        |> Map.new()

      %{state | memberships: new_memberships}
    end)

    :ok
  end

  @impl true
  def delete_all_for_organization(organization_id) do
    Agent.update(__MODULE__, fn state ->
      new_memberships =
        state.memberships
        |> Enum.reject(fn {_id, m} -> m.organization_id == organization_id end)
        |> Map.new()

      %{state | memberships: new_memberships}
    end)

    :ok
  end

  @impl true
  def exists?(user_id, organization_id) do
    case find_by_user_and_org(user_id, organization_id) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @impl true
  def count_for_organization(organization_id) do
    Agent.get(__MODULE__, fn state ->
      state.memberships
      |> Map.values()
      |> Enum.count(&(&1.organization_id == organization_id))
    end)
  end

  @impl true
  def count_owners(organization_id) do
    Agent.get(__MODULE__, fn state ->
      state.memberships
      |> Map.values()
      |> Enum.count(&(&1.organization_id == organization_id && &1.role == :owner))
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all memberships in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.memberships) end)
  end

  @doc """
  Returns the count of memberships.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.memberships) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ ->
      %{
        memberships: %{}
      }
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_uniqueness(%OrganizationMembership{
         id: id,
         user_id: user_id,
         organization_id: org_id
       }) do
    Agent.get(__MODULE__, fn state ->
      existing =
        state.memberships
        |> Map.values()
        |> Enum.find(fn m ->
          m.user_id == user_id && m.organization_id == org_id && m.id != id
        end)

      case existing do
        nil -> :ok
        _ -> {:error, :already_exists}
      end
    end)
  end

  defp filter_by_role(memberships, nil), do: memberships

  defp filter_by_role(memberships, role) do
    Enum.filter(memberships, &(&1.role == role))
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
