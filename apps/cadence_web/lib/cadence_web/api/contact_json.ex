defmodule CadenceWeb.API.ContactJSON do
  @moduledoc "Contact lifecycle response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate scheduled_contact(value), to: LegacyJSON
  defdelegate realized_contact(value), to: LegacyJSON
  defdelegate realized_contact_runtime_snapshot(value), to: LegacyJSON
  defdelegate path_runtime_snapshot(value), to: LegacyJSON
  defdelegate contact_action(value), to: LegacyJSON
end
