defmodule CadenceWeb.ProviderAccountDetailPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}
  alias Cadence.Reads.Comms.ProviderAccountDetail
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    account_id = "host-detail-#{System.unique_integer([:positive])}"
    credential_ref = account_id <> "-credential"

    assert {:ok, _} =
             ProviderCredentials.create(
               scope.organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "fixture/host-detail",
                 registered_at: ~U[2026-09-07 10:00:00.000000Z]
               },
               manage_backend?: false
             )

    assert {:ok, _, _} =
             ProviderAccounts.create(
               scope,
               %{
                 provider_account_id: account_id,
                 credential_ref: credential_ref,
                 provider_type: :simulator,
                 display_name: "Host Detail",
                 base_url: "https://provider.example.test",
                 environment_ref: "test",
                 guardrails: %{"max_quota" => 10}
               },
               validate_credential?: false
             )

    previous = Application.fetch_env(:cadence_web, :provider_account_live_opts)
    Application.put_env(:cadence_web, :provider_account_live_opts, manage_backend?: false)

    on_exit(fn ->
      case previous do
        {:ok, opts} -> Application.put_env(:cadence_web, :provider_account_live_opts, opts)
        :error -> Application.delete_env(:cadence_web, :provider_account_live_opts)
      end
    end)

    %{
      scope: scope,
      user: user,
      org: org,
      account_id: account_id,
      conn: TestFixtures.member_conn(user),
      path: "/provider-accounts/" <> account_id
    }
  end

  test "host composes detail and orders sandbox rotation, grant and grant revocation", context do
    {:ok, view, _} = live(context.conn, context.path)
    original = page(view)
    assert original["id"] == "comms.provider-account-detail"
    assert original["context"]["resourceId"] == context.account_id
    model = original["data"]["model"]
    assert_producer(model, context.scope)
    rotation = input(model, 1)
    rotated = action(view, context.path, original, "rotate-credential", rotation)
    assert rotated["snapshot"]["status"] == "ok"
    updated = rotated["snapshot"]["data"]["result"]["patch"]
    assert updated["account"]["credential_version"] == model["account"]["credential_version"] + 1

    assert action(view, context.path, original, "rotate-credential", rotation)["snapshot"][
             "status"
           ] == "unknown"

    assert {:ok, current} = ProviderAccountDetail.load(context.scope, context.account_id)
    assert current.account.credential_version == updated["account"]["credential_version"]
    mission = TestFixtures.persist_mission!(context.org)

    grant =
      input(updated, 2)
      |> Map.put("grant", %{
        "mission_id" => mission.mission_id,
        "max_quota" => "0",
        "grant_reason" => "Sandbox admission"
      })

    granted = action(view, context.path, original, "grant-mission", grant)
    assert granted["snapshot"]["status"] == "ok"
    granted_model = granted["snapshot"]["data"]["result"]["patch"]
    assert [row] = granted_model["account_grants"]

    assert {:ok, saved} =
             ProviderAccountGrants.fetch_active_for_system(
               context.scope.organization_id,
               row["id"]
             )

    assert saved.restrictions["max_quota"] == 0

    revoke =
      input(granted_model, 3)
      |> Map.merge(%{"grant-id" => row["id"], "expected_grant_version" => row["version"]})

    assert action(view, context.path, original, "revoke-grant", revoke)["snapshot"]["status"] ==
             "ok"

    read = action(view, context.path, original, "refresh", %{})
    assert read["snapshot"]["status"] == "ok"
    assert [revoked] = read["snapshot"]["data"]["account_grants"]
    assert revoked["lifecycle"]["status"] == "blocked"
    assert_producer(read["snapshot"]["data"], context.scope)
  end

  test "account and page identity cannot be replaced by input or query parameters", context do
    {:ok, view, _} = live(context.conn, context.path <> "?provider_account_id=foreign")
    original = page(view)
    assert original["context"]["resourceId"] == context.account_id
    assert original["data"]["model"]["account"]["provider_account_id"] == context.account_id
    path = context.path <> "?provider_account_id=foreign"
    input = input(original["data"]["model"], 1)

    assert action(
             view,
             path,
             original,
             "rotate-credential",
             Map.put(input, "provider_account_id", "foreign")
           )["snapshot"]["status"] == "unknown"

    for bad <- [
          nil,
          [],
          Map.put(input, "sequence", "1"),
          Map.put(input, "credential_ref", %{}),
          Map.put(input, "arbitrary", "data")
        ] do
      assert action(view, path, original, "rotate-credential", bad)["snapshot"]["status"] ==
               "unknown"
    end

    refute action(view, path, Map.put(original, "token", Ecto.UUID.generate()), "refresh", %{})[
             "ok"
           ]

    refresh(view, "/missions")
    refute action(view, path, original, "rotate-credential", input)["ok"]
    refresh(view, path)
    refute page(view)["token"] == original["token"]
    refute action(view, path, original, "refresh", %{})["ok"]
    assert {:ok, current} = ProviderAccountDetail.load(context.scope, context.account_id)
    assert current.account.credential_version == 1
  end

  test "stale versions reject before effects; unknown results lock effects but preserve reads",
       context do
    {:ok, view, _} = live(context.conn, context.path)
    original = page(view)
    model = original["data"]["model"]
    stale = input(model, 1) |> Map.put("expected_account_version", 999)

    assert action(view, context.path, original, "rotate-credential", stale)["snapshot"]["status"] ==
             "rejected"

    bad_grant = input(model, 2) |> Map.put("grant", %{"mission_id" => "missing-mission"})

    assert action(view, context.path, original, "grant-mission", bad_grant)["snapshot"] == %{
             "status" => "unknown"
           }

    assert action(view, context.path, original, "rotate-credential", input(model, 3))["snapshot"][
             "status"
           ] == "unknown"

    assert action(view, context.path, original, "refresh", %{})["snapshot"]["status"] == "ok"
    refresh(view, context.path)
    assert page(view)["token"] == original["token"]
    assert page(view)["data"]["locked"]
    assert page(view)["data"]["sequence"] == 2
    assert {:ok, current} = ProviderAccountDetail.load(context.scope, context.account_id)
    assert current.account.credential_version == 1
  end

  test "missing accounts, foreign organizations, members and revoked sessions remain contained",
       context do
    {:ok, missing, _} = live(context.conn, "/provider-accounts/missing")
    assert page(missing)["status"] == "unavailable"
    {:ok, view, _} = live(context.conn, context.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(context.conn, :user_session_token))
    render_hook(view, "host:organization-page", request(context.path, original, "refresh", %{}))
    assert_redirect(view, "/sign-in")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), context.path)
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, context.org, role: :member)

    member =
      Scope.new(%{
        user: user,
        organization_id: context.org.organization_id,
        organization_membership: membership
      })

    assert {:error, :forbidden} = ProviderAccountDetail.load(member, context.account_id)
    assert {:error, {:redirect, %{to: "/"}}} = live(TestFixtures.member_conn(user), context.path)
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)

    foreign =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    assert {:error, :provider_account_not_found} =
             ProviderAccountDetail.load(foreign, context.account_id)
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "organization_module_page"
      ]

  defp input(model, sequence) do
    account = model["account"]

    %{
      "provider_account_id" => account["provider_account_id"],
      "credential_ref" => account["credential_ref"],
      "expected_account_version" => account["version"],
      "expected_credential_version" => account["credential_version"],
      "sequence" => sequence
    }
  end

  defp request(path, page, event, input),
    do: %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    }

  defp action(view, path, page, event, input) do
    render_hook(view, "host:organization-page", request(path, page, event, input))
    assert_reply(view, reply)
    Jason.decode!(Jason.encode!(reply))
  end

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp assert_producer(model, scope) do
    checker =
      Path.expand(
        "../../../../frontend/modules/communications/src/features/provider-accounts/producer-render-check.mjs",
        __DIR__
      )

    samples = [
      %{
        component: "ProviderAccountShow",
        organization_id: scope.organization_id,
        props: model,
        ids: [model["page"]["id"], model["grant_form"]["id"]]
      }
    ]

    {output, status} =
      System.cmd(System.find_executable("node"), [checker, Jason.encode!(samples)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
