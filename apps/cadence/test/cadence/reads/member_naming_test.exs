defmodule Cadence.Reads.MemberNamingTest do
  @moduledoc """
  #469 (#146): Displays & Alarms name a person only while they hold an active membership in the
  organization being read, checked at read time, and never by email or id. Every dashboards read
  names people through `Reads.Dashboards.Authors.names/2`; alarm episodes through
  `Reads.AlarmEpisodes.People.put/2`. Each case: (a) a member with a name, (b) a member without
  one (keeps their id, #471), (c) someone who left, and a platform admin from another organization
  (neither id nor name, ca-security).
  """
  use Cadence.DataCase, async: true

  alias Cadence.Accounts.{OrganizationMembership, OrganizationMembershipRow, User, UserRow}
  alias Cadence.Reads.AlarmEpisodes.People
  alias Cadence.Reads.Dashboards.Authors

  setup do
    org = "naming-org-#{System.unique_integer([:positive])}"
    other = org <> "-other"
    persist_mission_scope(org, org <> "-mission")
    persist_mission_scope(other, other <> "-mission")

    %{
      org: org,
      named: person!(org, "Ada Member"),
      nameless: person!(org, ""),
      left: person!(org, "Cy Left", :revoked),
      support: person!(other, "Pat Support")
    }
  end

  test "dashboards: a member keeps their id, named when they have a name; anyone else neither",
       c do
    ids = [c.named, c.nameless, c.left, c.support, nil, c.named]
    members = Authors.members(c.org, ids)

    assert Enum.map([c.named, c.nameless, c.left, c.support, nil], &Authors.person(members, &1)) ==
             [
               %{id: c.named, name: "Ada Member"},
               %{id: c.nameless, name: nil},
               %{id: nil, name: nil},
               %{id: nil, name: nil},
               nil
             ]

    # A name alone (the directory row) only for a member that has one.
    assert Authors.names(c.org, ids) == %{c.named => "Ada Member"}
    refute inspect(members) =~ "@"
  end

  test "alarm episodes: people are named again now; a service and the system keep theirs", c do
    episode = %{
      assignee: %{id: c.named, name: "stored name"},
      acknowledged_by: %{kind: "user", id: c.left, name: "Cy Left (stored)"},
      events: [
        %{actor: %{kind: "user", id: c.nameless, name: "nameless@example.test"}},
        %{actor: %{kind: "user", id: c.support, name: "Pat Support"}},
        %{actor: %{kind: "service", id: "service-1", name: "Nightly planner"}},
        %{actor: %{kind: "system", id: nil, name: "Cadence"}},
        %{actor: nil}
      ]
    }

    assert [named] = People.put(c.org, [episode])

    assert named.assignee == %{id: c.named, name: "Ada Member"}
    assert named.acknowledged_by == %{kind: "user", id: nil, name: nil}

    assert Enum.map(named.events, & &1.actor) == [
             %{kind: "user", id: c.nameless, name: nil},
             %{kind: "user", id: nil, name: nil},
             %{kind: "service", id: "service-1", name: "Nightly planner"},
             %{kind: "system", id: nil, name: "Cadence"},
             nil
           ]

    refute inspect(named) =~ "@"
  end

  defp person!(organization_id, display_name, state \\ :active) do
    id = "naming-user-#{System.unique_integer([:positive])}"

    user =
      User.new(%{
        user_id: id,
        email: id <> "@example.test",
        display_name: if(display_name == "", do: "x", else: display_name)
      })

    Repo.insert!(UserRow.changeset(user))

    # (b) A member with no display name: an older row or a blanked one (the changeset requires
    # one), set directly.
    if display_name == "",
      do: Repo.update_all(from(u in UserRow, where: u.user_id == ^id), set: [display_name: ""])

    membership =
      OrganizationMembership.new(%{
        user_id: id,
        organization_id: organization_id,
        role: :member,
        lifecycle_state: state
      })

    Repo.insert!(OrganizationMembershipRow.changeset(membership))
    id
  end
end
