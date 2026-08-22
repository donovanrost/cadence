defmodule Cadence.Dashboards.DashboardLibraryVersion do
  @moduledoc "One immutable, pinned reusable widget definition."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_library_version_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  @type t :: %__MODULE__{}

  schema "dashboard_library_versions" do
    field(:dashboard_library_item_id, :string)
    field(:version, :integer)
    field(:widget_definition, :map)
    field(:compatibility, :map, default: %{})
    field(:change_summary, :string)
    field(:created_by, :string)
    timestamps()
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :dashboard_library_version_id,
      :dashboard_library_item_id,
      :version,
      :widget_definition,
      :compatibility,
      :change_summary,
      :created_by
    ])
    |> validate_required([
      :dashboard_library_version_id,
      :dashboard_library_item_id,
      :version,
      :widget_definition,
      :compatibility
    ])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:dashboard_library_item_id, :version],
      name: :dashboard_library_versions_item_version_idx
    )
  end
end
