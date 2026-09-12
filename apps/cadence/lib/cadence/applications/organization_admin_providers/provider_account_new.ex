defmodule Cadence.Applications.OrganizationAdminProviders.ProviderAccountNew do
  @moduledoc false
  defdelegate props(), to: Cadence.GroundNetworks.ProviderAccountRegistration
  defdelegate form(params), to: Cadence.GroundNetworks.ProviderAccountRegistration
  defdelegate create(scope, params), to: Cadence.GroundNetworks.ProviderAccountRegistration
end
