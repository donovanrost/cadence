defmodule Cadence.Domain.DashboardLayouts.Entities.DashboardLayout do
  @moduledoc """
  Pure domain entity representing a dashboard layout.

  This entity contains the business logic for dashboard layout management,
  completely independent of any persistence or infrastructure concerns.

  ## Fields

  - `:id` - Unique identifier (nil for new layouts)
  - `:name` - User-given name for the layout
  - `:user_id` - Owner of the layout
  - `:mission_id` - Associated mission (nil for global layouts)
  - `:is_default` - Whether this is the default layout for user/mission
  - `:frame_layout` - Golden Layout panel configuration
  - `:widgets` - GridStack widget positions and configs
  - `:created_at` - When the layout was created
  - `:updated_at` - When the layout was last updated

  ## Immutability

  All operations return a new layout struct rather than mutating in place.
  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          user_id: String.t(),
          mission_id: String.t() | nil,
          is_default: boolean(),
          frame_layout: map() | nil,
          widgets: [map()],
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @enforce_keys [:name, :user_id]

  defstruct [
    :id,
    :name,
    :user_id,
    :mission_id,
    :frame_layout,
    :created_at,
    :updated_at,
    is_default: false,
    widgets: []
  ]

  # ===========================================================================
  # Construction
  # ===========================================================================

  @doc """
  Creates a new dashboard layout with the given attributes.

  Returns `{:ok, layout}` if valid, `{:error, reason}` otherwise.

  ## Required Attributes

  - `:name` - Layout name (1-100 characters)
  - `:user_id` - Owner's user ID

  ## Optional Attributes

  - `:id` - UUID (assigned by repository if not provided)
  - `:mission_id` - Associated mission (nil for global layouts)
  - `:is_default` - Whether this is the default (default: false)
  - `:frame_layout` - Panel configuration map
  - `:widgets` - List of widget configuration maps
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_name(attrs) do
      layout = %__MODULE__{
        id: Map.get(attrs, :id),
        name: Map.fetch!(attrs, :name),
        user_id: Map.fetch!(attrs, :user_id),
        mission_id: Map.get(attrs, :mission_id),
        is_default: Map.get(attrs, :is_default, false),
        frame_layout: Map.get(attrs, :frame_layout),
        widgets: Map.get(attrs, :widgets, []),
        created_at: Map.get(attrs, :created_at),
        updated_at: Map.get(attrs, :updated_at)
      }

      {:ok, layout}
    end
  end

  # ===========================================================================
  # Updates
  # ===========================================================================

  @doc """
  Updates the layout name.

  Returns `{:ok, layout}` if valid, `{:error, reason}` otherwise.
  """
  @spec update_name(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def update_name(%__MODULE__{} = layout, name) when is_binary(name) do
    with :ok <- validate_name(%{name: name}) do
      {:ok, %{layout | name: name}}
    end
  end

  @doc """
  Updates the frame layout configuration.
  """
  @spec update_frame_layout(t(), map()) :: {:ok, t()}
  def update_frame_layout(%__MODULE__{} = layout, frame_layout) when is_map(frame_layout) do
    {:ok, %{layout | frame_layout: frame_layout}}
  end

  def update_frame_layout(%__MODULE__{} = layout, nil) do
    {:ok, %{layout | frame_layout: nil}}
  end

  @doc """
  Updates the widgets configuration.
  """
  @spec update_widgets(t(), [map()]) :: {:ok, t()}
  def update_widgets(%__MODULE__{} = layout, widgets) when is_list(widgets) do
    {:ok, %{layout | widgets: widgets}}
  end

  @doc """
  Sets or unsets this layout as the default.
  """
  @spec set_default(t(), boolean()) :: {:ok, t()}
  def set_default(%__MODULE__{} = layout, is_default) when is_boolean(is_default) do
    {:ok, %{layout | is_default: is_default}}
  end

  @doc """
  Creates a duplicate of this layout with a new name.

  The duplicate will have:
  - A new ID (nil, to be assigned by repository)
  - The specified new name
  - is_default set to false
  - Same frame_layout and widgets
  """
  @spec duplicate(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def duplicate(%__MODULE__{} = layout, new_name) when is_binary(new_name) do
    new(%{
      name: new_name,
      user_id: layout.user_id,
      mission_id: layout.mission_id,
      frame_layout: layout.frame_layout,
      widgets: layout.widgets,
      is_default: false
    })
  end

  # ===========================================================================
  # Queries
  # ===========================================================================

  @doc """
  Returns true if the layout is persisted (has an ID).
  """
  @spec persisted?(t()) :: boolean()
  def persisted?(%__MODULE__{id: nil}), do: false
  def persisted?(%__MODULE__{id: _}), do: true

  @doc """
  Returns true if this is a global layout (no mission association).
  """
  @spec global?(t()) :: boolean()
  def global?(%__MODULE__{mission_id: nil}), do: true
  def global?(%__MODULE__{}), do: false

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  @required_fields [:name, :user_id]

  defp validate_required(attrs) do
    missing =
      @required_fields
      |> Enum.filter(fn field ->
        value = Map.get(attrs, field)
        is_nil(value) or value == ""
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  defp validate_name(%{name: name}) when is_binary(name) do
    cond do
      String.length(name) < 1 ->
        {:error, {:invalid_name, "name must be at least 1 character"}}

      String.length(name) > 100 ->
        {:error, {:invalid_name, "name must be at most 100 characters"}}

      true ->
        :ok
    end
  end

  defp validate_name(_), do: {:error, {:invalid_name, "name must be a string"}}
end
