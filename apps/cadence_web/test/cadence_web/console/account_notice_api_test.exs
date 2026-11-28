defmodule CadenceWeb.Console.AccountNoticeAPITest do
  @moduledoc "#709: a signed-in person's own notices (the legacy bell's), and Mark read by id."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts
  alias CadenceWeb.TestFixtures

  setup do
    [org_a, org_b] = for _ <- 1..2, do: TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")

    for org <- [org_a, org_b],
        do: TestFixtures.grant_membership!(admin, org, role: :organization_admin)

    person = TestFixtures.persist_user!(display_name: "Oli")
    stranger = TestFixtures.persist_user!(display_name: "Sam")

    # The real path: an admin adds someone who already has an account.
    add = fn org, role ->
      {:ok, %{mode: :granted}} =
        Accounts.establish_organization_access(person.email, org.organization_id,
          membership_role: role,
          invited_by_user_id: admin.user_id
        )
    end

    add.(org_a, :member)
    add.(org_b, :organization_admin)

    %{org_a: org_a, org_b: org_b, person: person, stranger: stranger}
  end

  defp as(user), do: TestFixtures.member_conn(user)
  defp mine(user, query \\ ""), do: user |> as() |> get("/api/v1/account/notices#{query}")
  defp read(user, id), do: user |> as() |> post("/api/v1/account/notices/#{id}/read")

  defp count(user),
    do: json_response(get(as(user), "/api/v1/session"), 200)["data"]["unread_notices_count"]

  test "lists my notices newest first, and the session counts the same rows", c do
    body = json_response(mine(c.person), 200)
    assert %{"notices" => [newest, oldest]} = body["data"]
    assert body["meta"] == %{"next_cursor" => nil}

    assert %{
             "id" => "notif" <> _,
             "kind" => "organization_access_granted",
             "organization" => %{"id" => org_b_id, "name" => _},
             "role" => "organization_admin",
             "created_at" => _,
             "read_at" => nil
           } = newest

    assert org_b_id == c.org_b.organization_id
    assert oldest["organization"]["id"] == c.org_a.organization_id
    assert oldest["role"] == "member"
    # Words come from kind and facts; the stored title and body aren't sent.
    refute Map.has_key?(newest, "title") or Map.has_key?(newest, "body")
    assert count(c.person) == 2

    assert %{"notices" => []} = json_response(mine(c.stranger), 200)["data"]
    assert count(c.stranger) == 0
  end

  test "pages with a cursor, and refuses a malformed one", c do
    first = json_response(mine(c.person, "?limit=1"), 200)
    assert [_] = first["data"]["notices"]
    cursor = first["meta"]["next_cursor"]
    assert is_binary(cursor)

    second = json_response(mine(c.person, "?limit=1&cursor=#{cursor}"), 200)
    assert [_] = second["data"]["notices"]
    assert second["meta"]["next_cursor"] == nil
    refute hd(first["data"]["notices"])["id"] == hd(second["data"]["notices"])["id"]

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"cursor" => _}}} =
             json_response(mine(c.person, "?cursor=nope"), 422)
  end

  test "Mark read: mine only, idempotent, and the count follows", c do
    [notice | _] = json_response(mine(c.person), 200)["data"]["notices"]

    assert %{"error" => %{"code" => "notice_not_found"}} =
             json_response(read(c.stranger, notice["id"]), 404)

    assert %{"error" => %{"code" => "notice_not_found"}} =
             json_response(read(c.person, "notif_missing"), 404)

    assert %{"id" => id, "read_at" => read_at} =
             json_response(read(c.person, notice["id"]), 200)["data"]

    assert id == notice["id"] and is_binary(read_at)
    assert json_response(read(c.person, notice["id"]), 200)["data"]["read_at"] == read_at
    assert count(c.person) == 1
  end

  test "needs a signed-in person" do
    assert build_conn() |> get("/api/v1/account/notices") |> json_response(401)
  end
end
