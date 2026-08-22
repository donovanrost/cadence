defmodule Cadence.Dashboards.DashboardSnapshot do
  @moduledoc "Immutable dashboard definition and runtime-context snapshot."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_snapshot_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  @type t :: %__MODULE__{}

  schema "dashboard_snapshots" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:dashboard_version, :integer)
    field(:created_by, :string)
    field(:runtime_context, :map, default: %{})
    field(:data_semantics, :string)
    field(:data_visibility, :string, default: "authorized_runtime_data")
    field(:document, :map)
    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :dashboard_snapshot_id,
      :organization_id,
      :mission_id,
      :dashboard_id,
      :dashboard_version,
      :created_by,
      :runtime_context,
      :data_semantics,
      :data_visibility,
      :document
    ])
    |> validate_required([
      :dashboard_snapshot_id,
      :mission_id,
      :dashboard_id,
      :dashboard_version,
      :runtime_context,
      :data_semantics,
      :data_visibility,
      :document
    ])
    |> validate_inclusion(:data_semantics, [
      "definition_at_version_current_data",
      "frozen_time_window"
    ])
    |> validate_inclusion(:data_visibility, ["authorized_runtime_data", "definition_only"])
  end
end
