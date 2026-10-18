defmodule Cadence.CommandReviewFixtures do
  @moduledoc false
  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.Ids
  alias Cadence.Missions
  alias Cadence.Missions.Mission
  alias Cadence.Organizations
  alias Cadence.Organizations.Organization
  alias Cadence.Repo

  def scope! do
    id = Ids.new("review")

    {:ok, org} =
      Organizations.persist_organization(
        Organization.new(%{organization_id: id, slug: id, display_name: "Command review"})
      )

    {:ok, mission} =
      Missions.persist_mission(
        Mission.new(%{
          mission_id: id,
          organization_id: id,
          slug: id,
          display_name: "Review mission"
        })
      )

    user = User.new(%{user_id: id, email: "#{id}@example.test", display_name: "Reviewer"})
    Repo.insert!(UserRow.changeset(user))

    member =
      OrganizationMembership.new(%{user_id: id, organization_id: id, role: :organization_admin})

    Repo.insert!(OrganizationMembershipRow.changeset(member))

    scope =
      Scope.new(%{
        user: user,
        organization_id: id,
        organization: org,
        organization_membership: member
      })

    %{org: id, mission: mission.mission_id, user: user, member: member, scope: scope}
  end

  def request!(c, attrs \\ %{}) do
    request =
      CommandRequest.new(
        Map.merge(
          %{
            command_request_id: Ids.new("command_request"),
            organization_id: c.org,
            mission_id: c.mission,
            source_endpoint_ref: "endpoint_review",
            mission_model_revision_id: "model_review",
            command_id: "command_review",
            command_name: "Set_power",
            command_display_name: "Set power",
            lifecycle_state: :approval_pending,
            requested_by: %{
              "actor_kind" => "user",
              "user_id" => "requester",
              "secret" => "private-actor"
            },
            argument_values: %{"amount" => 3},
            resolved_argument_values: %{"amount" => 3, "channel" => "primary"},
            critical: true,
            significance: :critical,
            requested_at: ~U[2026-09-10 08:00:00.123456Z],
            metadata: %{"internal" => "private-metadata"}
          },
          attrs
        )
      )

    request |> CommandRequestRow.changeset() |> Repo.insert!() |> CommandRequestRow.to_domain()
  end
end
