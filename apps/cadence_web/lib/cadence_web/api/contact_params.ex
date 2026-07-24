defmodule CadenceWeb.API.ContactParams do
  @moduledoc "Contact lifecycle request parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate scheduled_contact(organization_id, mission_id, params), to: LegacyParams
  defdelegate realization(params), to: LegacyParams
  defdelegate contact_action(params), to: LegacyParams
end
