defmodule CadenceWeb.API.IdentityJSON do
  @moduledoc "Identity and tenancy response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate bootstrap(value), to: LegacyJSON
  defdelegate bootstrap_admin_session(value), to: LegacyJSON
  defdelegate current_scope(value), to: LegacyJSON
  defdelegate user(value), to: LegacyJSON
  defdelegate organization(value), to: LegacyJSON
  defdelegate mission(value), to: LegacyJSON
  defdelegate service_identity(value), to: LegacyJSON
  defdelegate issued_service_identity(value), to: LegacyJSON
end
