defmodule Cadence.Dashboards.DashboardLibraryItem do
  @moduledoc "Mission-scoped reusable widget identity with explicit immutable versions."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_library_item_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @type t :: %__MODULE__{}

  schema "dashboard_library_items" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:name, :string)
    field(:description, :string)
    field(:latest_version, :integer, default: 1)
    field(:created_by, :string)
    field(:updated_by, :string)
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :dashboard_library_item_id,
      :organization_id,
      :mission_id,
      :name,
      :description,
      :latest_version,
      :created_by,
      :updated_by
    ])
    |> validate_required([:dashboard_library_item_id, :mission_id, :name, :latest_version])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_number(:latest_version, greater_than: 0)
    |> unique_constraint(:name, name: :dashboard_library_items_scope_name_idx)
  end
end
