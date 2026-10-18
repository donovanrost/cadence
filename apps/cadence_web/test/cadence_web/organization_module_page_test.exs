defmodule CadenceWeb.OrganizationModulePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.OrganizationAdminProviders.ProviderAccountList
  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias Cadence.Reads.Comms.ProviderAccountDirectory
  alias CadenceWeb.{HostTransportTestSupport, OrganizationModulePage, TestFixtures}

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    %{conn: TestFixtures.member_conn(user), user: user, org: org, scope: scope}
  end

  test "host composes scoped empty and populated directories without frontend release admission",
       context do
    {:ok, view, _} = live(context.conn, "/provider-accounts")

    HostTransportTestSupport.assert_context(view, %{
      "kind" => "organization_module",
      "host_scope" => "organization",
      "organization_id" => context.org.organization_id,
      "query_params" => %{}
    })

    empty = contribution(view)
    assert empty["data"]["count"] == 0
    assert_consumer(empty, context.scope)
    account_id = persist_account!(context.scope)
    render_hook(view, "host:context", %{"path" => "/provider-accounts?organization_id=foreign"})
    populated = contribution(view)
    assert populated["context"]["organizationId"] == context.org.organization_id
    assert [row] = populated["data"]["provider_accounts"]
    assert row["provider_account_id"] == account_id
    assert row["href"] == "/provider-accounts/" <> account_id
    assert_consumer(populated, context.scope)
    render_hook(view, "host:context", %{"path" => "/missions"})
    assert contribution(view) == nil
  end

  test "legacy entry delegates to the same read; foreign organizations remain isolated",
       context do
    persist_account!(context.scope)
    assert {:ok, data} = ProviderAccountDirectory.load(context.scope)
    assert ProviderAccountList.props(context.scope) == {:ok, data}
    other = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(context.user, other, role: :organization_admin)

    foreign =
      Scope.new(%{
        user: context.user,
        organization_id: other.organization_id,
        organization_membership: membership
      })

    assert {:ok, %{count: 0, provider_accounts: []}} = ProviderAccountDirectory.load(foreign)
    assert data.count == 1
  end

  test "member, unauthenticated and revoked-session reads cannot bypass host authorization",
       context do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), "/provider-accounts")
    member_user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(member_user, context.org, role: :member)

    member =
      Scope.new(%{
        user: member_user,
        organization_id: context.org.organization_id,
        organization_membership: membership
      })

    assert {:error, :forbidden} = ProviderAccountDirectory.load(member)

    assert %{status: "unavailable"} =
             OrganizationModulePage.load(member, %{route: "/provider-accounts"})

    assert {:error, {:redirect, %{to: "/"}}} =
             live(TestFixtures.member_conn(member_user), "/provider-accounts")

    {:ok, view, _} = live(context.conn, "/provider-accounts")
    :ok = Cadence.Auth.revoke_user_session(get_session(context.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => "/provider-accounts"})
    assert_redirect(view, "/sign-in")
  end

  defp contribution(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "organization_module_page"
      ]

  defp assert_consumer(snapshot, scope) do
    assert snapshot["id"] == "comms.provider-account-directory"
    assert snapshot["slot"] == "organization.page"
    assert snapshot["version"] == 1
    assert snapshot["status"] == "ready"

    checker =
      Path.expand(
        "../../../../frontend/modules/communications/src/features/provider-accounts/producer-render-check.mjs",
        __DIR__
      )

    samples = [
      %{
        component: "ProviderAccountListPage",
        organization_id: scope.organization_id,
        props: snapshot["data"],
        ids:
          ["provider-accounts-page"] ++
            Enum.map(snapshot["data"]["provider_accounts"], & &1["__dom_id"])
      }
    ]

    node = System.find_executable("node") || flunk("Node required for producer/consumer proof")
    {output, status} = System.cmd(node, [checker, Jason.encode!(samples)], stderr_to_stdout: true)
    assert status == 0, output
  end

  defp persist_account!(scope) do
    suffix = System.unique_integer([:positive])
    account_id = "directory-account-#{suffix}"
    credential_ref = "directory-credential-#{suffix}"

    assert {:ok, _} =
             ProviderCredentials.create(
               scope.organization_id,
               account_id,
               %{
                 provider_credential_ref: credential_ref,
                 backend_type: :external,
                 backend_key: "fixture/directory/#{suffix}",
                 registered_at: ~U[2026-09-07 10:00:00.000000Z]
               },
               manage_backend?: false
             )

    assert {:ok, _account, _version} =
             ProviderAccounts.create(
               scope,
               %{
                 provider_account_id: account_id,
                 credential_ref: credential_ref,
                 provider_type: :simulator,
                 display_name: "Relay Directory",
                 base_url: "https://provider.example.test",
                 region_ref: "test",
                 environment_ref: "test"
               },
               validate_credential?: false
             )

    account_id
  end
end
