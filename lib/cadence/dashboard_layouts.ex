defmodule Cadence.DashboardLayouts do
  @moduledoc """
  Context module for managing user dashboard layouts.

  Provides functions for creating, updating, and retrieving dashboard layouts.
  Each user can have multiple layouts per mission with one marked as default.

  This module serves as the public API facade, delegating to:
  - `Cadence.Application.DashboardLayouts.DashboardLayoutQueries` for read operations
  - `Cadence.Application.DashboardLayouts.DashboardLayoutOperations` for write operations
  """

  alias Cadence.Domain.DashboardLayouts.Entities.DashboardLayout
  alias Cadence.Application.DashboardLayouts.DashboardLayoutQueries
  alias Cadence.Application.DashboardLayouts.DashboardLayoutOperations

  # ============================================================================
  # Query Operations
  # ============================================================================

  @doc """
  Gets a user's layout for a specific mission.

  Returns the default layout if one exists, otherwise the most recently updated.
  If no layouts exist, returns a new unsaved layout with default configuration.
  """
  @spec get_user_layout(map(), String.t()) :: DashboardLayout.t()
  def get_user_layout(user, mission_id) do
    DashboardLayoutQueries.get_user_layout(user.id, mission_id)
  end

  @doc """
  Gets a user's default layout (mission-agnostic).

  Returns the layout where mission_id is nil and is_default is true.
  """
  @spec get_user_default_layout(map()) :: DashboardLayout.t() | nil
  def get_user_default_layout(user) do
    case DashboardLayoutQueries.get_user_default(user.id) do
      {:ok, layout} -> layout
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Lists all layouts for a user and mission.
  """
  @spec list_user_layouts(map(), String.t()) :: [DashboardLayout.t()]
  def list_user_layouts(user, mission_id) do
    DashboardLayoutQueries.list_for_user(user.id, mission_id)
  end

  @doc """
  Gets a layout by ID scoped to a user.

  Returns `{:ok, layout}` or `{:error, :not_found}`.
  """
  @spec get_layout(String.t(), String.t()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}
  def get_layout(id, user_id) do
    DashboardLayoutQueries.find_for_user(id, user_id)
  end

  @doc """
  Gets a layout by ID without user scoping.

  WARNING: This bypasses ownership checks. Only use for internal operations
  where user context is verified elsewhere.
  """
  @spec get_layout_unscoped(String.t()) :: {:ok, DashboardLayout.t()} | {:error, :not_found}
  def get_layout_unscoped(id) do
    DashboardLayoutQueries.find(id)
  end

  # ============================================================================
  # Write Operations
  # ============================================================================

  @doc """
  Creates a new dashboard layout.
  """
  @spec create_layout(map()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def create_layout(attrs \\ %{}) do
    DashboardLayoutOperations.create(attrs)
  end

  @doc """
  Creates or updates the user's layout for a mission.

  If the layout is new (no id), creates it.
  If it exists, updates it.
  """
  @spec save_layout(DashboardLayout.t(), map()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def save_layout(%DashboardLayout{} = layout, attrs) do
    # For new layouts, ensure required fields are set
    attrs =
      if layout.id == nil do
        Map.merge(
          %{
            name: layout.name || "Default",
            user_id: layout.user_id,
            mission_id: layout.mission_id
          },
          attrs
        )
      else
        attrs
      end

    if layout.id == nil do
      DashboardLayoutOperations.create(attrs)
    else
      DashboardLayoutOperations.save(layout, attrs)
    end
  end

  @doc """
  Updates only the frame layout portion.
  """
  @spec update_frame_layout(DashboardLayout.t(), map()) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def update_frame_layout(%DashboardLayout{id: nil} = layout, frame_layout) do
    # Save new layout first
    save_layout(layout, %{
      name: layout.name || "Default",
      frame_layout: frame_layout,
      user_id: layout.user_id,
      mission_id: layout.mission_id
    })
  end

  def update_frame_layout(%DashboardLayout{} = layout, frame_layout) do
    DashboardLayoutOperations.update_frame_layout(layout, frame_layout)
  end

  @doc """
  Updates only the widgets portion.
  """
  @spec update_widgets(DashboardLayout.t(), [map()]) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def update_widgets(%DashboardLayout{id: nil} = layout, widgets) do
    # Save new layout first
    save_layout(layout, %{
      name: layout.name || "Default",
      widgets: widgets,
      user_id: layout.user_id,
      mission_id: layout.mission_id
    })
  end

  def update_widgets(%DashboardLayout{} = layout, widgets) do
    DashboardLayoutOperations.update_widgets(layout, widgets)
  end

  @doc """
  Sets a layout as the default for the user/mission combo.

  Unsets any other default layout for the same user/mission.
  """
  @spec set_default(DashboardLayout.t()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def set_default(%DashboardLayout{} = layout) do
    DashboardLayoutOperations.set_default(layout)
  end

  @doc """
  Deletes a dashboard layout.
  """
  @spec delete_layout(DashboardLayout.t()) :: {:ok, DashboardLayout.t()} | {:error, term()}
  def delete_layout(%DashboardLayout{} = layout) do
    DashboardLayoutOperations.delete(layout)
  end

  @doc """
  Duplicates a layout with a new name.
  """
  @spec duplicate_layout(DashboardLayout.t(), String.t()) ::
          {:ok, DashboardLayout.t()} | {:error, term()}
  def duplicate_layout(%DashboardLayout{} = layout, new_name) do
    DashboardLayoutOperations.duplicate(layout, new_name)
  end

  # ============================================================================
  # Default Configuration
  # ============================================================================

  # Panel size constants (in pixels)
  # Compact widths (collapsed state - icon/badge only)
  @nav_panel_compact_width 120
  @context_panel_compact_width 64
  # Dashboard doesn't collapse
  @dashboard_min_width 400

  @doc """
  Returns default layout configuration.
  """
  def default_frame_layout do
    %{
      "settings" => %{
        "showPopoutIcon" => false,
        "showMaximiseIcon" => false,
        "showCloseIcon" => false
      },
      "dimensions" => %{
        "defaultMinItemWidth" => 100
      },
      "header" => %{
        "show" => "top",
        "popout" => false,
        "maximise" => false,
        "close" => false,
        "minimise" => false
      },
      "root" => %{
        "type" => "row",
        "content" => [
          %{
            "type" => "component",
            "componentType" => "navigation",
            "title" => "Navigation",
            "isClosable" => false,
            "header" => %{"show" => false},
            "minWidth" => @nav_panel_compact_width,
            "componentState" => %{}
          },
          %{
            "type" => "component",
            "componentType" => "dashboard",
            "title" => "Dashboard",
            "isClosable" => false,
            "header" => %{"show" => false},
            "minWidth" => @dashboard_min_width,
            "componentState" => %{}
          },
          %{
            "type" => "component",
            "componentType" => "context",
            "title" => "Context",
            "isClosable" => false,
            "header" => %{"show" => false},
            "minWidth" => @context_panel_compact_width,
            "componentState" => %{}
          }
        ]
      }
    }
  end
end
