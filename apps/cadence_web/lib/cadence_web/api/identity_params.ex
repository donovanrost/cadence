defmodule CadenceWeb.API.IdentityParams do
  @moduledoc "Identity and tenancy request parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate bootstrap_admin_session(params), to: LegacyParams
  defdelegate durable_session(params), to: LegacyParams
  defdelegate organization_invitation_acceptance(params), to: LegacyParams
  defdelegate organization(params), to: LegacyParams
  defdelegate mission(organization_id, params), to: LegacyParams
  defdelegate service_identity(organization_id, params), to: LegacyParams
  defdelegate bootstrap_service_identity(organization_id, params), to: LegacyParams
  defdelegate bootstrap_mission(organization_id, params), to: LegacyParams
end
