defmodule Cadence.Test.Adapters.InMemoryUserRepository do
  @moduledoc """
  In-memory user repository for testing.

  Implements `Cadence.Ports.Repository.Accounts.UserRepository` behavior
  by storing users in an Agent, allowing tests to run without a database.

  ## Usage

      setup do
        {:ok, _} = InMemoryUserRepository.start_link()
        Application.put_env(:cadence, :user_repository, InMemoryUserRepository)
        on_exit(fn ->
          Application.delete_env(:cadence, :user_repository)
          InMemoryUserRepository.stop()
        end)
        :ok
      end

      test "saves and finds a user" do
        {:ok, user} = User.new(valid_attrs())
        {:ok, saved} = InMemoryUserRepository.save(user)

        {:ok, found} = InMemoryUserRepository.find(saved.id)
        assert found.id == saved.id
      end
  """

  use Agent

  @behaviour Cadence.Ports.Repository.Accounts.UserRepository

  alias Cadence.Domain.Accounts.Entities.User

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn -> %{users: %{}} end,
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
  # UserRepository Implementation
  # ============================================================================

  @impl true
  def find(id) do
    case Agent.get(__MODULE__, fn state -> Map.get(state.users, id) end) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @impl true
  def find_by_email(email) do
    email_lower = String.downcase(email)

    Agent.get(__MODULE__, fn state ->
      result =
        state.users
        |> Map.values()
        |> Enum.find(fn user -> String.downcase(user.email) == email_lower end)

      case result do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end)
  end

  @impl true
  def save(%User{} = user) do
    now = DateTime.utc_now()

    user =
      if user.id do
        %{user | updated_at: now}
      else
        %{user | id: Ecto.UUID.generate(), created_at: now, updated_at: now}
      end

    # Check for email uniqueness
    case check_email_uniqueness(user) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{state | users: Map.put(state.users, user.id, user)}
        end)

        {:ok, user}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def list(opts \\ []) do
    org_filter = Keyword.get(opts, :organization_id)
    role_filter = Keyword.get(opts, :role)
    system_admin_filter = Keyword.get(opts, :system_admin)
    confirmed_filter = Keyword.get(opts, :confirmed)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    Agent.get(__MODULE__, fn state ->
      state.users
      |> Map.values()
      |> filter_by_organization(org_filter)
      |> filter_by_role(role_filter)
      |> filter_by_system_admin(system_admin_filter)
      |> filter_by_confirmed(confirmed_filter)
      |> filter_by_search(search)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.drop(offset)
      |> maybe_limit(limit)
    end)
  end

  @impl true
  def delete(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.pop(state.users, id) do
        {nil, _} ->
          {{:error, :not_found}, state}

        {user, new_users} ->
          {{:ok, user}, %{state | users: new_users}}
      end
    end)
  end

  # ============================================================================
  # Organization-scoped Operations
  # ============================================================================

  @impl true
  def list_for_organization(org_id, opts \\ []) do
    list(Keyword.put(opts, :organization_id, org_id))
  end

  @impl true
  def count_for_organization(org_id) do
    Agent.get(__MODULE__, fn state ->
      state.users
      |> Map.values()
      |> Enum.count(fn user -> user.organization_id == org_id end)
    end)
  end

  @impl true
  def find_by_email_in_organization(org_id, email) do
    email_lower = String.downcase(email)

    Agent.get(__MODULE__, fn state ->
      result =
        state.users
        |> Map.values()
        |> Enum.find(fn user ->
          user.organization_id == org_id && String.downcase(user.email) == email_lower
        end)

      case result do
        nil -> {:error, :not_found}
        user -> {:ok, user}
      end
    end)
  end

  # ============================================================================
  # Email Uniqueness
  # ============================================================================

  @impl true
  def email_taken?(email, exclude_user_id \\ nil) do
    email_lower = String.downcase(email)

    Agent.get(__MODULE__, fn state ->
      state.users
      |> Map.values()
      |> Enum.any?(fn user ->
        String.downcase(user.email) == email_lower && user.id != exclude_user_id
      end)
    end)
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all users in the repository.
  """
  def all do
    Agent.get(__MODULE__, fn state -> Map.values(state.users) end)
  end

  @doc """
  Returns the count of users.
  """
  def count do
    Agent.get(__MODULE__, fn state -> map_size(state.users) end)
  end

  @doc """
  Clears all data from the repository.
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{users: %{}} end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp check_email_uniqueness(%User{id: id, email: email}) do
    if email_taken?(email, id) do
      {:error, :email_already_taken}
    else
      :ok
    end
  end

  defp filter_by_organization(users, nil), do: users

  defp filter_by_organization(users, org_id) do
    Enum.filter(users, &(&1.organization_id == org_id))
  end

  defp filter_by_role(users, nil), do: users

  defp filter_by_role(users, role) do
    Enum.filter(users, &(&1.role == role))
  end

  defp filter_by_system_admin(users, nil), do: users

  defp filter_by_system_admin(users, system_admin) do
    Enum.filter(users, &(&1.system_admin == system_admin))
  end

  defp filter_by_confirmed(users, nil), do: users

  defp filter_by_confirmed(users, true) do
    Enum.filter(users, &(&1.confirmed_at != nil))
  end

  defp filter_by_confirmed(users, false) do
    Enum.filter(users, &(&1.confirmed_at == nil))
  end

  defp filter_by_search(users, nil), do: users

  defp filter_by_search(users, search) do
    search_lower = String.downcase(search)

    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.email || ""), search_lower)
    end)
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit), do: Enum.take(items, limit)
end
