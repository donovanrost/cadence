defmodule CadenceWeb.ApplicationContributions.OrganizationAdminTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.ApplicationContributions.{
    OrganizationAdmin,
    OrganizationAdminAction,
    OrganizationAdminQuery
  }

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

  test "binds every contribution to a Phoenix-owned query and renderer component" do
    for surface <- OrganizationAdmin.surfaces() do
      assert {:ok, query} = OrganizationAdminQuery.fetch(surface.query)
      assert query.surface_id == surface.id
      assert surface.component =~ ~r/^[A-Z][A-Za-z]+$/
    end
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
end
