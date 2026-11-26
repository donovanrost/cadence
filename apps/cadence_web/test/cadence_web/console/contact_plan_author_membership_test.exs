defmodule CadenceWeb.Console.ContactPlanAuthorMembershipTest do
  @moduledoc """
  #468 D (#146; security checklist 12): a contact plan's `author` is named through ActorRef, by
  current membership in the plan's organization. An active member keeps their id and is named by
  display name (nil without one). Anyone else (a platform admin from another organization, a
  removed member) reads id and name nil, and their email or name is never sent.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Management.Contacts.Store.{ContactPlanRow, ContactPlanVersionRow}
  alias Cadence.Repo
  alias CadenceWeb.{ContactPlanningFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    other_org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    named = TestFixtures.persist_user!(display_name: "Nadia")
    named_membership = TestFixtures.grant_membership!(named, org, role: :member)

    nameless = TestFixtures.persist_user!(display_name: "Nameless")
    TestFixtures.grant_membership!(nameless, org, role: :member)
    nameless_id = nameless.user_id
    Repo.update_all(from(u in UserRow, where: u.user_id == ^nameless_id), set: [display_name: ""])

    # A platform admin from another organization (in admin mode they'd act in this one).
    outsider = TestFixtures.persist_user!(display_name: "Pat")
    TestFixtures.grant_membership!(outsider, other_org, role: :organization_admin)

    departed = TestFixtures.persist_user!(display_name: "Dee")
    TestFixtures.grant_membership!(departed, org, role: :member)
    org_id = org.organization_id
    departed_id = departed.user_id

    Repo.update_all(
      from(m in OrganizationMembershipRow,
        where: m.organization_id == ^org_id and m.user_id == ^departed_id
      ),
      set: [lifecycle_state: "revoked"]
    )

    plan_id =
      ContactPlanningFixtures.plan_fixture(org, named, named_membership, mission).plan.contact_plan_id

    %{
      org_id: org_id,
      plan_id: plan_id,
      named: named,
      people: %{nameless: nameless, outsider: outsider, departed: departed},
      emails: Enum.map([named, nameless, outsider, departed], & &1.email),
      base: "/api/console/v1/missions/#{mission.mission_id}/contact-plans"
    }
  end

  # The plan as if `user_id` had made it (both the plan and its versions).
  defp authored_by!(c, user_id) do
    for schema <- [ContactPlanRow, ContactPlanVersionRow] do
      Repo.update_all(
        from(r in schema,
          where: r.organization_id == ^c.org_id and r.contact_plan_id == ^c.plan_id
        ),
        set: [created_by: user_id]
      )
    end
  end

  defp author(c) do
    detail =
      c.named |> TestFixtures.member_conn() |> get("#{c.base}/#{c.plan_id}") |> response(200)

    list = c.named |> TestFixtures.member_conn() |> get(c.base) |> response(200)
    for e <- c.emails, do: refute(detail =~ e or list =~ e)

    [row] =
      Jason.decode!(list)["data"]["plans"] |> Enum.filter(&(&1["id"] == c.plan_id))

    author = Jason.decode!(detail)["data"]["author"]
    # The list and the detail agree (one lookup each).
    assert row["author"] == author
    author
  end

  test "a member author is named and keeps their id", c do
    named_id = c.named.user_id
    assert %{"kind" => "user", "id" => ^named_id, "name" => "Nadia"} = author(c)
  end

  test "a nameless member keeps their id with a null name", c do
    authored_by!(c, c.people.nameless.user_id)
    nameless_id = c.people.nameless.user_id
    assert %{"kind" => "user", "id" => ^nameless_id, "name" => nil} = author(c)
  end

  test "a platform admin from another organization, or a removed member, reads unnamed", c do
    for person <- [c.people.outsider, c.people.departed] do
      authored_by!(c, person.user_id)
      assert %{"kind" => "user", "id" => nil, "name" => nil} = author(c)
      refute inspect(author(c)) =~ person.display_name
    end
  end

  test "Cadence's own run still reads as Cadence", c do
    authored_by!(c, "cadence-planner")
    assert %{"kind" => "system", "name" => "Cadence"} = author(c)
  end
end
