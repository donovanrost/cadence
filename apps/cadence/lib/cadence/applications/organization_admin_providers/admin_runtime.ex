defmodule Cadence.Applications.OrganizationAdminProviders.AdminRuntime do
  @moduledoc "Compatibility adapter for the historical organization-admin surface."

  defdelegate props(params \\ %{}), to: Cadence.Reads.Dashboards.RuntimeDiagnostics
end
