defmodule CadenceWeb.Console.Capabilities do
  @moduledoc """
  The console's capability vocabulary for a scope, composed from each owning
  context's enforcing policy (DECISIONS #38): never a role table.

  - `command.request`, `command.approve`: commanding's review policy
    (`Cadence.Management.Commanding.capabilities/1`, the check
    `ReviewAccess.authorize/2` enforces).
  - `command.abort`: `GroupAbort.capabilities/1`, any mission operator (DECISIONS #42).
  - `org.invite`, `org.manage_members`: `OrganizationPeople.permissions/2`.
  - `dashboard.author`: `Cadence.Dashboards.Capabilities.list/1` (Policy `:author_dashboards`).

  The session's per-organization list also keeps the scope capabilities
  (`organization_admin`, `platform_admin`) it has always reported.
  """

  alias Cadence.Administration.OrganizationPeople
  alias Cadence.Auth.Scope
  alias Cadence.Control.Commanding.GroupAbort
  alias Cadence.Dashboards.Capabilities, as: DashboardCapabilities
  alias Cadence.Management.Commanding

  @doc "Capabilities other contexts evaluate, for People members (`OrganizationPeople.load/3`)."
  @spec contributed(Scope.t()) :: [binary()]
  def contributed(%Scope{} = scope),
    do: Commanding.capabilities(scope) ++ GroupAbort.capabilities(scope)

  @doc "Everything `scope` holds in its organization, for the session."
  @spec organization(Scope.t()) :: [binary()]
  def organization(%Scope{organization_id: nil} = scope), do: scope_capabilities(scope)

  def organization(%Scope{organization_id: organization_id} = scope) do
    scope_capabilities(scope) ++
      contributed(scope) ++
      OrganizationPeople.permissions(scope, organization_id) ++
      DashboardCapabilities.list(scope)
  end

  defp scope_capabilities(scope),
    do: scope.capabilities |> Enum.map(&Atom.to_string/1) |> Enum.sort()
end
