defmodule Cadence.CommandGroupFixtures do
  @moduledoc false

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.CommandAuthoringFixtures
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.CommandReviewFixtures
  alias Cadence.ExactCommandAuthoringFixtures
  alias Cadence.Ids
  alias Cadence.Repo

  @doc "A mission with the exact-authoring catalog active and `count` commandable spacecraft."
  def setup!(count \\ 2) do
    c = CommandReviewFixtures.scope!()
    model = ExactCommandAuthoringFixtures.activate!(c.org, c.mission)

    spacecraft =
      for i <- 1..count do
        id = "sc-#{i}"

        {:ok, _} =
          Cadence.SpacecraftStore.persist_spacecraft(
            c.org,
            Cadence.Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: c.org,
              mission_id: c.mission,
              display_name: "SC-#{i}"
            })
          )

        CommandAuthoringFixtures.target!(c.org, c.mission, %{
          source_endpoint_id: Cadence.SourceEndpoints.managed_source_endpoint_id(id),
          spacecraft_id: id,
          display_name: "SC-#{i}"
        })

        id
      end

    Map.merge(c, %{ids: model.commands_by_name, spacecraft: spacecraft})
  end

  def command(c, name, args), do: %{command_id: c.ids[name], argument_values: args}

  def draft(spacecraft_ids, commands, extra \\ %{}) do
    Map.merge(
      %{
        title: "Load shed",
        # The operator's explicit endpoint (an audited override); route-based resolution is
        # covered by Cadence.Comms.UplinkResolutionTest.
        targets:
          Enum.map(
            spacecraft_ids,
            &%{
              spacecraft_id: &1,
              source_endpoint_id: Cadence.SourceEndpoints.managed_source_endpoint_id(&1)
            }
          ),
        commands: commands,
        priority: 3
      },
      extra
    )
  end

  def actor(c), do: %{"actor_kind" => "user", "user_id" => c.scope.user.user_id}

  @doc "The digest a preflight would have shown for `draft`."
  def digest(c, draft) do
    {:ok, validated} = Validation.validate(c.org, c.mission, actor(c), draft)
    validated.digest
  end

  @doc "Another operator (a member of the same organization) with their own scope."
  def operator!(c, name \\ "Second Operator") do
    id = Ids.new("operator")
    user = User.new(%{user_id: id, email: "#{id}@example.test", display_name: name})
    Repo.insert!(UserRow.changeset(user))

    member =
      OrganizationMembership.new(%{
        user_id: id,
        organization_id: c.org,
        role: :organization_admin
      })

    Repo.insert!(OrganizationMembershipRow.changeset(member))
    {:ok, org} = Cadence.Organizations.fetch_organization(c.org)

    Scope.new(%{
      user: user,
      organization_id: c.org,
      organization: org,
      organization_membership: member
    })
  end
end
