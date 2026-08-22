defmodule Cadence.Dashboards.DashboardPlaylist do
  @moduledoc "Ordered dashboard references for presentation and wallboard rotation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_playlist_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  @type t :: %__MODULE__{}

  schema "dashboard_playlists" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:name, :string)
    field(:description, :string)
    field(:dashboard_ids, {:array, :string}, default: [])
    field(:dwell_seconds, :integer, default: 30)
    field(:wallboard_mode, :boolean, default: false)
    field(:created_by, :string)
    field(:updated_by, :string)
    timestamps()
  end

  def changeset(playlist, attrs) do
    playlist
    |> cast(attrs, [
      :dashboard_playlist_id,
      :organization_id,
      :mission_id,
      :name,
      :description,
      :dashboard_ids,
      :dwell_seconds,
      :wallboard_mode,
      :created_by,
      :updated_by
    ])
    |> validate_required([:dashboard_playlist_id, :mission_id, :name, :dashboard_ids])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_number(:dwell_seconds, greater_than_or_equal_to: 5, less_than_or_equal_to: 900)
    |> unique_constraint(:name, name: :dashboard_playlists_scope_name_idx)
  end
end
