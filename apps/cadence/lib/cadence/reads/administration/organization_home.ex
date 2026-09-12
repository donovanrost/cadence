defmodule Cadence.Reads.Administration.OrganizationHome do
  @moduledoc "Authorized organization home facts; presentation belongs to the host feature."

  alias Cadence.{Accounts, Missions, Organizations, SpacecraftStore}
  alias Cadence.Auth.{Policy, Scope}

  def load(%Scope{} = scope) do
    with :ok <-
           Policy.authorize(scope, :operate_organization, %{
             organization_id: scope.organization_id
           }),
         {:ok, organization} <- Organizations.fetch_organization(scope.organization_id) do
      summary = Missions.organization_summary(scope.organization_id)

      {:ok,
       %{
         "version" => 1,
         "organization" => %{
           "id" => organization.organization_id,
           "name" => organization.display_name,
           "slug" => organization.slug
         },
         "counts" => %{
           "missions" => summary.total_count,
           "spacecraft" => SpacecraftStore.count_organization_spacecraft(scope.organization_id),
           "active_memberships" => Accounts.count_organization_members(scope.organization_id)
         },
         "recent_missions" =>
           Enum.map(summary.recent, fn mission ->
             %{
               "id" => mission.mission_id,
               "name" => mission.display_name,
               "slug" => mission.slug,
               "created_at" => DateTime.to_iso8601(mission.created_at)
             }
           end)
       }}
    end
  end

  def load(_), do: {:error, :unavailable}
end
