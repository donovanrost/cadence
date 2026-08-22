defmodule Cadence.Dashboards.DashboardUserPreference do
  @moduledoc """
  User-scoped dashboard discovery state for one organization and mission.

  This state never changes a shared Dashboard Document.
  """

  @type t :: %__MODULE__{
          dashboard_user_preference_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          user_id: binary(),
          dashboard_id: binary(),
          starred: boolean(),
          last_viewed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :dashboard_user_preference_id,
    :organization_id,
    :mission_id,
    :user_id,
    :dashboard_id,
    :last_viewed_at,
    :inserted_at,
    :updated_at,
    starred: false
  ]
end
