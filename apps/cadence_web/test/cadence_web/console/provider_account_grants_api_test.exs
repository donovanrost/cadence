defmodule CadenceWeb.Console.ProviderAccountGrantsAPITest do
  @moduledoc "L13 PA2 detail, mission grants and credential revoke (setup.md §L13)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    {:ok, _credential} =
      ProviderCredentials.create(
        org.organization_id,
        "pa-sim",
        %{
          provider_credential_ref: "cred-simulator-alpha",
          backend_type: :external,
          backend_key: "providers/sim"
        },
        manage_backend?: false
      )

    {:ok, _account, _version} =
      ProviderAccounts.create_for_system(
        org.organization_id,
        %{
          provider_account_id: "pa-sim",
          display_name: "Simulator Account",
          provider_type: :simulator,
          base_url: "http://simulator.test",
          environment_ref: "run-alpha",
          credential_ref: "cred-simulator-alpha",
          guardrails: %{
            "allowed_services" => ["telemetry", "tracking"],
            "allowed_stations" => ["station-alpha", "station-beta"],
            "max_quota" => 100
          }
        },
        %{"kind" => "system", "id" => "test"},
        validate_credential?: false
      )

    %{
      org: org,
      admin: admin,
      member: member,
      mission: mission,
      base: "/api/console/v1/organizations/#{org.organization_id}/provider-accounts/pa-sim"
    }
  end

  defp admin(c), do: TestFixtures.member_conn(c.admin)

  defp grant!(c, body \\ %{}) do
    c
    |> admin()
    |> post(
      c.base <> "/grants",
      Map.merge(
        %{"mission_id" => c.mission.mission_id, "expected_account_version" => 1},
        body
      )
    )
    |> json_response(201)
    |> get_in(["data", "grant"])
  end

  test "PA2 shows the account, masked credential, guardrails and grants; members can't", c do
    grant = grant!(c, %{"allowed_stations" => ["station-alpha"], "reason" => "Flight ops"})

    data = c |> admin() |> get(c.base) |> json_response(200) |> Map.fetch!("data")

    assert %{
             "id" => "pa-sim",
             "version" => 1,
             "status" => "not_checked",
             "credential" => %{"ref" => "…-alpha", "version" => 1, "status" => "active"},
             "guardrails" => %{
               "allowed_services" => ["telemetry", "tracking"],
               "allowed_stations" => ["station-alpha", "station-beta"]
             }
           } = data["account"]

    refute inspect(data) =~ "cred-simulator-alpha"
    assert data["permissions"] == ["provider_accounts.manage"]

    assert [
             %{
               "id" => id,
               "state" => "active",
               "mission" => %{"id" => mission_id},
               "allowed_stations" => ["station-alpha"],
               "allowed_services" => nil,
               "reason" => "Flight ops",
               "granted_by" => %{"name" => _}
             }
           ] = data["grants"]

    assert {id, mission_id} == {grant["id"], c.mission.mission_id}
    assert c.member |> TestFixtures.member_conn() |> get(c.base) |> json_response(403)

    assert c |> admin() |> get(c.base <> "-nope") |> json_response(404)
  end

  test "PA2: a reference with no registered credential reads status missing, version null", c do
    # Accounts can't be created on an unregistered reference; an older account's record can be gone.
    Cadence.Repo.query!(
      "DELETE FROM provider_credentials WHERE provider_credential_ref = 'cred-simulator-alpha'"
    )

    assert %{"credential" => credential} =
             c |> admin() |> get(c.base) |> json_response(200) |> get_in(["data", "account"])

    assert credential == %{"ref" => "…-alpha", "version" => nil, "status" => "missing"}
  end

  test "grant refuses a stale account version, a widening field and a bad mission", c do
    assert %{"error" => %{"code" => "account_changed", "details" => %{"version" => 1}}} =
             c
             |> admin()
             |> post(c.base <> "/grants", %{
               "mission_id" => c.mission.mission_id,
               "expected_account_version" => 7
             })
             |> json_response(409)

    for {field, value} <- [
          {"allowed_stations", ["station-gamma"]},
          {"allowed_services", ["ranging"]},
          {"max_quota", 500}
        ] do
      assert %{"error" => %{"code" => "invalid_params", "details" => %{^field => _}}} =
               c
               |> admin()
               |> post(c.base <> "/grants", %{
                 "mission_id" => c.mission.mission_id,
                 "expected_account_version" => 1,
                 field => value
               })
               |> json_response(422)
    end

    assert %{"error" => %{"details" => %{"mission_id" => _}}} =
             c
             |> admin()
             |> post(c.base <> "/grants", %{
               "mission_id" => "another-orgs-mission",
               "expected_account_version" => 1
             })
             |> json_response(422)
  end

  test "revoke a grant: reason required, stale version, flagged count, already revoked", c do
    grant = grant!(c)
    path = c.base <> "/grants/#{grant["id"]}/revoke"

    assert %{"error" => %{"details" => %{"reason" => "Say why."}}} =
             c
             |> admin()
             |> post(path, %{"expected_grant_version" => 1, "reason" => " "})
             |> json_response(422)

    assert %{"error" => %{"code" => "grant_changed", "details" => %{"version" => 1}}} =
             c
             |> admin()
             |> post(path, %{"expected_grant_version" => 3, "reason" => "Contract ended"})
             |> json_response(409)

    assert %{
             "data" => %{
               "grant" => %{"state" => "revoked", "version" => 2, "revoke_reason" => "Ended"},
               "flagged_reservations" => 0
             }
           } =
             c
             |> admin()
             |> post(path, %{"expected_grant_version" => 1, "reason" => "Ended"})
             |> json_response(200)

    assert %{"error" => %{"code" => "grant_already_revoked"}} =
             c
             |> admin()
             |> post(path, %{"expected_grant_version" => 2, "reason" => "Again"})
             |> json_response(409)

    assert %{"error" => %{"code" => "account_grant_not_found"}} =
             c
             |> admin()
             |> post(c.base <> "/grants/nope/revoke", %{
               "expected_grant_version" => 1,
               "reason" => "x"
             })
             |> json_response(404)
  end

  test "revoke the credential: the account then says credential_revoked; twice is 409", c do
    path = c.base <> "/credential/revoke"

    assert %{"error" => %{"code" => "credential_changed", "details" => %{"version" => 1}}} =
             c
             |> admin()
             |> post(path, %{"expected_credential_version" => 4, "reason" => "Leaked"})
             |> json_response(409)

    assert %{"error" => %{"details" => %{"reason" => _}}} =
             c
             |> admin()
             |> post(path, %{"expected_credential_version" => 1})
             |> json_response(422)

    assert %{"data" => %{"account" => %{"status" => "credential_revoked", "id" => "pa-sim"}}} =
             c
             |> admin()
             |> post(path, %{"expected_credential_version" => 1, "reason" => "Leaked"})
             |> json_response(200)

    assert %{"error" => %{"code" => "credential_already_revoked"}} =
             c
             |> admin()
             |> post(path, %{"expected_credential_version" => 2, "reason" => "Again"})
             |> json_response(409)

    assert %{"data" => %{"account" => %{"credential" => %{"status" => "revoked"}}}} =
             c |> admin() |> get(c.base) |> json_response(200)

    assert c.member
           |> TestFixtures.member_conn()
           |> post(path, %{"expected_credential_version" => 2, "reason" => "x"})
           |> json_response(403)
  end
end
