defmodule Cadence.Applications.OrganizationAdminProviders.ProviderAccountShow do
  @moduledoc false
  defdelegate props(scope, account_id), to: Cadence.Reads.Comms.ProviderAccountDetail, as: :load
end
