defmodule CadenceWeb.ApplicationContributions.OrganizationAdminTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.ApplicationContributions.{
    OrganizationAdmin,
    OrganizationAdminAction,
    OrganizationAdminQuery
  }

  @expected_surface_contracts [
    %{
      id: "organization_home",
      purpose: :overview,
      scope: :organization,
      placement: :application_workspace,
      navigation: %{label: "Overview", order: 10},
      query: %{id: "cadence.organization.home", version: 1},
      actions: [],
      exposed_module: "./Application"
    },
    %{
      id: "provider_accounts",
      purpose: :collection,
      scope: :organization,
      placement: :application_workspace,
      navigation: %{label: "Provider Accounts", order: 20},
      query: %{id: "cadence.organization.provider_accounts.list", version: 1},
      actions: [],
      exposed_module: "./Application"
    },
    %{
      id: "provider_account_new",
      purpose: :configuration,
      scope: :organization,
      placement: :application_workspace,
      navigation: %{label: "New Provider Account", order: 30},
      query: %{id: "cadence.organization.provider_accounts.new", version: 1},
      actions: ["validate_provider_account_form", "register_provider_account"],
      exposed_module: "./Application"
    },
    %{
      id: "provider_account_show",
      purpose: :subject_detail,
      scope: :organization,
      placement: :application_workspace,
      navigation: %{label: "Provider Account", order: 40},
      query: %{id: "cadence.organization.provider_account.show", version: 1},
      actions: [
        "validate_provider_account",
        "rotate_provider_credential",
        "revoke_provider_credential",
        "grant_provider_account_mission",
        "revoke_provider_account_mission"
      ],
      exposed_module: "./Application"
    },
    %{
      id: "notifications",
      purpose: :activity,
      scope: :user,
      placement: :application_workspace,
      navigation: %{label: "Notifications", order: 50},
      query: %{id: "cadence.organization.notifications", version: 1},
      actions: ["accept_invitation", "mark_notification_read"],
      exposed_module: "./Application"
    },
    %{
      id: "notifications_bell",
      purpose: :activity,
      scope: :user,
      placement: :application_workspace,
      navigation: %{label: "Notifications Bell", order: 60},
      query: %{id: "cadence.organization.notifications_bell", version: 1},
      actions: ["mark_notification_read"],
      exposed_module: "./Application"
    },
    %{
      id: "admin_home",
      purpose: :overview,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "Overview", order: 70},
      query: %{id: "cadence.platform_admin.home", version: 1},
      actions: [],
      exposed_module: "./Application"
    },
    %{
      id: "admin_runtime",
      purpose: :activity,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "Runtime", order: 80},
      query: %{id: "cadence.platform_admin.runtime", version: 1},
      actions: ["refresh_runtime", "filter_runtime_decisions"],
      exposed_module: "./Application"
    },
    %{
      id: "admin_organizations",
      purpose: :collection,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "Organizations", order: 90},
      query: %{id: "cadence.platform_admin.organizations", version: 1},
      actions: [],
      exposed_module: "./Application"
    },
    %{
      id: "admin_organization_new",
      purpose: :configuration,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "New Organization", order: 100},
      query: %{id: "cadence.platform_admin.organization.new", version: 1},
      actions: ["validate_organization", "create_organization"],
      exposed_module: "./Application"
    },
    %{
      id: "admin_organization_show",
      purpose: :subject_detail,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "Organization", order: 110},
      query: %{id: "cadence.platform_admin.organization.show", version: 1},
      actions: ["issue_service_identity", "dismiss_service_token", "open_organization"],
      exposed_module: "./Application"
    },
    %{
      id: "admin_organization_invite",
      purpose: :configuration,
      scope: :admin,
      placement: :application_workspace,
      navigation: %{label: "Invite User", order: 120},
      query: %{id: "cadence.platform_admin.organization.invite", version: 1},
      actions: ["validate_invitation", "invite_organization_member"],
      exposed_module: "./Application"
    }
  ]

  test "contributes every post-auth organization and platform-admin surface" do
    assert :ok = OrganizationAdmin.validate()

    assert Enum.map(OrganizationAdmin.surfaces(), & &1.id) == [
             "organization_home",
             "provider_accounts",
             "provider_account_new",
             "provider_account_show",
             "notifications",
             "notifications_bell",
             "admin_home",
             "admin_runtime",
             "admin_organizations",
             "admin_organization_new",
             "admin_organization_show",
             "admin_organization_invite"
           ]

    assert Enum.map(OrganizationAdmin.surfaces(), &{&1.id, &1.scope}) == [
             {"organization_home", :organization},
             {"provider_accounts", :organization},
             {"provider_account_new", :organization},
             {"provider_account_show", :organization},
             {"notifications", :user},
             {"notifications_bell", :user},
             {"admin_home", :admin},
             {"admin_runtime", :admin},
             {"admin_organizations", :admin},
             {"admin_organization_new", :admin},
             {"admin_organization_show", :admin},
             {"admin_organization_invite", :admin}
           ]

    assert Enum.all?(OrganizationAdmin.release_contributions(), fn release ->
             release.exposed_module == "./Application"
           end)
  end

  test "keeps the complete server surface contract internally consistent" do
    assert Enum.map(OrganizationAdmin.surfaces(), &surface_contract/1) ==
             @expected_surface_contracts

    assert Enum.map(OrganizationAdmin.definition().surfaces, fn surface ->
             %{
               id: surface.surface_id,
               purpose: surface.purpose,
               scope: surface.scope,
               placement: surface.placement,
               navigation: surface.navigation,
               query: %{
                 id: surface.data_contract.query_id,
                 version: surface.data_contract.version
               },
               actions: surface.actions
             }
           end) == Enum.map(@expected_surface_contracts, &Map.delete(&1, :exposed_module))

    assert Enum.map(OrganizationAdmin.release_contributions(), fn release ->
             {release.surface_id, release.surface_version, release.exposed_module}
           end) ==
             Enum.map(@expected_surface_contracts, &{&1.id, 1, &1.exposed_module})

    assert Enum.all?(@expected_surface_contracts, fn surface ->
             {:ok, query} = OrganizationAdminQuery.fetch(surface.query.id, surface.query.version)
             query.surface_id == surface.id
           end)
  end

  test "binds every contribution to a Phoenix-owned query and renderer component" do
    for surface <- OrganizationAdmin.surfaces() do
      assert {:ok, query} = OrganizationAdminQuery.fetch(surface.query)
      assert query.surface_id == surface.id
      assert surface.component =~ ~r/^[A-Z][A-Za-z]+$/
    end
  end

  test "publishes the exact 19-row surface action ledger with 18 unique actions" do
    expected = [
      {"provider_account_new", 1, "validate_provider_account_form"},
      {"provider_account_new", 1, "register_provider_account"},
      {"provider_account_show", 1, "validate_provider_account"},
      {"provider_account_show", 1, "rotate_provider_credential"},
      {"provider_account_show", 1, "revoke_provider_credential"},
      {"provider_account_show", 1, "grant_provider_account_mission"},
      {"provider_account_show", 1, "revoke_provider_account_mission"},
      {"notifications", 1, "accept_invitation"},
      {"notifications", 1, "mark_notification_read"},
      {"notifications_bell", 1, "mark_notification_read"},
      {"admin_runtime", 1, "refresh_runtime"},
      {"admin_runtime", 1, "filter_runtime_decisions"},
      {"admin_organization_new", 1, "validate_organization"},
      {"admin_organization_new", 1, "create_organization"},
      {"admin_organization_show", 1, "issue_service_identity"},
      {"admin_organization_show", 1, "dismiss_service_token"},
      {"admin_organization_show", 1, "open_organization"},
      {"admin_organization_invite", 1, "validate_invitation"},
      {"admin_organization_invite", 1, "invite_organization_member"}
    ]

    surface_pairs =
      OrganizationAdmin.surfaces()
      |> Enum.flat_map(fn surface -> Enum.map(surface.actions, &{surface.id, 1, &1}) end)

    action_pairs = Enum.map(OrganizationAdminAction.all(), &{&1.surface_id, &1.version, &1.id})

    assert length(surface_pairs) == 19
    assert length(action_pairs) == 19
    assert length(Enum.uniq(Enum.map(action_pairs, &elem(&1, 2)))) == 18
    assert surface_pairs == expected
    assert action_pairs == expected
    assert length(OrganizationAdmin.definition().actions) == 18
  end

  test "rejects duplicate provider binding rows" do
    [first | _rest] = OrganizationAdminAction.all()

    assert {:error, :duplicate_action_bindings} =
             OrganizationAdminAction.validate_bindings(OrganizationAdminAction.all() ++ [first])
  end

  test "keeps invitation acceptance and organization opening host-owned" do
    assert OrganizationAdminAction.host_owned?("notifications", "accept_invitation")
    assert OrganizationAdminAction.host_owned?("admin_organization_show", "open_organization")

    assert OrganizationAdmin.host_owned_flows() == %{
             sign_in: "Phoenix authentication and session establishment",
             invitation_acceptance: "Phoenix validates and persists membership acceptance",
             no_organization_bootstrap: "Phoenix establishes the first organization scope",
             admin_mode_transition:
               "Phoenix owns admin-mode reauthentication and session transition"
           }
  end

  test "does not expose pre-scope bootstrap or admin-mode transition surfaces" do
    surface_ids = MapSet.new(Enum.map(OrganizationAdmin.surfaces(), & &1.id))

    refute MapSet.member?(surface_ids, "sign_in")
    refute MapSet.member?(surface_ids, "no_organization")
    refute MapSet.member?(surface_ids, "admin_mode")
    refute MapSet.member?(surface_ids, "organization_invitation")
  end

  test "records every existing LiveView mount as a compatibility wrapper" do
    wrappers = OrganizationAdmin.compatibility_wrappers()

    assert Enum.map(wrappers, & &1.surface_id) == Enum.map(OrganizationAdmin.surfaces(), & &1.id)
    assert Enum.all?(wrappers, fn wrapper -> wrapper.live_view =~ "CadenceWeb." end)
    assert Enum.all?(wrappers, fn wrapper -> wrapper.component =~ ~r/^[A-Z][A-Za-z]+$/ end)
  end

  defp surface_contract(surface) do
    %{
      id: surface.id,
      purpose: surface.purpose,
      scope: surface.scope,
      placement: surface.placement,
      navigation: %{label: surface.navigation_label, order: surface.navigation_order},
      query: %{id: surface.query, version: surface.query_version},
      actions: surface.actions,
      exposed_module: surface.exposed_module
    }
  end
end
