defmodule CadenceWeb.Console.ServiceIdentityAPITest do
  @moduledoc "Service identity create / rotate / revoke (O6): the token is shown once."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth
  alias Cadence.Auth.ServiceAccountability
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Ada Admin")
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    %{
      admin: admin,
      member: member,
      mission: mission,
      base: "/api/console/v1/organizations/#{org.organization_id}/service-identities"
    }
  end

  defp conn(user), do: TestFixtures.member_conn(user)

  defp directory(c),
    do:
      c.admin
      |> conn()
      |> get(c.base)
      |> json_response(200)
      |> get_in(["data", "service_identities"])

  defp listed(c), do: Enum.map(directory(c), & &1["id"])

  defp key_created_at(c, id), do: Enum.find(directory(c), &(&1["id"] == id))["key_created_at"]

  test "create shows the token once; rotate replaces it; revoke ends it", c do
    body = %{
      "name" => "Ops automation",
      "mission_id" => c.mission.mission_id,
      "capabilities" => ["mission_admin"]
    }

    assert c.member |> conn() |> post(c.base, body) |> json_response(403)

    created = c.admin |> conn() |> post(c.base, body)
    assert get_resp_header(created, "cache-control") == ["no-store"]

    assert %{
             "service_identity" => %{"id" => id, "name" => "Ops automation"},
             "api_token" => first
           } =
             json_response(created, 201)["data"]

    assert {:ok, _scope} = Auth.authenticate_api_token(first)
    assert id in listed(c)
    original_key = key_created_at(c, id)
    # Timestamps are ISO strings (qa #37).
    assert {:ok, _at, _offset} = DateTime.from_iso8601(original_key)

    assert %{"api_token" => second} =
             c.admin
             |> conn()
             |> post(c.base <> "/#{id}/rotate", %{})
             |> json_response(200)
             |> Map.fetch!("data")

    refute second == first
    assert {:error, _} = Auth.authenticate_api_token(first)
    assert {:ok, _scope} = Auth.authenticate_api_token(second)
    # The directory dates the key from its rotation.
    refute key_created_at(c, id) == original_key
    assert {:ok, _at, _offset} = DateTime.from_iso8601(key_created_at(c, id))

    assert c.admin |> conn() |> delete(c.base <> "/#{id}") |> response(204)
    assert {:error, _} = Auth.authenticate_api_token(second)
    refute id in listed(c)

    assert %{"error" => %{"code" => "service_identity_not_found"}} =
             c.admin |> conn() |> post(c.base <> "/#{id}/rotate", %{}) |> json_response(404)
  end

  test "names and capabilities are validated", c do
    post = fn body -> c.admin |> conn() |> post(c.base, body) |> json_response(422) end

    assert %{"error" => %{"details" => %{"name" => _}}} =
             post.(%{"name" => "", "capabilities" => ["organization_admin"]})

    assert %{"error" => %{"details" => %{"capabilities" => _}}} =
             post.(%{"name" => "x", "capabilities" => ["root"]})

    assert %{"error" => %{"details" => %{"mission_id" => _}}} =
             post.(%{"name" => "x", "capabilities" => ["mission_admin"]})

    assert %{"error" => %{"details" => %{"mission_id" => _}}} =
             post.(%{"name" => "x", "capabilities" => ["mission_admin"], "mission_id" => "nope"})
  end

  # #280: the people accountable for an identity are recorded by the server.
  test "create and rotate record who did them; an org admin records accountable people", c do
    org_id = c.mission.organization_id
    second_admin = TestFixtures.persist_user!(display_name: "Bo Admin")
    {:ok, org} = Cadence.Organizations.fetch_organization(org_id)
    TestFixtures.grant_membership!(second_admin, org, role: :organization_admin)

    body = %{
      "name" => "Pipeline",
      "mission_id" => c.mission.mission_id,
      "capabilities" => ["mission_admin"]
    }

    %{"service_identity" => %{"id" => id}} =
      c.admin |> conn() |> post(c.base, body) |> json_response(201) |> Map.fetch!("data")

    assert {:ok, [admin_id]} = ServiceAccountability.people(org_id, id)
    assert admin_id == c.admin.user_id
    # The platform directory's creator is the recorded issuer, never identity metadata.
    assert %{created_by_id: ^admin_id} =
             Cadence.Accounts.PlatformDirectory.service_identity(org_id, id)

    second_admin |> conn() |> post(c.base <> "/#{id}/rotate", %{}) |> json_response(200)
    assert {:ok, people} = ServiceAccountability.people(org_id, id)
    assert Enum.sort(people) == Enum.sort([c.admin.user_id, second_admin.user_id])

    accountable = c.base <> "/#{id}/accountable"

    assert c.member
           |> conn()
           |> post(accountable, %{"user_ids" => [c.member.user_id]})
           |> json_response(403)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c.admin
             |> conn()
             |> post(accountable, %{"user_ids" => ["not-a-member"]})
             |> json_response(422)

    assert c.admin
           |> conn()
           |> post(accountable, %{"user_ids" => [c.member.user_id]})
           |> response(204)

    assert {:ok, people} = ServiceAccountability.people(org_id, id)
    assert c.member.user_id in people and c.admin.user_id in people
  end
end
