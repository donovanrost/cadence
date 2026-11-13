defmodule CadenceWeb.Console.OrganizationMissionAPITest do
  @moduledoc "§11 L4: console mission create (slug check and create) in the path's organization."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada")
    member = TestFixtures.persist_user!(display_name: "Mia")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    existing = TestFixtures.persist_mission!(org)

    %{
      admin: admin,
      member: member,
      existing: existing,
      base: "/api/console/v1/organizations/#{org.organization_id}/missions"
    }
  end

  defp get_json(user, path), do: user |> TestFixtures.member_conn() |> get(path)
  defp post_json(user, path, body), do: user |> TestFixtures.member_conn() |> post(path, body)

  test "an org admin checks a slug and creates a mission; a clash suggests a free slug", c do
    taken = c.existing.slug

    assert %{"slug" => "earendil", "available" => true, "suggestion" => nil} =
             json_response(get_json(c.admin, c.base <> "/slug?slug=earendil"), 200)["data"]

    assert %{"available" => false, "suggestion" => suggestion} =
             json_response(get_json(c.admin, c.base <> "/slug?slug=#{taken}"), 200)["data"]

    assert suggestion == "#{taken}-2"

    assert %{"mission" => %{"id" => _, "name" => "Earendil", "slug" => "earendil"}} =
             json_response(
               post_json(c.admin, c.base, %{"name" => "Earendil", "slug" => "earendil"}),
               201
             )["data"]

    clash = post_json(c.admin, c.base, %{"name" => "Again", "slug" => "earendil"})

    assert %{"slug" => _, "suggestion" => "earendil-2"} =
             json_response(clash, 422)["error"]["details"]

    bad = post_json(c.admin, c.base, %{"name" => " ", "slug" => "Not A Slug"})
    assert %{"name" => _, "slug" => _} = json_response(bad, 422)["error"]["details"]
  end

  test "members can't create missions", c do
    assert json_response(post_json(c.member, c.base, %{"name" => "X", "slug" => "x"}), 403)
    assert json_response(get_json(c.member, c.base <> "/slug?slug=x"), 403)
  end
end
