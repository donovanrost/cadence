defmodule CadenceWeb.API.CommsParams do
  @moduledoc "Spacecraft and communications configuration request parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate source_endpoint(organization_id, mission_id, params), to: LegacyParams

  defdelegate source_endpoint(organization_id, mission_id, spacecraft_id, params),
    to: LegacyParams

  defdelegate spacecraft(organization_id, mission_id, params), to: LegacyParams
  defdelegate provider_profile(organization_id, mission_id, params), to: LegacyParams
  defdelegate provider_profile_patch(params), to: LegacyParams
  defdelegate transport_profile(organization_id, mission_id, params), to: LegacyParams
  defdelegate transport_profile_patch(params), to: LegacyParams
  defdelegate path_template(organization_id, mission_id, params), to: LegacyParams
  defdelegate path_template_patch(params), to: LegacyParams
  defdelegate link_assignment(organization_id, mission_id, params), to: LegacyParams
  defdelegate link_assignment_delete(params), to: LegacyParams
  defdelegate link_template_application(params), to: LegacyParams
  defdelegate resource_version(params, key \\ "version"), to: LegacyParams
end
