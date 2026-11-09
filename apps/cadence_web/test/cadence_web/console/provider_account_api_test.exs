defmodule CadenceWeb.Console.ProviderAccountAPITest do
  @moduledoc "PA1 provider accounts (read and test)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias CadenceWeb.TestFixtures

  test "lists accounts with status and permissions; members can't read" do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    {:ok, _credential} =
      ProviderCredentials.create(
        org.organization_id,
        "pa-sim",
        %{
          provider_credential_ref: "cred-sim",
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
          credential_ref: "cred-sim"
        },
        %{"kind" => "system", "id" => "test"},
        validate_credential?: false
      )

    base = "/api/console/v1/organizations/#{org.organization_id}/provider-accounts"

    data =
      admin |> TestFixtures.member_conn() |> get(base) |> json_response(200) |> Map.fetch!("data")

    assert [
             %{
               "id" => "pa-sim",
               "name" => "Simulator Account",
               "provider" => %{"key" => "simulator"},
               "status" => "not_checked",
               "missions" => [],
               "expires_at" => nil
             }
           ] = data["accounts"]

    assert data["permissions"] == ["provider_accounts.manage"]
    assert Enum.any?(data["adapters"], &(&1["key"] == "simulator"))

    assert member |> TestFixtures.member_conn() |> get(base) |> json_response(403)

    missing = admin |> TestFixtures.member_conn() |> post(base <> "/nope/test", %{})
    assert json_response(missing, 404)["error"]["code"] == "provider_account_not_found"
  end
end
