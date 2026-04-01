defmodule Cadence.Ports.Repository.DashboardLayouts.DashboardLayoutRepository do
  @moduledoc """
  Port (behavior) defining the contract for dashboard layout persistence operations.

  This behavior abstracts the persistence layer from the domain, enabling:
  - Unit testing with in-memory implementations
  - Swapping storage backends without changing domain logic
  - Clear separation between domain entities and database schemas

  ## Implementations

  - `Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository` - Production Ecto/PostgreSQL
  - `Cadence.Test.Adapters.InMemoryDashboardLayoutRepository` - In-memory for tests
  """

  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout

  @type id :: String.t()
  @type user_id :: String.t()
  @type mission_id :: String.t() | nil
  @type opts :: keyword()
  @type error :: :not_found | {:validation, map()} | term()

  @doc """
  Finds a dashboard layout by ID.

  Returns `{:ok, layout}` if found, `{:error, :not_found}` otherwise.
  """
  @callback find(id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}

  @doc """
  Finds a dashboard layout by ID scoped to a user.

  Returns `{:ok, layout}` if found and owned by user, `{:error, :not_found}` otherwise.
  """
  @callback find_for_user(id(), user_id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}

  @doc """
  Finds a user's layout for a specific mission.

  Returns the default layout if one exists, otherwise the most recently updated.
  Returns `{:error, :not_found}` if no layouts exist.
  """
  @callback find_user_layout(user_id(), mission_id()) ::
              {:ok, DashboardLayout.t()} | {:error, :not_found}

  @doc """
  Finds a user's default layout (mission-agnostic).

  Returns the layout where mission_id is nil and is_default is true.
  """
  @callback find_user_default(user_id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}

  @doc """
  Lists all layouts for a user and mission.

  Returns layouts ordered by is_default desc, name asc.
  """
  @callback list_for_user(user_id(), mission_id()) :: [DashboardLayout.t()]

  @doc """
  Persists a dashboard layout (insert or update).

  Returns `{:ok, layout}` with the persisted entity, or `{:error, reason}` on failure.
  """
  @callback save(DashboardLayout.t()) :: {:ok, DashboardLayout.t()} | {:error, error()}

  @doc """
  Deletes a dashboard layout by ID.

  Returns `{:ok, layout}` with the deleted entity, or `{:error, :not_found}`.
  """
  @callback delete(id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}

  @doc """
  Unsets default flag for all layouts of a user/mission except the given ID.

  Used when setting a new default layout.
  Returns the count of updated layouts.
  """
  @callback unset_other_defaults(user_id(), mission_id(), exclude_id :: id()) ::
              {:ok, non_neg_integer()}

  @doc """
  Returns the configured dashboard layout repository implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :dashboard_layout_repository,
      Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository
    )
  end
end
