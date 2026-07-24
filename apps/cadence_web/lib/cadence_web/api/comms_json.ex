defmodule CadenceWeb.API.CommsJSON do
  @moduledoc "Spacecraft and communications response serialization boundary."

  alias CadenceWeb.ControlPlaneJSON, as: LegacyJSON

  defdelegate source_endpoint(value), to: LegacyJSON
  defdelegate spacecraft(value), to: LegacyJSON
  defdelegate provider_profile(value), to: LegacyJSON
  defdelegate transport_profile(value), to: LegacyJSON
  defdelegate path_template(value), to: LegacyJSON
  defdelegate link_assignment(value), to: LegacyJSON
  defdelegate link_template_application_result(value), to: LegacyJSON
end
