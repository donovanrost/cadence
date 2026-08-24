defmodule CadenceWeb.SpacecraftApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  defp setup_session do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization, slug: "primary", display_name: "Primary")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission,
      organization: organization,
      scope: scope
    }
  end

  test "projects the page, pinned profile, and application card through exact LiveVue props" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    assert has_element?(view, "#spacecraft-applications-page")
    assert has_element?(view, "#spacecraft-applications-component")
    assert has_element?(view, "#spacecraft-applications-page > header h1", "Applications")

    assert has_element?(
             view,
             "#spacecraft-applications-page > header p",
             "Install profile-declared product applications and open their host-rendered workspaces."
           )

    assert has_element?(
             view,
             "nav[aria-label='Breadcrumb'] a[href='/missions/#{context.mission.mission_id}']",
             "Primary"
           )

    assert has_element?(
             view,
             "nav[aria-label='Breadcrumb'] a[href='/missions/#{context.mission.mission_id}/spacecraft']",
             "Spacecraft"
           )

    assert has_element?(
             view,
             "nav[aria-label='Breadcrumb'] a[href='/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}']",
             "Nova-1"
           )

    assert has_element?(
             view,
             "nav[aria-label='Breadcrumb'] span[class~='text-primary/90']",
             "Applications"
           )

    assert has_element?(
             view,
             "#spacecraft-applications-page > header a[href='/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness']",
             "Readiness"
           )

    sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")

    spacecraft_nav =
      Enum.find(
        sidebar.props["presentation"]["navigation"]["items"],
        &(&1["key"] == "spacecraft")
      )

    assert spacecraft_nav["attrs"]["href"] ==
             "/missions/#{context.mission.mission_id}/spacecraft"

    assert spacecraft_nav["label"] == "Spacecraft"
    assert spacecraft_nav["class"] =~ "bg-primary/10"

    assert has_element?(view, "#user-menu-desktop")

    vue = spacecraft_applications_vue(view)

    assert vue.component == "SpacecraftApplications"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.handlers["install"] == JS.push("install_application")
    assert vue.handlers["disable"] == JS.push("disable_application")
    assert vue.handlers["uninstall"] == JS.push("uninstall_application")

    assert vue.props["profile"] == %{
             "kind" => "pinned",
             "id" => "spacecraft-applications-profile",
             "label" => "Pinned Profile",
             "display_name" => "Aurora Bus",
             "version" => 1,
             "status" => %{"tone" => "ready", "label" => "Current"}
           }

    assert vue.props["applications"] == [
             %{
               "id" => "spacecraft-application-telemetry_decom",
               "application_key" => "telemetry_decom",
               "application_version" => 1,
               "display_name" => "Telemetry Decom",
               "description" =>
                 "Bind packet fields and decode selected inputs into named telemetry points.",
               "lifecycle_state" => nil,
               "installable" => true,
               "manageable" => false,
               "uninstallable" => false,
               "scope_label" => "Application",
               "manage_path" =>
                 "/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom",
               "status" => %{
                 "state" => "not_installed",
                 "label" => "Not installed",
                 "tone" => "info",
                 "facts" => [
                   %{
                     "id" => "workspace",
                     "label" => "Workspace",
                     "value" => "Install to configure"
                   },
                   %{
                     "id" => "application_version",
                     "label" => "Application version",
                     "value" => "v1"
                   }
                 ]
               },
               "install_action" => %{
                 "id" => "install-spacecraft-application-telemetry_decom",
                 "action_id" => "install",
                 "label" => "Install",
                 "variant" => "primary",
                 "effect" => "durable",
                 "execution" => "immediate",
                 "confirmation" => nil
               },
               "disable_action" => nil,
               "uninstall_action" => nil,
               "unavailable_message" => nil
             }
           ]
  end

  test "preserves pinned profile drift plus deterministic custom application order and safe IDs" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission,
        display_name: "Aurora Bus",
        applications: %{
          "telemetry_decom" => %{},
          "custom:thermal-alerting" => %{
            "display_name" => "Thermal Alerting",
            "description" => "Mission-owned temperature monitoring."
          }
        }
      )

    %Cadence.SpacecraftType{} = profile

    latest_profile = %Cadence.SpacecraftType{
      profile
      | version: profile.version + 1,
        display_name: "Aurora Bus Next"
    }

    assert {:ok, _latest_profile} =
             Cadence.SpacecraftTypeStore.persist_spacecraft_type(
               context.organization.organization_id,
               latest_profile
             )

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))
    props = spacecraft_applications_vue(view).props

    assert props["profile"] == %{
             "kind" => "pinned",
             "id" => "spacecraft-applications-profile",
             "label" => "Pinned Profile",
             "display_name" => "Aurora Bus",
             "version" => 1,
             "status" => %{"tone" => "attention", "label" => "Profile drift"}
           }

    assert Enum.map(props["applications"], & &1["application_key"]) == [
             "custom:thermal-alerting",
             "telemetry_decom"
           ]

    assert Enum.map(props["applications"], & &1["id"]) == [
             "spacecraft-application-custom-thermal-alerting",
             "spacecraft-application-telemetry_decom"
           ]

    custom = application_prop(view, "custom:thermal-alerting")

    assert custom["display_name"] == "Thermal Alerting"
    assert custom["description"] == "Mission-owned temperature monitoring."
    assert custom["scope_label"] == "Application"

    assert custom["status"] == %{
             "state" => "unavailable",
             "label" => "Unavailable",
             "tone" => "blocked",
             "facts" => []
           }

    refute custom["installable"]
    refute custom["manageable"]
    assert is_nil(custom["install_action"])
    assert is_nil(custom["disable_action"])
    assert is_nil(custom["uninstall_action"])

    assert custom["unavailable_message"] ==
             "This application is not available for installation in this deployment."
  end

  test "refreshes manage, disable, uninstall, and reinstall lifecycle DTOs after each hook" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    render_hook(view, "install_application", %{"key" => "telemetry_decom"})

    application = application_prop(view, "telemetry_decom")
    assert application["lifecycle_state"] == "installed"
    assert application["manageable"]
    assert is_nil(application["install_action"])

    assert application["manage_path"] ==
             "/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"

    assert application["disable_action"] == %{
             "id" => "disable-spacecraft-application-telemetry_decom",
             "action_id" => "disable",
             "label" => "Disable workspace",
             "variant" => "secondary",
             "effect" => "durable",
             "execution" => "immediate",
             "confirmation" => %{
               "title" => "Disable application workspace?",
               "message" =>
                 "Workspace access and configuration editing will stop. Existing configuration is retained, and active runtime state is unchanged until a separately governed mission change is applied.",
               "confirm_label" => "Disable workspace",
               "tone" => "attention",
               "prompt" =>
                 "Disable application workspace?\n\nWorkspace access and configuration editing will stop. Existing configuration is retained, and active runtime state is unchanged until a separately governed mission change is applied."
             }
           }

    assert application["uninstall_action"] == %{
             "id" => "uninstall-spacecraft-application-telemetry_decom",
             "action_id" => "uninstall",
             "label" => "Uninstall",
             "variant" => "danger",
             "effect" => "durable",
             "execution" => "immediate",
             "confirmation" => %{
               "title" => "Uninstall host access?",
               "message" =>
                 "The durable installation record and application configuration will be retained. Active runtime state is unchanged.",
               "confirm_label" => "Uninstall",
               "tone" => "danger",
               "prompt" =>
                 "Uninstall host access?\n\nThe durable installation record and application configuration will be retained. Active runtime state is unchanged."
             }
           }

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Application is available in the host workspace."
           )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    render_hook(view, "disable_application", %{"key" => "telemetry_decom"})

    application = application_prop(view, "telemetry_decom")
    assert application["lifecycle_state"] == "disabled"
    refute application["manageable"]
    assert application["install_action"]["label"] == "Enable"
    assert application["uninstall_action"]["label"] == "Uninstall"

    assert application["status"] == %{
             "state" => "disabled",
             "label" => "Disabled",
             "tone" => "blocked",
             "facts" => [
               %{"id" => "workspace", "label" => "Workspace", "value" => "Enable to manage"},
               %{
                 "id" => "application_version",
                 "label" => "Application version",
                 "value" => "v1"
               }
             ]
           }

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Application workspace disabled. Active runtime state is unchanged."
           )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    render_hook(view, "uninstall_application", %{"key" => "telemetry_decom"})

    application = application_prop(view, "telemetry_decom")
    assert application["lifecycle_state"] == "uninstalled"
    assert application["install_action"]["label"] == "Reinstall"
    assert is_nil(application["uninstall_action"])

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Application uninstalled. Its configuration and runtime state were preserved."
           )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    render_hook(view, "install_application", %{"key" => "telemetry_decom"})

    application = application_prop(view, "telemetry_decom")
    assert application["lifecycle_state"] == "installed"
    assert application["manageable"]
    assert application["disable_action"]["label"] == "Disable workspace"
  end

  test "keeps a retained application visible and reinstallable without a pinned profile" do
    context = setup_session()
    spacecraft = TestFixtures.persist_spacecraft!(context.mission, display_name: "Nova-1")
    host_context = HostContext.spacecraft(context.mission.mission_id, spacecraft.spacecraft_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(
               context.scope,
               host_context,
               "telemetry_decom"
             )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    assert spacecraft_applications_vue(view).props["profile"]["kind"] == "missing"
    assert application_prop(view, "telemetry_decom")["manageable"]

    render_hook(view, "uninstall_application", %{"key" => "telemetry_decom"})
    assert application_prop(view, "telemetry_decom")["install_action"]["label"] == "Reinstall"

    inventory_path = inventory_path(context.mission, spacecraft)

    assert {:error,
            {:live_redirect,
             %{
               to: ^inventory_path,
               flash: %{"error" => "Reinstall the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
             )

    render_hook(view, "install_application", %{"key" => "telemetry_decom"})
    assert application_prop(view, "telemetry_decom")["manageable"]
  end

  test "preserves missing-profile and empty pinned-profile presentation conditions" do
    context = setup_session()
    spacecraft = TestFixtures.persist_spacecraft!(context.mission, display_name: "Nova-1")

    {:ok, missing_view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))
    missing_props = spacecraft_applications_vue(missing_view).props

    assert missing_props == %{
             "profile" => %{
               "kind" => "missing",
               "id" => "spacecraft-applications-no-profile",
               "label" => "Spacecraft Profile",
               "title" => "No profile selected",
               "description" =>
                 "Select a Spacecraft Profile before installing profile-declared applications.",
               "action" => %{
                 "label" => "Select profile",
                 "path" =>
                   "/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
               }
             },
             "applications" => []
           }

    empty_profile =
      TestFixtures.persist_spacecraft_profile!(context.mission,
        display_name: "Empty Bus",
        applications: %{}
      )

    profiled_spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-2",
        spacecraft_type_id: empty_profile.spacecraft_type_id,
        spacecraft_type_version: empty_profile.version
      )

    {:ok, profiled_view, _html} =
      live(context.conn, inventory_path(context.mission, profiled_spacecraft))

    profiled_props = spacecraft_applications_vue(profiled_view).props
    assert profiled_props["profile"]["kind"] == "pinned"
    assert profiled_props["profile"]["id"] == "spacecraft-applications-profile"
    assert profiled_props["applications"] == []
  end

  test "denies installation outside the declared-or-retained spacecraft policy" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission,
        display_name: "Empty Bus",
        applications: %{}
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} = live(context.conn, inventory_path(context.mission, spacecraft))

    render_hook(view, "install_application", %{"key" => "telemetry_decom"})

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Application is neither declared by this profile nor retained at this scope."
           )

    assert spacecraft_applications_vue(view).props["applications"] == []
  end

  test "unknown application detail redirects back to the applications list" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    assert {:error, {:live_redirect, %{to: path, flash: %{"error" => "Application not found."}}}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/not_real"
             )

    assert path == inventory_path(context.mission, spacecraft)
  end

  test "known but uninstalled application detail redirects to the inventory" do
    context = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(context.mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(context.mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    assert {:error,
            {:live_redirect,
             %{
               to: path,
               flash: %{"error" => "Install the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
             )

    assert path == inventory_path(context.mission, spacecraft)
  end

  test "missing spacecraft and unauthenticated inventory requests preserve router redirects" do
    context = setup_session()
    spacecraft_list_path = ~p"/missions/#{context.mission.mission_id}/spacecraft"

    assert {:error,
            {:redirect,
             %{
               to: ^spacecraft_list_path,
               flash: %{"error" => "Spacecraft not found."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/spacecraft/missing-spacecraft/applications"
             )

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               build_conn(),
               ~p"/missions/mission-test/spacecraft/spacecraft-test/applications"
             )
  end

  defp spacecraft_applications_vue(view) do
    LiveVue.Test.get_vue(view, id: "spacecraft-applications-component")
  end

  defp application_prop(view, application_key) do
    view
    |> spacecraft_applications_vue()
    |> Map.fetch!(:props)
    |> Map.fetch!("applications")
    |> Enum.find(&(&1["application_key"] == application_key))
  end

  defp inventory_path(mission, spacecraft) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end
end
