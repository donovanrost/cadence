defmodule Cadence.DashboardLayouts do
  @moduledoc """
  Context module for managing user dashboard layouts.

  Provides functions for creating, updating, and retrieving dashboard layouts.
  Each user can have multiple layouts per mission with one marked as default.
  """

  import Ecto.Query, warn: false
  alias Cadence.Repo
  alias Cadence.DashboardLayouts.DashboardLayout

  @doc """
  Gets a user's layout for a specific mission.

  Returns the default layout if one exists, otherwise the most recently updated.
  If no layouts exist, returns a new unsaved layout with default configuration.
  """
  def get_user_layout(user, mission_id) do
    query =
      from l in DashboardLayout,
        where: l.user_id == ^user.id and l.mission_id == ^mission_id,
        order_by: [desc: l.is_default, desc: l.updated_at],
        limit: 1

    case Repo.one(query) do
      nil -> %DashboardLayout{user_id: user.id, mission_id: mission_id, name: "Default"}
      layout -> layout
    end
  end

  @doc """
  Gets a user's default layout (mission-agnostic).

  Returns the layout where mission_id is nil and is_default is true.
  """
  def get_user_default_layout(user) do
    query =
      from l in DashboardLayout,
        where: l.user_id == ^user.id and is_nil(l.mission_id) and l.is_default == true,
        limit: 1

    Repo.one(query)
  end

  @doc """
  Lists all layouts for a user and mission.
  """
  def list_user_layouts(user, mission_id) do
    query =
      from l in DashboardLayout,
        where: l.user_id == ^user.id and l.mission_id == ^mission_id,
        order_by: [desc: l.is_default, asc: l.name]

    Repo.all(query)
  end

  @doc """
  Gets a layout by ID scoped to a user.

  Returns `{:ok, layout}` or `{:error, :not_found}`.
  """
  def get_layout(id, user_id) do
    query =
      from l in DashboardLayout,
        where: l.id == ^id and l.user_id == ^user_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      layout -> {:ok, layout}
    end
  end

  @doc """
  Gets a layout by ID without user scoping.

  WARNING: This bypasses ownership checks. Only use for internal operations
  where user context is verified elsewhere.
  """
  def get_layout_unscoped(id) do
    case Repo.get(DashboardLayout, id) do
      nil -> {:error, :not_found}
      layout -> {:ok, layout}
    end
  end

  @doc """
  Creates a new dashboard layout.
  """
  def create_layout(attrs \\ %{}) do
    %DashboardLayout{}
    |> DashboardLayout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates or updates the user's layout for a mission.

  If the layout is new (no id), creates it.
  If it exists, updates it.
  """
  def save_layout(%DashboardLayout{id: nil} = layout, attrs) do
    layout
    |> DashboardLayout.changeset(attrs)
    |> Repo.insert()
  end

  def save_layout(%DashboardLayout{} = layout, attrs) do
    layout
    |> DashboardLayout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only the frame layout portion.
  """
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
    layout
    |> DashboardLayout.frame_layout_changeset(frame_layout)
    |> Repo.update()
  end

  @doc """
  Updates only the widgets portion.
  """
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
    layout
    |> DashboardLayout.widgets_changeset(widgets)
    |> Repo.update()
  end

  @doc """
  Sets a layout as the default for the user/mission combo.

  Unsets any other default layout for the same user/mission.
  """
  def set_default(%DashboardLayout{} = layout) do
    Repo.transaction(fn ->
      # Unset any existing defaults
      from(l in DashboardLayout,
        where:
          l.user_id == ^layout.user_id and
            l.mission_id == ^layout.mission_id and
            l.id != ^layout.id
      )
      |> Repo.update_all(set: [is_default: false])

      # Set this one as default
      layout
      |> DashboardLayout.default_changeset(true)
      |> Repo.update!()
    end)
  end

  @doc """
  Deletes a dashboard layout.
  """
  def delete_layout(%DashboardLayout{} = layout) do
    Repo.delete(layout)
  end

  @doc """
  Duplicates a layout with a new name.
  """
  def duplicate_layout(%DashboardLayout{} = layout, new_name) do
    %DashboardLayout{}
    |> DashboardLayout.changeset(%{
      name: new_name,
      frame_layout: layout.frame_layout,
      widgets: layout.widgets,
      user_id: layout.user_id,
      mission_id: layout.mission_id,
      is_default: false
    })
    |> Repo.insert()
  end

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
