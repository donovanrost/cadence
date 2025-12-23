defmodule Cadence.Application.DashboardLayouts.DashboardLayoutOperations do
  @moduledoc """
  Use case module for dashboard layout state changes.

  Provides operations for creating, updating, and deleting dashboard layouts.
  """

  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout

  # Get configured repository
  defp repo do
    Application.get_env(
      :cadence,
      :dashboard_layout_repository,
      Cadence.Adapters.Persistence.Ecto.DashboardLayouts.EctoDashboardLayoutRepository
    )
  end

  @doc """
  Creates a new dashboard layout.

  ## Parameters

  - `attrs` - Map with required keys: `:name`, `:user_id`
              Optional keys: `:mission_id`, `:is_default`, `:frame_layout`, `:widgets`

  ## Returns

  - `{:ok, layout}` - Layout created successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec create(map()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def create(attrs) do
    with {:ok, layout} <- DashboardLayout.new(attrs),
         {:ok, saved} <- repo().save(layout) do
      {:ok, saved}
    end
  end

  @doc """
  Saves a layout (creates if new, updates if existing).

  ## Parameters

  - `layout` - The dashboard layout entity
  - `attrs` - Map of attributes to update

  ## Returns

  - `{:ok, layout}` - Layout saved successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec save(DashboardLayout.t(), map()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def save(%DashboardLayout{} = layout, attrs) do
    updated =
      layout
      |> maybe_update_name(attrs)
      |> maybe_update_frame_layout(attrs)
      |> maybe_update_widgets(attrs)
      |> maybe_update_default(attrs)

    case updated do
      {:ok, layout} -> repo().save(layout)
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates only the frame layout portion.

  ## Parameters

  - `layout` - The dashboard layout entity
  - `frame_layout` - The new frame layout map

  ## Returns

  - `{:ok, layout}` - Layout updated successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec update_frame_layout(DashboardLayout.t(), map()) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def update_frame_layout(%DashboardLayout{} = layout, frame_layout) do
    with {:ok, updated} <- DashboardLayout.update_frame_layout(layout, frame_layout),
         {:ok, saved} <- repo().save(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Updates only the widgets portion.

  ## Parameters

  - `layout` - The dashboard layout entity
  - `widgets` - The new widgets list

  ## Returns

  - `{:ok, layout}` - Layout updated successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec update_widgets(DashboardLayout.t(), [map()]) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def update_widgets(%DashboardLayout{} = layout, widgets) do
    with {:ok, updated} <- DashboardLayout.update_widgets(layout, widgets),
         {:ok, saved} <- repo().save(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Sets a layout as the default for the user/mission combo.

  Unsets any other default layout for the same user/mission.

  ## Parameters

  - `layout` - The dashboard layout entity to set as default

  ## Returns

  - `{:ok, layout}` - Layout set as default successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec set_default(DashboardLayout.t()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def set_default(%DashboardLayout{id: nil}) do
    {:error, :layout_not_persisted}
  end

  def set_default(%DashboardLayout{} = layout) do
    # Unset any existing defaults
    {:ok, _count} = repo().unset_other_defaults(layout.user_id, layout.mission_id, layout.id)

    # Set this one as default
    with {:ok, updated} <- DashboardLayout.set_default(layout, true),
         {:ok, saved} <- repo().save(updated) do
      {:ok, saved}
    end
  end

  @doc """
  Deletes a dashboard layout.

  ## Parameters

  - `layout` - The dashboard layout entity to delete

  ## Returns

  - `{:ok, layout}` - Layout deleted successfully
  - `{:error, :not_found}` - Layout not found
  """
  @spec delete(DashboardLayout.t()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def delete(%DashboardLayout{id: nil}) do
    {:error, :layout_not_persisted}
  end

  def delete(%DashboardLayout{id: id}) do
    repo().delete(id)
  end

  @doc """
  Duplicates a layout with a new name.

  ## Parameters

  - `layout` - The dashboard layout entity to duplicate
  - `new_name` - The name for the new layout

  ## Returns

  - `{:ok, layout}` - New layout created successfully
  - `{:error, reason}` - Validation or persistence error
  """
  @spec duplicate(DashboardLayout.t(), String.t()) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def duplicate(%DashboardLayout{} = layout, new_name) do
    with {:ok, new_layout} <- DashboardLayout.duplicate(layout, new_name),
         {:ok, saved} <- repo().save(new_layout) do
      {:ok, saved}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp maybe_update_name(layout, %{name: name}) when is_binary(name) do
    DashboardLayout.update_name(layout, name)
  end

  defp maybe_update_name(layout, _), do: {:ok, layout}

  defp maybe_update_frame_layout({:ok, layout}, %{frame_layout: frame_layout}) do
    DashboardLayout.update_frame_layout(layout, frame_layout)
  end

  defp maybe_update_frame_layout(result, _), do: result

  defp maybe_update_widgets({:ok, layout}, %{widgets: widgets}) when is_list(widgets) do
    DashboardLayout.update_widgets(layout, widgets)
  end

  defp maybe_update_widgets(result, _), do: result

  defp maybe_update_default({:ok, layout}, %{is_default: is_default}) when is_boolean(is_default) do
    DashboardLayout.set_default(layout, is_default)
  end

  defp maybe_update_default(result, _), do: result
end
