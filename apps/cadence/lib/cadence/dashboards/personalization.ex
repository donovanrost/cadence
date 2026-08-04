defmodule Cadence.Dashboards.Personalization do
  @moduledoc "User-specific dashboard preferences and investigation presets."

  alias Cadence.Dashboards.{InvestigationPresets, UserPreferences}

  defdelegate list_preferences(organization_id, mission_id, user_id),
    to: UserPreferences,
    as: :list

  defdelegate navigation(organization_id, mission_id, user_id, summaries),
    to: UserPreferences

  defdelegate set_starred(
                organization_id,
                mission_id,
                user_id,
                dashboard_id,
                starred,
                opts
              ),
              to: UserPreferences

  defdelegate record_view(organization_id, mission_id, user_id, dashboard_id, opts),
    to: UserPreferences

  defdelegate save_preset(organization_id, mission_id, dashboard_id, attrs, opts),
    to: InvestigationPresets,
    as: :save

  defdelegate list_presets(organization_id, mission_id, dashboard_id, opts),
    to: InvestigationPresets,
    as: :list

  defdelegate fetch_preset(organization_id, mission_id, dashboard_id, preset_id),
    to: InvestigationPresets,
    as: :fetch

  defdelegate delete_preset(organization_id, mission_id, dashboard_id, preset_id),
    to: InvestigationPresets,
    as: :delete
end
