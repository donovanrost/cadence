defmodule Cadence.Reads.EventLogContextNamesTest do
  @moduledoc """
  #472 (#462, #146 rule C1): the Timeline names a person only while they hold an active
  membership in the mission's organization, checked at read time. No email, ever.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.MissionEvents.Entry
  alias Cadence.Reads.EventLog.Context

  @org "org-472-log"
  @mission "mission-472-log"

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope("org-472-log-other", "mission-472-log-other")
    person!("log-member", "Mira K.", @org)
    person!("log-nameless", "Placeholder", @org)
    {1, _} = Repo.update_all(where(UserRow, user_id: "log-nameless"), set: [display_name: ""])
    person!("log-left", "Lee Left", @org, :revoked)
    person!("log-admin", "Pat Platform", "org-472-log-other", :active, [:platform_admin])
    :ok
  end

  test "(a) a member is named; (b) no display name, (c) a non-member or one who left: nothing" do
    entries =
      for id <- ~w(log-member log-nameless log-left log-admin),
          do: struct(Entry, actor: %{"value" => %{"kind" => "user", "id" => id}})

    %{users: users} = Context.load(@org, @mission, entries)

    assert users == %{"log-member" => "Mira K."}
    refute Enum.any?(Map.values(users), &(&1 =~ "@"))
  end

  defp person!(id, name, organization_id, state \\ :active, capabilities \\ []) do
    Repo.insert!(
      UserRow.changeset(
        User.new(%{
          user_id: id,
          email: "#{id}@example.test",
          display_name: name,
          capabilities: capabilities
        })
      )
    )

    Repo.insert!(
      OrganizationMembershipRow.changeset(
        OrganizationMembership.new(%{
          user_id: id,
          organization_id: organization_id,
          role: :member,
          lifecycle_state: state
        })
      )
    )
  end
end
