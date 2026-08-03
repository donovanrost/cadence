defmodule Cadence.Dashboards.DashboardShare do
  @moduledoc "Authenticated, mission-scoped dashboard share with explicit visibility semantics."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dashboard_share_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]
  @type t :: %__MODULE__{}

  schema "dashboard_shares" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:dashboard_id, :string)
    field(:created_by, :string)
    field(:access_policy, :string, default: "mission_member")
    field(:data_visibility, :string, default: "authorized_runtime_data")
    field(:runtime_context, :map, default: %{})
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    timestamps()
  end

  def changeset(share, attrs) do
    share
    |> cast(attrs, [
      :dashboard_share_id,
      :organization_id,
      :mission_id,
      :dashboard_id,
      :created_by,
      :access_policy,
      :data_visibility,
      :runtime_context,
      :expires_at,
      :revoked_at
    ])
    |> validate_required([
      :dashboard_share_id,
      :mission_id,
      :dashboard_id,
      :access_policy,
      :data_visibility,
      :runtime_context
    ])
    |> validate_inclusion(:access_policy, ["mission_member"])
    |> validate_inclusion(:data_visibility, ["authorized_runtime_data", "definition_only"])
  end
end
