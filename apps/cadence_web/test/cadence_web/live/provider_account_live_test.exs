defmodule CadenceWeb.ProviderAccountLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "organization administrators can mount provider account surfaces" do
    {conn, _user, organization} = signed_in_organization_admin()

    assert_provider_account_surface(
      conn,
      ~p"/provider-accounts",
      "provider-account-list-page-component",
      "provider_accounts",
      class: "contents",
      organization_id: organization.organization_id,
      query_params: %{}
    )

    assert_provider_account_surface(
      conn,
      ~p"/provider-accounts/new",
      "provider-account-new-component",
      "provider_account_new",
      class: "max-w-3xl space-y-6",
      organization_id: organization.organization_id,
      query_params: %{}
    )

    provider_account_id = "provider-account-test"

    assert_provider_account_surface(
      conn,
      ~p"/provider-accounts/#{provider_account_id}",
      "provider-account-show-component",
      "provider_account_show",
      class: "contents",
      organization_id: organization.organization_id,
      query_params: %{"provider_account_id" => provider_account_id}
    )
  end

  test "ordinary members are redirected away from provider account administration" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: :member)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(TestFixtures.member_conn(user), ~p"/provider-accounts")
  end

  defp assert_provider_account_surface(conn, path, id, surface_id, opts) do
    {:ok, view, _html} = live(conn, path)

    assert has_element?(view, "##{id}")
    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.ssr == false
    assert vue.class == Keyword.fetch!(opts, :class)
    assert vue.handlers == %{}

    query_params = Keyword.fetch!(opts, :query_params)
    organization_id = Keyword.fetch!(opts, :organization_id)

    assert vue.props == %{
             "application_key" => "organization_admin",
             "surface_id" => surface_id,
             "host_scope" => "organization",
             "organization_id" => organization_id,
             "query_params" => query_params
           }
  end

  defp signed_in_organization_admin do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()

    _membership =
      TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    {TestFixtures.member_conn(user), user, organization}
  end
end
