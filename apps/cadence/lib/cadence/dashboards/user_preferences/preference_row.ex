defmodule Cadence.Dashboards.UserPreferences.PreferenceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.DashboardUserPreference
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:dashboard_user_preference_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_user_preferences" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:user_id, :string)
    field(:dashboard_id, :string)
    field(:starred, :boolean, default: false)
    field(:last_viewed_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields [
    :dashboard_user_preference_id,
    :mission_id,
    :user_id,
    :dashboard_id,
    :starred
  ]

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint(
      [:organization_id, :mission_id, :user_id, :dashboard_id],
      name: :dashboard_user_preferences_scope_idx
    )
  end

  @spec to_domain(%__MODULE__{}) :: DashboardUserPreference.t()
  def to_domain(%__MODULE__{} = row) do
    %DashboardUserPreference{
      dashboard_user_preference_id: row.dashboard_user_preference_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      user_id: row.user_id,
      dashboard_id: row.dashboard_id,
      starred: row.starred,
      last_viewed_at: row.last_viewed_at,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    }
  end
end
