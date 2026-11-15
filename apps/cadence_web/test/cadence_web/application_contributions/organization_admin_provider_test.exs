defmodule Cadence.Applications.OrganizationAdminProviderTest do
  use CadenceWeb.ConnCase, async: false

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
  alias Cadence.Applications.OrganizationAdminQuery
  alias Cadence.Auth.Scope
  alias Cadence.Notifications.Notification
  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.ProviderRegistry, as: SurfaceProviderRegistry
  alias CadenceWeb.TestFixtures

  setup do
    organization = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(user_id: "org-provider-user")
    membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    {:ok,
     organization: organization,
     organization_scope:
       Scope.new(%{
         user: user,
         organization_id: organization.organization_id,
         organization_membership: membership
       }),
     user_scope: Scope.new(%{user: user})}
  end

  test "registers the notifications bell with executable query and action authorities" do
    assert Enum.map(OrganizationAdmin.surface_query_contributions(), & &1.query_id) == [
             "cadence.organization.notifications_bell"
           ]

    assert Enum.all?(OrganizationAdmin.surface_query_contributions(), fn contribution ->
             contribution.provider == OrganizationAdminQuery
           end)

    assert {:ok, OrganizationAdminQuery} =
             SurfaceProviderRegistry.fetch(
               "organization_admin",
               "cadence.organization.notifications_bell"
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
    assert length(ledgers.declared) == 36
    assert ledgers.declared == ledgers.provider
    assert ledgers.declared == ledgers.registry

    refute OrganizationAdminAction.host_owned?("notifications_bell", "mark_notification_read")
  end

  test "loads the executable user presentation", %{user_scope: user_scope} do
    assert {:ok, %{"data" => %{context: %{version: 1, unread_count: 0, notifications: []}}}} =
             OrganizationAdminQuery.load(
               user_scope,
               HostContext.user(user_scope.user.user_id),
               query_request("notifications_bell", "cadence.organization.notifications_bell")
             )
  end

  test "executes every organization-admin query family through non-LiveView providers", %{
    user_scope: user_scope
  } do
    user_queries = [
      {user_scope, HostContext.user(user_scope.user.user_id), "notifications_bell",
       "cadence.organization.notifications_bell", %{}}
    ]

    for {scope, context, surface_id, query_id, params} <- user_queries do
      assert {:ok, %{"data" => data}} =
               OrganizationAdminQuery.load(
                 scope,
                 context,
                 query_request(surface_id, query_id, params)
               )

      assert is_map(data)
    end
  end

  test "keeps action permissions and effects specific to their operations" do
    actions = Map.new(OrganizationAdmin.definition().actions, &{&1.action_id, &1})

    assert actions["mark_notification_read"].required_permission == "read_notifications"
    assert actions["mark_notification_read"].effect == :durable
  end

  test "rejects a notification read without its subject", %{user_scope: user_scope} do
    assert {:error, %ActionFailure{code: "invalid_input"}} =
             execute_action(
               user_scope,
               HostContext.user(user_scope.user.user_id),
               "notifications_bell",
               "mark_notification_read",
               %{}
             )
  end

  test "rejects user actions in the organization context", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    # §11c A + L13: the remote installs at user scope only, so the organization context is refused
    # before the action's own scope check.
    assert {:error, :unsupported_application_host_context} =
             ActionDispatcher.authorize(
               organization_scope,
               HostContext.organization(organization.organization_id),
               %ActionRequest{
                 application_key: "organization_admin",
                 application_version: 1,
                 action_id: "mark_notification_read",
                 surface_id: "notifications_bell",
                 surface_version: 1
               }
             )
  end

  test "uses exact installation exemptions and rejects arbitrary no-install applications", %{
    organization: organization,
    organization_scope: organization_scope
  } do
    refute ApplicationSurfaces.organization_installation_exempt?("mission_catalog")

    # §11c A + L13: no organization-scope surface is left; the remote installs at user scope only.
    refute ApplicationSurfaces.organization_installation_exempt?("organization_admin")
    refute ApplicationSurfaces.installation_exempt?("mission_catalog", :organization)

    refute ApplicationSurfaces.installation_exempt?("organization_admin", :organization)
    assert ApplicationSurfaces.installation_exempt?("organization_admin", :user)
    # L7: platform admin is in the console; the remote no longer installs at :admin.
    refute ApplicationSurfaces.installation_exempt?("organization_admin", :admin)

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
  end

  test "uses the same installation exemption matrix in the action dispatcher" do
    refute ActionDispatcher.installation_exempt?("mission_catalog", :organization)
    refute ActionDispatcher.installation_exempt?("organization_admin", :organization)
    assert ActionDispatcher.installation_exempt?("organization_admin", :user)
    refute ActionDispatcher.installation_exempt?("organization_admin", :admin)

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

  test "rejects cross-scope contexts", %{
    organization_scope: organization_scope,
    user_scope: user_scope
  } do
    assert {:error, :scope_mismatch} =
             OrganizationAdminQuery.load(
               organization_scope,
               HostContext.organization("different-organization"),
               query_request("notifications_bell", "cadence.organization.notifications_bell")
             )

    assert {:error, :scope_mismatch} =
             OrganizationAdminQuery.load(
               user_scope,
               HostContext.user("different-user"),
               query_request("notifications_bell", "cadence.organization.notifications_bell")
             )
  end

  test "requires the exact provider-owned surface binding before action execution", %{
    user_scope: user_scope
  } do
    host = HostContext.user(user_scope.user.user_id)

    base = %ActionRequest{
      application_key: "organization_admin",
      application_version: 1,
      action_id: "mark_notification_read",
      surface_id: "notifications_bell",
      surface_version: 1,
      params: %{}
    }

    # The exact binding is admitted and reaches the action's own input validation.
    assert {:error, %ActionFailure{code: "invalid_input"}} =
             OrganizationAdminAction.execute(user_scope, host, base)

    for request <- [
          %{base | surface_id: nil, surface_version: nil},
          %{base | surface_version: 2},
          %{base | surface_id: "organization_home"},
          %{base | action_id: "accept_invitation"},
          %{base | action_id: "register_provider_account", surface_id: "provider_account_new"}
        ] do
      assert {:error, :unsupported_application_action} =
               OrganizationAdminAction.execute(user_scope, host, request)
    end
  end

  test "notification compatibility delegates inbox placement and retains the bell read result", %{
    user_scope: scope
  } do
    {:ok, n} =
      Cadence.Notifications.persist_notification(
        Notification.new(%{
          user_id: scope.user.user_id,
          kind: :organization_access_granted,
          title: "Access notice"
        })
      )

    assert {:ok,
            %{patch: %{context: %{version: 1, user: user, unread_count: 0, notifications: [row]}}}} =
             execute_action(
               scope,
               HostContext.user(scope.user.user_id),
               "notifications_bell",
               "mark_notification_read",
               %{"notification_id" => n.notification_id}
             )

    assert row.notification_id == n.notification_id
    assert user.user_id == scope.user.user_id
    assert {:ok, _, 0} = DateTime.from_iso8601(row.read_at)
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
end
