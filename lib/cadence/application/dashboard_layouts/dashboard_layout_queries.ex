defmodule Cadence.Application.DashboardLayouts.DashboardLayoutQueries do
  @moduledoc """
  Query operations for dashboard layouts.

  Provides read-only operations for retrieving dashboard layouts.
  """

  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout

  @type user_id :: String.t()
  @type mission_id :: String.t() | nil

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :dashboard_layout_repository,
      Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository
    )
  end

  @doc """
  Finds a dashboard layout by ID.

  Returns `{:ok, layout}` if found, `{:error, :not_found}` otherwise.
  """
  @spec find(String.t()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}
  def find(id), do: repo().find(id)

  @doc """
  Finds a dashboard layout by ID scoped to a user.

  Returns `{:ok, layout}` if found and owned by user, `{:error, :not_found}` otherwise.
  """
  @spec find_for_user(String.t(), user_id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}
  def find_for_user(id, user_id), do: repo().find_for_user(id, user_id)

  @doc """
  Gets a user's layout for a specific mission.

  Returns the default layout if one exists, otherwise the most recently updated.
  If no layouts exist, returns a new unsaved layout with default configuration.
  """
  @spec get_user_layout(user_id(), mission_id()) :: DashboardLayout.t()
  def get_user_layout(user_id, mission_id) do
    case repo().find_user_layout(user_id, mission_id) do
      {:ok, layout} ->
        layout

      {:error, :not_found} ->
        # Return a new unsaved layout
        {:ok, layout} =
          DashboardLayout.new(%{name: "Default", user_id: user_id, mission_id: mission_id})

        layout
    end
  end

  @doc """
  Gets a user's default layout (mission-agnostic).

  Returns `{:ok, layout}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_user_default(user_id()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}
  def get_user_default(user_id), do: repo().find_user_default(user_id)

  @doc """
  Lists all layouts for a user and mission.
  """
  @spec list_for_user(user_id(), mission_id()) :: [DashboardLayout.t()]
  def list_for_user(user_id, mission_id), do: repo().list_for_user(user_id, mission_id)
end
