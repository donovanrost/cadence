defmodule Cadence.Applications.OrganizationAdminProviderTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts.User

  alias Cadence.Applications.{
    ActionContractLedger,
    ActionDispatcher,
    ActionFailure,
    ActionProviderRegistry,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.{OrganizationAdmin, OrganizationAdminAction}
  alias Cadence.Applications.OrganizationAdminProviders, as: Providers
  alias Cadence.Applications.OrganizationAdminQuery
  alias Cadence.Applications.Registry
  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry
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
             SurfaceProviderRegistry.fetch(
               "organization_admin",
               "cadence.organization.home"
             )

    assert {:ok, OrganizationAdminAction} =
             ActionProviderRegistry.fetch("organization_admin")

    assert Map.keys(ActionProviderRegistry.providers()) |> Enum.sort() ==
             [
               "comms",
               "derived_telemetry",
               "limits",
               "mission_catalog",
               "ops_console",
               "organization_admin",
               "spacecraft",
               "telemetry_decom"
             ]
  end

  test "closes the complete five-application action ledger and preserves host-owned classification" do
    assert :ok = ActionContractLedger.validate()

    ledgers = ActionContractLedger.ledgers()
    assert length(ledgers.declared) == 60
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry

    assert OrganizationAdminAction.host_owned?("notifications", "accept_invitation")
    assert OrganizationAdminAction.host_owned?("admin_organization_show", "open_organization")

    refute OrganizationAdminAction.host_owned?(
             "provider_account_new",
             "register_provider_account"
           )
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

    assert {:ok, %{"data" => %{count: 0, notifications: []}}} =
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

  test "executes every organization-admin query family through non-LiveView providers", %{
    organization: organization,
    organization_scope: organization_scope,
    user_scope: user_scope,
    admin_scope: admin_scope
  } do
    {account, _version, _credential} = persist_provider_account!(organization)

    organization_queries = [
      {organization_scope, HostContext.organization(organization.organization_id),
       "organization_home", "cadence.organization.home", %{}},
      {organization_scope, HostContext.organization(organization.organization_id),
       "provider_accounts", "cadence.organization.provider_accounts.list", %{}},
      {organization_scope, HostContext.organization(organization.organization_id),
       "provider_account_new", "cadence.organization.provider_accounts.new", %{}},
      {organization_scope, HostContext.organization(organization.organization_id),
       "provider_account_show", "cadence.organization.provider_account.show",
       %{"provider_account_id" => account.provider_account_id}}
    ]

    user_queries = [
      {user_scope, HostContext.user(user_scope.user.user_id), "notifications",
       "cadence.organization.notifications", %{}},
      {user_scope, HostContext.user(user_scope.user.user_id), "notifications_bell",
       "cadence.organization.notifications_bell", %{}}
    ]

    admin_queries = [
      {admin_scope, HostContext.admin(), "admin_home", "cadence.platform_admin.home", %{}},
      {admin_scope, HostContext.admin(), "admin_runtime", "cadence.platform_admin.runtime", %{}},
      {admin_scope, HostContext.admin(), "admin_organizations",
       "cadence.platform_admin.organizations", %{}},
      {admin_scope, HostContext.admin(), "admin_organization_new",
       "cadence.platform_admin.organization.new", %{}},
      {admin_scope, HostContext.admin(), "admin_organization_show",
       "cadence.platform_admin.organization.show",
       %{"organization_id" => organization.organization_id}},
      {admin_scope, HostContext.admin(), "admin_organization_invite",
       "cadence.platform_admin.organization.invite",
       %{"organization_id" => organization.organization_id}}
    ]

    for {scope, context, surface_id, query_id, params} <-
          organization_queries ++ user_queries ++ admin_queries do
      assert {:ok, %{"data" => data}} =
               OrganizationAdminQuery.load(
                 scope,
                 context,
                 query_request(surface_id, query_id, params)
               )

      assert is_map(data)
    end

    assert is_map(Providers.OrganizationHome.presentation(organization))

    assert {:ok, %{provider_accounts: [_row]}} =
             Providers.ProviderAccountList.props(organization_scope)

    assert is_map(Providers.ProviderAccountNew.props())

    assert {:ok, %{page: _page, account_grants: _grants}} =
             Providers.ProviderAccountShow.props(organization_scope, account.provider_account_id)

    assert is_map(Providers.Notifications.presentation(user_scope))
    assert is_map(Providers.AdminHome.props())
    assert is_map(Providers.AdminRuntime.props())
    assert is_map(Providers.AdminOrganizationList.props())
    assert is_map(Providers.AdminOrganizationNew.props())

    assert {:ok, %{organization: _organization}} =
             Providers.AdminOrganizationShow.props(organization.organization_id)

    assert {:ok, %{page: _page}} =
             Providers.AdminOrganizationInvite.props(organization.organization_id)
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

  test "executes every provider-owned action family without route-module helpers", %{
    organization: organization,
    organization_scope: organization_scope,
    user_scope: user_scope,
    admin_scope: admin_scope
  } do
    assert {:ok, %{patch: %{form: provider_form}}} =
             execute_action(
               organization_scope,
               HostContext.organization(organization.organization_id),
               "provider_account_new",
               "validate_provider_account_form",
               %{"provider_account" => %{"provider_type" => "simulator", "backend_type" => "env"}}
             )

    assert provider_form.connector.selected.provider_type == "simulator"

    assert {:error, %ActionFailure{code: "invalid_input"}} =
             execute_action(
               organization_scope,
               HostContext.organization(organization.organization_id),
               "provider_account_new",
               "register_provider_account",
               %{}
             )

    for action_id <- [
          "validate_provider_account",
          "rotate_provider_credential",
          "revoke_provider_credential",
          "grant_provider_account_mission",
          "revoke_provider_account_mission"
        ] do
      assert {:error, _reason} =
               execute_action(
                 organization_scope,
                 HostContext.organization(organization.organization_id),
                 "provider_account_show",
                 action_id,
                 %{"provider_account_id" => "missing-provider-account"}
               )
    end

    for action_id <- ["accept_invitation", "mark_notification_read"] do
      assert {:error, %ActionFailure{}} =
               execute_action(
                 user_scope,
                 HostContext.user(user_scope.user.user_id),
                 "notifications",
                 action_id,
                 %{}
               )
    end

    assert {:error, %ActionFailure{}} =
             execute_action(
               user_scope,
               HostContext.user(user_scope.user.user_id),
               "notifications_bell",
               "mark_notification_read",
               %{}
             )

    assert {:ok, %{patch: _runtime}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_runtime",
               "refresh_runtime",
               %{}
             )

    assert {:ok, %{patch: _filtered_runtime}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_runtime",
               "filter_runtime_decisions",
               %{"runtime_decision_filters" => %{"dashboard_id" => "missing"}}
             )

    assert {:ok, %{patch: %{form: _organization_form}}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_new",
               "validate_organization",
               %{"organization" => %{}}
             )

    assert {:error, %ActionFailure{code: "invalid_organization"}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_new",
               "create_organization",
               %{}
             )

    assert {:error, %ActionFailure{code: "invalid_input"}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_show",
               "issue_service_identity",
               %{}
             )

    assert {:ok, %{patch: %{issued_service_token: nil}}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_show",
               "dismiss_service_token",
               %{}
             )

    assert {:error, %ActionFailure{code: "host_owned_action"}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_show",
               "open_organization",
               %{}
             )

    assert {:ok, %{patch: %{form: _invite_form}}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_invite",
               "validate_invitation",
               %{"invite" => %{}}
             )

    assert {:error, %ActionFailure{code: "invalid_input"}} =
             execute_action(
               admin_scope,
               HostContext.admin(),
               "admin_organization_invite",
               "invite_organization_member",
               %{}
             )
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
                 action_id: "validate_provider_account_form",
                 surface_id: "provider_account_new",
                 surface_version: 1
               }
             )

    assert {:error, :scope_mismatch} =
             ActionDispatcher.authorize(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "mark_notification_read",
                 surface_id: "notifications",
                 surface_version: 1
               }
             )
  end

  test "uses exact installation exemptions and rejects arbitrary no-install applications", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    assert ApplicationSurfaces.organization_installation_exempt?("mission_catalog")
    assert ApplicationSurfaces.organization_installation_exempt?("organization_admin")
    assert ApplicationSurfaces.installation_exempt?("mission_catalog", :organization)

    assert ApplicationSurfaces.installation_exempt?("organization_admin", :organization)
    assert ApplicationSurfaces.installation_exempt?("organization_admin", :user)
    assert ApplicationSurfaces.installation_exempt?("organization_admin", :admin)

    refute ApplicationSurfaces.installation_exempt?("mission_catalog", :user)
    refute ApplicationSurfaces.installation_exempt?("mission_catalog", :admin)
    refute ApplicationSurfaces.installation_exempt?("organization_admin", :mission)
    refute ApplicationSurfaces.installation_exempt?("organization_admin", :spacecraft)

    for placement <- [:organization, :user, :admin, :mission, :spacecraft] do
      refute ApplicationSurfaces.installation_exempt?("third_party", placement)
    end

    assert {:error, :application_installation_scope_required} =
             ApplicationInstallations.fetch_installed(
               organization_scope,
               HostContext.organization(organization.organization_id),
               "third_party"
             )

    assert {:ok, definition} = Registry.fetch_available("mission_catalog")
    assert {:ok, surface} = Registry.fetch_surface(definition, :organization, "mission_list")

    assert {:ok, _result} =
             ApplicationSurfaces.load(
               organization_scope,
               HostContext.organization(organization.organization_id),
               "mission_catalog",
               1,
               surface
             )
  end

  test "uses the same installation exemption matrix in the action dispatcher" do
    assert ActionDispatcher.installation_exempt?("mission_catalog", :organization)
    assert ActionDispatcher.installation_exempt?("organization_admin", :organization)
    assert ActionDispatcher.installation_exempt?("organization_admin", :user)
    assert ActionDispatcher.installation_exempt?("organization_admin", :admin)

    refute ActionDispatcher.installation_exempt?("mission_catalog", :user)
    refute ActionDispatcher.installation_exempt?("mission_catalog", :admin)
    refute ActionDispatcher.installation_exempt?("organization_admin", :mission)
    refute ActionDispatcher.installation_exempt?("organization_admin", :spacecraft)
    refute ActionDispatcher.installation_exempt?("third_party", :organization)
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
                 action_id: "refresh_runtime",
                 surface_id: "admin_runtime",
                 surface_version: 1
               }
             )

    assert {:error, :scope_mismatch} =
             OrganizationAdminAction.execute(
               organization_scope,
               HostContext.organization("different-organization"),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "validate_provider_account_form",
                 surface_id: "provider_account_new",
                 surface_version: 1
               }
             )

    assert admin_scope.user.user_id != user_scope.user.user_id
  end

  test "requires the exact provider-owned surface binding before action execution", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    base = %ActionRequest{
      application_key: "organization_admin",
      application_version: 1,
      action_id: "validate_provider_account_form",
      surface_id: "provider_account_new",
      surface_version: 1,
      params: %{
        "provider_account" => %{
          "provider_type" => "simulator",
          "backend_type" => "env"
        }
      }
    }

    assert {:ok, _result} =
             OrganizationAdminAction.execute(
               organization_scope,
               HostContext.organization(organization.organization_id),
               base
             )

    for request <- [
          %{base | surface_id: nil, surface_version: nil},
          %{base | surface_version: 2},
          %{base | action_id: "mark_notification_read", surface_id: "provider_account_new"},
          %{base | action_id: "accept_invitation", surface_id: "notifications_bell"},
          %{base | action_id: "register_provider_account", surface_id: "provider_account_show"}
        ] do
      assert {:error, :unsupported_application_action} =
               OrganizationAdminAction.execute(
                 organization_scope,
                 HostContext.organization(organization.organization_id),
                 request
               )
    end
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
                 surface_id: "provider_account_new",
                 surface_version: 1,
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

  defp execute_action(scope, host_context, surface_id, action_id, params) do
    OrganizationAdminAction.execute(
      scope,
      host_context,
      %ActionRequest{
        application_key: "organization_admin",
        application_version: 1,
        action_id: action_id,
        surface_id: surface_id,
        surface_version: 1,
        params: params
      }
    )
  end

  defp persist_provider_account!(organization) do
    suffix = System.unique_integer([:positive])
    account_id = "provider-account-closure-#{suffix}"
    credential_ref = "provider-credential-closure-#{suffix}"
    now = ~U[2026-07-15 20:00:00.000000Z]

    {:ok, credential} =
      ProviderCredentials.create(
        organization.organization_id,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/closure/#{suffix}",
          registered_at: now
        },
        manage_backend?: false,
        now: now
      )

    {:ok, account, version} =
      ProviderAccounts.create_for_system(
        organization.organization_id,
        %{
          provider_account_id: account_id,
          display_name: "Closure Provider",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "demo",
          credential_ref: credential_ref,
          guardrails: %{
            "allowed_services" => ["telemetry"],
            "allowed_stations" => ["station-alpha"],
            "max_quota" => 10
          }
        },
        %{"kind" => "system", "id" => "organization-admin-provider-test"},
        validate_credential?: false,
        now: now
      )

    {account, version, credential}
  end
end
