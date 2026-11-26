defmodule CadenceWeb.Console.AccountInvitationAPITest do
  @moduledoc "§11 L21: a signed-in user's own pending invitations, accepted or declined by id."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    [org_a, org_b] = for _ <- 1..2, do: TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")

    for org <- [org_a, org_b],
        do: TestFixtures.grant_membership!(admin, org, role: :organization_admin)

    outsider = TestFixtures.persist_user!(display_name: "Oli")
    stranger = TestFixtures.persist_user!(display_name: "Sam")

    invite = fn org, role ->
      admin
      |> TestFixtures.member_conn()
      |> post("/api/v1/organizations/#{org.organization_id}/invitations", %{
        "email" => outsider.email,
        "role" => role
      })
      |> json_response(201)
      |> get_in(["data", "id"])
    end

    %{
      org_a: org_a,
      org_b: org_b,
      outsider: outsider,
      stranger: stranger,
      a_id: invite.(org_a, "member"),
      b_id: invite.(org_b, "organization_admin")
    }
  end

  defp as(user), do: TestFixtures.member_conn(user)
  defp mine(user), do: user |> as() |> get("/api/v1/account/invitations")

  defp answer(user, id, verb),
    do: user |> as() |> post("/api/v1/account/invitations/#{id}/#{verb}")

  defp count(user),
    do:
      json_response(get(as(user), "/api/v1/session"), 200)["data"][
        "pending_invitations_count"
      ]

  test "lists my pending invitations, oldest first, and the session counts them", c do
    assert %{"invitations" => [first, second]} = json_response(mine(c.outsider), 200)["data"]

    assert %{
             "id" => a_id,
             "organization" => %{"id" => org_a_id, "slug" => _, "name" => _},
             "role" => "member",
             "invited_by" => %{"name" => "Ada Admin"},
             "invited_at" => _,
             "expires_at" => _
           } = first

    assert {a_id, org_a_id} == {c.a_id, c.org_a.organization_id}
    assert second["id"] == c.b_id and second["role"] == "organization_admin"
    assert count(c.outsider) == 2

    # Someone else's invitations aren't listed to me.
    assert %{"invitations" => []} = json_response(mine(c.stranger), 200)["data"]
    assert count(c.stranger) == 0
  end

  test "accept joins the organization and returns it; decline is final", c do
    assert %{"organization" => %{"id" => org_id, "slug" => slug}, "role" => "member"} =
             json_response(answer(c.outsider, c.a_id, "accept"), 200)["data"]

    assert org_id == c.org_a.organization_id and slug == c.org_a.slug

    assert %{"id" => b_id, "status" => "declined"} =
             json_response(answer(c.outsider, c.b_id, "decline"), 200)["data"]

    assert b_id == c.b_id
    assert %{"invitations" => []} = json_response(mine(c.outsider), 200)["data"]
    assert count(c.outsider) == 0

    # Answered already: 409 with what happened.
    assert %{"code" => "invitation_not_pending", "details" => %{"status" => "accepted"}} =
             json_response(answer(c.outsider, c.a_id, "decline"), 409)["error"]

    assert %{"code" => "invitation_not_pending", "details" => %{"status" => "declined"}} =
             json_response(answer(c.outsider, c.b_id, "accept"), 409)["error"]
  end

  test "an unknown id, or one addressed to someone else, is the same 404", c do
    for {user, id} <- [{c.outsider, "organization_invitation-nope"}, {c.stranger, c.a_id}],
        verb <- ["accept", "decline"] do
      assert %{"code" => "invitation_not_found"} =
               json_response(answer(user, id, verb), 404)["error"]
    end

    # Still pending for its real recipient.
    assert count(c.outsider) == 2
  end
end
