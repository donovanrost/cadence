defmodule CadenceWeb.API.MissionJSON do
  @moduledoc "Mission projection response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate mission_event(organization_id, value), to: LegacyJSON
  defdelegate mission_health(organization_id, value), to: LegacyJSON
end
