defmodule CadenceWeb.MissionProviderPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{
    MissionProviderRegistration,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Management.Providers
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    account = "mission-provider-account-#{System.unique_integer([:positive])}"
    credential = account <> "-credential"

    {:ok, _} =
      ProviderCredentials.create(
        org.organization_id,
        account,
        %{
          provider_credential_ref: credential,
          backend_type: :external,
          backend_key: "fixture/no-live-credential",
          registered_at: ~U[2026-09-07 10:00:00.000000Z]
        },
        manage_backend?: false
      )

    {:ok, _, _} =
      ProviderAccounts.create(
        scope,
        %{
          provider_account_id: account,
          credential_ref: credential,
          provider_type: :simulator,
          display_name: "Host mission provider",
          base_url: "https://provider.invalid",
          environment_ref: "fixture",
          guardrails: %{}
        },
        validate_credential?: false
      )

    {:ok, grant} =
      ProviderAccountGrants.grant(scope, mission.mission_id, account, %{
        restrictions: %{},
        grant_reason: "Fixture"
      })

    params = %{
      "display_name" => "Mission network",
      "provider_account_id" => account,
      "provider_account_version" => to_string(grant.provider_account_version),
      "provider_account_grant_id" => grant.provider_account_grant_id,
      "provider_account_grant_version" => to_string(grant.version),
      "policy_mode" => "approval_required",
      "deadline_behavior" => "retain_last_accepted"
    }

    %{
      conn: TestFixtures.member_conn(user),
      org: org,
      scope: scope,
      mission: mission,
      grant: grant,
      params: params,
      path: "/missions/#{mission.mission_id}/comms/providers"
    }
  end

  test "directory and creation load without a release, and creation is consumed across refresh",
       c do
    {:ok, view, _} = live(c.conn, c.path)
    assert page(view)["id"] == "comms.provider-list"
    assert page(view)["status"] == "ready"
    path = c.path <> "/new?provider_account_grant_id=#{c.grant.provider_account_grant_id}"
    refresh(view, path)
    original = page(view)

    assert original["data"]["model"]["data"]["form"]["fields"]["provider_account_grant_id"][
             "value"
           ] == c.grant.provider_account_grant_id

    input = %{"sequence" => 1, "provider" => c.params}
    refresh(view, path)
    assert page(view) == original
    result = action(view, path, original, "create-provider", input)
    assert result["snapshot"]["status"] == "ok"
    assert result["snapshot"]["sequence"] == 1
    assert length(Providers.list_providers(c.org.organization_id, c.mission.mission_id)) == 1

    assert action(view, path, original, "create-provider", input)["snapshot"]["status"] ==
             "rejected"

    refresh(view, path)
    assert page(view)["data"]["phase"] == "completed"
    assert page(view)["token"] == original["token"]
  end

  test "creation rejects forged bindings, bad payloads and invalidated page identities without effects",
       c do
    path = c.path <> "/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    for params <- [
          Map.delete(c.params, "provider_account_version"),
          Map.put(c.params, "provider_account_version", "99"),
          Map.put(c.params, "provider_account_id", "foreign"),
          Map.put(c.params, "display_name", %{})
        ] do
      assert action(view, path, original, "create-provider", %{
               "sequence" => 1,
               "provider" => params
             })["snapshot"]["status"] == "rejected"
    end

    for input <- [
          nil,
          [],
          %{"sequence" => 1.0, "provider" => c.params},
          %{"sequence" => 2, "provider" => c.params}
        ] do
      assert action(view, path, original, "create-provider", input)["snapshot"]["status"] ==
               "rejected"
    end

    refresh(view, c.path)

    refute action(view, path, original, "create-provider", %{
             "sequence" => 1,
             "provider" => c.params
           })["ok"]

    refresh(view, path)
    refute page(view)["token"] == original["token"]
    assert Providers.list_providers(c.org.organization_id, c.mission.mission_id) == []
  end

  test "detail binds path and observed version before archive, then rejects replay", c do
    {:ok, provider} = MissionProviderRegistration.create(c.scope, c.mission.mission_id, c.params)
    path = c.path <> "/#{provider.provider_id}?provider_id=foreign&mission_id=foreign"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["context"]["resourceId"] == provider.provider_id

    input = %{
      "provider_id" => provider.provider_id,
      "expected_provider_version" => provider.version,
      "sequence" => 1
    }

    for invalid <- [
          Map.put(input, "provider_id", "foreign"),
          Map.put(input, "expected_provider_version", 99)
        ] do
      assert action(view, path, original, "archive-provider", invalid)["snapshot"]["status"] ==
               "rejected"
    end

    assert action(view, path, original, "archive-provider", input)["snapshot"]["status"] == "ok"

    assert action(view, path, original, "archive-provider", input)["snapshot"]["status"] ==
             "rejected"

    assert Providers.list_providers(c.org.organization_id, c.mission.mission_id) == []
  end

  test "uncertain control outcome stays locked while read-only refresh remains available", c do
    {:ok, provider} = MissionProviderRegistration.create(c.scope, c.mission.mission_id, c.params)
    path = c.path <> "/#{provider.provider_id}"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    # Revocation stops admission before the external provider client is resolved.
    {:ok, _} =
      Cadence.Control.Providers.revoke_account_grant(
        c.scope,
        c.grant.provider_account_grant_id,
        "Fixture revoked"
      )

    input = %{
      "provider_id" => provider.provider_id,
      "expected_provider_version" => provider.version,
      "sequence" => 1
    }

    assert action(view, path, original, "validate-provider", input)["snapshot"]["status"] ==
             "unknown"

    read = action(view, path, original, "refresh", %{})
    assert read["snapshot"]["status"] == "ok"
    assert read["snapshot"]["data"]["phase"] == "submitted"
    refresh(view, path)
    assert page(view)["data"]["phase"] == "submitted"
    assert page(view)["token"] == original["token"]

    assert action(view, path, original, "archive-provider", Map.put(input, "sequence", 2))[
             "snapshot"
           ]["status"] == "rejected"

    assert {:ok, _} =
             Providers.fetch_provider(
               c.org.organization_id,
               c.mission.mission_id,
               provider.provider_id
             )
  end

  test "revoked authenticated session cannot execute a previously admitted form", c do
    path = c.path <> "/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:mission-page", %{
      "path" => path,
      "id" => original["id"],
      "token" => original["token"],
      "event" => "create-provider",
      "input" => %{"sequence" => 1, "provider" => c.params}
    })

    assert_redirect(view, "/sign-in")
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["mission_module_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:mission-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
