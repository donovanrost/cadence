defmodule CadenceWeb.ApplicationContributions.OrganizationAdminProviderTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Applications.{ActionDispatcher, ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.Registry
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces
  alias CadenceWeb.ApplicationContributions.{OrganizationAdmin, OrganizationAdminAction}
  alias CadenceWeb.ApplicationContributions.OrganizationAdminQuery
  alias CadenceWeb.TestFixtures

  setup do
    organization = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(user_id: "org-provider-user")
    membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    admin =
      TestFixtures.persist_user!(
        user_id: "platform-provider-user",
        capabilities: [:platform_admin]
      )

    {:ok,
     organization: organization,
     organization_scope:
       Scope.new(%{
         user: user,
         organization_id: organization.organization_id,
         organization_membership: membership
       }),
     user_scope: Scope.new(%{user: user}),
     admin_scope: Scope.new(%{user: admin, admin_mode?: true})}
  end

  test "registers all twelve surfaces with executable query and action authorities" do
    assert Enum.map(OrganizationAdmin.surface_query_contributions(), & &1.query_id) == [
             "cadence.organization.home",
             "cadence.organization.provider_accounts.list",
             "cadence.organization.provider_accounts.new",
             "cadence.organization.provider_account.show",
             "cadence.organization.notifications",
             "cadence.organization.notifications_bell",
             "cadence.platform_admin.home",
             "cadence.platform_admin.runtime",
             "cadence.platform_admin.organizations",
             "cadence.platform_admin.organization.new",
             "cadence.platform_admin.organization.show",
             "cadence.platform_admin.organization.invite"
           ]

    assert Enum.all?(OrganizationAdmin.surface_query_contributions(), fn contribution ->
             contribution.provider == OrganizationAdminQuery
           end)

    assert {:ok, OrganizationAdminQuery} =
             Cadence.Reads.ApplicationSurfaces.ProviderRegistry.fetch(
               "organization_admin",
               "cadence.organization.home"
             )

    assert {:ok, OrganizationAdminAction} =
             Cadence.Applications.ActionProviderRegistry.fetch("organization_admin")
  end

  test "loads executable organization, user, and admin presentations", %{
    organization: organization,
    organization_scope: organization_scope,
    user_scope: user_scope,
    admin_scope: admin_scope
  } do
    assert {:ok, %{"data" => %{page: _page, form: _form}}} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.organization(organization.organization_id),
               query_request(
                 "provider_account_new",
                 "cadence.organization.provider_accounts.new"
               )
             )

    assert {:ok, %{"data" => %{presentation: _presentation}}} =
             OrganizationAdminQuery.load(
               user_scope,
               HostContext.user(user_scope.user.user_id),
               query_request("notifications_bell", "cadence.organization.notifications_bell")
             )

    assert {:ok, %{"data" => %{presentation: _presentation}}} =
             OrganizationAdminQuery.load(
               admin_scope,
               HostContext.admin(),
               query_request("admin_home", "cadence.platform_admin.home")
             )
  end

  test "keeps action permissions and effects specific to their operations" do
    actions = Map.new(OrganizationAdmin.definition().actions, &{&1.action_id, &1})

    assert actions["validate_provider_account_form"].required_permission ==
             "manage_provider_accounts"

    assert actions["validate_provider_account_form"].effect == :none
    assert actions["validate_provider_account"].effect == :external
    assert actions["validate_provider_account"].intent == :maintenance
    assert actions["accept_invitation"].required_permission == "accept_invitation"
    assert actions["accept_invitation"].effect == :durable
    assert actions["refresh_runtime"].effect == :none
    assert actions["dismiss_service_token"].effect == :none
    assert actions["open_organization"].effect == :external
  end

  test "authorizes organization actions without installation and rejects user actions there", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    assert :ok =
             ActionDispatcher.authorize(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "validate_provider_account_form"
               }
             )

    assert {:error, :scope_mismatch} =
             ActionDispatcher.authorize(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "mark_notification_read"
               }
             )
  end

  test "requires installation for an unrelated application in an organization placement", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    assert {:ok, definition} = Registry.fetch_available("mission_catalog")
    assert {:ok, surface} = Registry.fetch_surface(definition, :organization, "mission_list")

    assert {:error, :application_installation_scope_required} =
             ApplicationSurfaces.load(
               organization_scope,
               HostContext.organization(organization.organization_id),
               "mission_catalog",
               1,
               surface
             )
  end

  test "does not admit an unrelated application through the organization dispatcher", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    assert {:error, :unsupported_application_host_context} =
             ActionDispatcher.authorize(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "telemetry_decom",
                 application_version: 1,
                 action_id: "disable"
               }
             )
  end

  test "rejects cross-scope contexts and cross-scope subjects", %{
    organization: organization,
    organization_scope: organization_scope,
    user_scope: user_scope,
    admin_scope: admin_scope
  } do
    assert {:error, :scope_mismatch} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.organization("different-organization"),
               query_request("provider_account_new", "cadence.organization.provider_accounts.new")
             )

    assert {:error, :scope_mismatch} =
             OrganizationAdminQuery.load(
               user_scope,
               HostContext.user("different-user"),
               query_request("notifications", "cadence.organization.notifications")
             )

    assert {:error, :forbidden} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.admin(),
               query_request("admin_home", "cadence.platform_admin.home")
             )

    assert {:error, :application_surface_subject_required} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.organization(organization.organization_id),
               query_request(
                 "provider_account_show",
                 "cadence.organization.provider_account.show"
               )
             )

    assert {:error, _reason} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.organization(organization.organization_id),
               query_request(
                 "provider_account_show",
                 "cadence.organization.provider_account.show",
                 %{"provider_account_id" => "provider-account-from-another-scope"}
               )
             )

    assert {:error, :forbidden} =
             OrganizationAdminAction.execute(
               Scope.new(%{user: %User{user_id: "not-an-admin"}}),
               HostContext.admin(),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "refresh_runtime"
               }
             )

    assert {:error, :scope_mismatch} =
             OrganizationAdminAction.execute(
               organization_scope,
               HostContext.organization("different-organization"),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "validate_provider_account_form"
               }
             )

    assert admin_scope.user.user_id != user_scope.user.user_id
  end

  test "executes a real Phoenix-owned form validation patch", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    assert {:ok, %{patch: %{form: form}}} =
             OrganizationAdminAction.execute(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "validate_provider_account_form",
                 params: %{
                   "provider_account" => %{
                     "provider_type" => "simulator",
                     "backend_type" => "env"
                   }
                 }
               }
             )

    assert is_map(form)
    assert form.connector.selected.provider_type == "simulator"
  end

  defp query_request(surface_id, query_id, params \\ %{}) do
    %SurfaceQueryRequest{
      application_key: "organization_admin",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: query_id,
      query_version: 1,
      params: params
    }
  end
end
