defmodule Cadence.Applications.OrganizationAdminProviders.ProviderAccountList do
  @moduledoc false
  defdelegate props(scope), to: Cadence.Reads.Comms.ProviderAccountDirectory, as: :load
end
