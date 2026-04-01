defmodule Cadence.DashboardLayouts.DashboardLayout do
  @moduledoc """
  Schema for user dashboard layouts.

  Each user can have multiple saved layouts per mission, with one marked as default.
  Layouts store both the Golden Layout frame configuration and gridstack widget positions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Accounts.User
  alias Cadence.Missions.Mission

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboard_layouts" do
    field :name, :string
    field :is_default, :boolean, default: false

    # Golden Layout state (panel positions, sizes)
    field :frame_layout, :map

    # gridstack widget positions and configs
    field :widgets, {:array, :map}, default: []

    belongs_to :user, User
    belongs_to :mission, Mission

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new dashboard layout.
  """
  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:name, :is_default, :frame_layout, :widgets, :user_id, :mission_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:mission_id)
    |> unique_constraint([:user_id, :mission_id, :name],
      name: "dashboard_layouts_user_id_mission_id_name_index",
      message: "Layout with this name already exists"
    )
  end

  @doc """
  Creates a changeset for updating frame layout only.
  """
  def frame_layout_changeset(layout, frame_layout) do
    layout
    |> cast(%{frame_layout: frame_layout}, [:frame_layout])
  end

  @doc """
  Creates a changeset for updating widgets only.
  """
  def widgets_changeset(layout, widgets) do
    layout
    |> cast(%{widgets: widgets}, [:widgets])
  end

  @doc """
  Creates a changeset for setting default status.
  """
  def default_changeset(layout, is_default) do
    layout
    |> cast(%{is_default: is_default}, [:is_default])
  end
end
