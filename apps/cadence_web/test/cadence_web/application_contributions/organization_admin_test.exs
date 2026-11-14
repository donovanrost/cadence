defmodule Cadence.Applications.OrganizationAdminTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{
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
      navigation: %{label: "Overview", order: 10, fallback_path: "/"},
      query: %{id: "cadence.organization.home", version: 1},
      actions: [],
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
    }
  ]

  test "contributes every post-auth organization surface (L7: platform admin, L13: provider accounts are in the console)" do
    assert :ok = OrganizationAdmin.validate()

    assert Enum.map(OrganizationAdmin.surfaces(), & &1.id) == [
             "organization_home",
             "notifications_bell"
           ]

    assert Enum.map(OrganizationAdmin.surfaces(), &{&1.id, &1.scope}) == [
             {"organization_home", :organization},
             {"notifications_bell", :user}
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

  test "publishes the exact 1-row surface action ledger" do
    expected = [{"notifications_bell", 1, "mark_notification_read"}]

    surface_pairs =
      OrganizationAdmin.surfaces()
      |> Enum.flat_map(fn surface -> Enum.map(surface.actions, &{surface.id, 1, &1}) end)

    action_pairs = Enum.map(OrganizationAdminAction.all(), &{&1.surface_id, &1.version, &1.id})

    assert surface_pairs == expected
    assert action_pairs == expected
    assert length(OrganizationAdmin.definition().actions) == 1
  end

  test "rejects duplicate provider binding rows" do
    [first | _rest] = OrganizationAdminAction.all()

    assert {:error, :duplicate_action_bindings} =
             OrganizationAdminAction.validate_bindings(OrganizationAdminAction.all() ++ [first])
  end

  test "keeps sign-in, invitations, bootstrap and admin mode host-owned" do
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

  defp navigation(%{fallback_path: path} = surface),
    do: %{label: surface.navigation_label, order: surface.navigation_order, fallback_path: path}

  defp navigation(surface),
    do: %{label: surface.navigation_label, order: surface.navigation_order}

  defp surface_contract(surface) do
    %{
      id: surface.id,
      purpose: surface.purpose,
      scope: surface.scope,
      placement: surface.placement,
      navigation: navigation(surface),
      query: %{id: surface.query, version: surface.query_version},
      actions: surface.actions,
      exposed_module: surface.exposed_module
    }
  end
end
