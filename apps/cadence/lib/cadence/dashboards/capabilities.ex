defmodule Cadence.Dashboards.Capabilities do
  @moduledoc """
  Dashboard capabilities a scope holds in its organization, for the console session
  (DECISIONS #38: derived from the enforcing policy, never a role table).

  - `dashboard.author`: `Policy.authorize(scope, :author_dashboards, …)` passes for at least one
    of the organization's missions (or the scope's own mission). Authoring routes still enforce
    it per mission.
  """

  alias Cadence.Auth.{Policy, Scope}

  @spec list(Scope.t()) :: [binary()]
  def list(%Scope{actor_kind: :user, organization_id: org} = scope) when is_binary(org) do
    missions =
      case scope.mission_id do
        nil -> org |> Cadence.Missions.list_missions() |> Enum.map(& &1.mission_id)
        mission_id -> [mission_id]
      end

    # todo(authz): Cedar should decide dashboard authoring per mission (any mission operator
    # today, Policy :author_dashboards).
    author? =
      Enum.any?(
        missions,
        &(Policy.authorize(scope, :author_dashboards, %{organization_id: org, mission_id: &1}) ==
            :ok)
      )

    if author?, do: ["dashboard.author"], else: []
  end

  def list(%Scope{}), do: []
end
