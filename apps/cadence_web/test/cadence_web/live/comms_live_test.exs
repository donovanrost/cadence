defmodule CadenceWeb.CommsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderProfile
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "overview" do
    test "renders the comms setup overview and section navigation" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-overview-page")
      assert has_element?(view, "#comms-transports")
      assert render(view) =~ "Transport"
      assert has_element?(view, "#comms-validation-page")
      assert has_element?(view, "#comms-validation-transport-setup")
      assert has_element?(view, "#comms-validation-advanced-runtime-identity")
      refute has_element?(view, "details[open] a", "Providers")
    end

    test "inlined validation surface includes spacecraft setup findings" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-validation-spacecraft-setup")
      assert render(view) =~ "Findings"
      assert render(view) =~ "Spacecraft Setup"
      assert render(view) =~ "Spacecraft Profile"
      refute render(view) =~ "Link Assignments"
      refute render(view) =~ "Link Template"
    end

    test "inlined validation surface includes routing setup findings" do
      {conn, org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs Routing")
      _transport = persist_transport!(org.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-validation-routing-setup")
      assert render(view) =~ "No Routing Rules configured"
      assert render(view) =~ ~p"/missions/#{mission.mission_id}/comms/routing/new"
    end

    test "expands the Comms section and marks Overview active on /comms" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "details[open] summary", "Comms")

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"].text-primary|,
               "Overview"
             )

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"] span.bg-primary|
             )

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms/validation"]|,
               "Validation"
             )
    end

    test "renders dedicated validation page grouped by setup owner" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(view, "#comms-validation-page")
      assert has_element?(view, "#comms-validation-spacecraft-setup")
      assert has_element?(view, "#comms-validation-transport-setup")
      assert render(view) =~ "Spacecraft Setup"
      assert render(view) =~ "Transport Setup"

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms/validation"].text-primary|,
               "Validation"
             )

      refute render(view) =~ "Link Template"
      refute render(view) =~ "Link Assignments"
    end

    test "leaves the Comms section collapsed when not on a /comms route" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert has_element?(view, "details:not([open]) summary", "Comms")
      refute has_element?(view, "details[open] summary", "Comms")
    end
  end

  describe "providers" do
    test "rejects invalid provider TCP configuration" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

      html =
        view
        |> form("#provider-profile-form",
          provider_profile: %{
            display_name: "Bad Provider",
            tcp_mode: "connect",
            direction: "downlink",
            host: "ground.example",
            port: "70000",
            framing_mode: "raw",
            reconnect_policy: "always",
            tls_enabled: "false"
          }
        )
        |> render_submit()

      assert html =~ "Port must be an integer from 1 to 65535."
    end

    test "creates TCP client providers with reconnect and TLS settings" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

      assert html =~ "TCP Mode"
      assert html =~ "Configuration Preview"

      assert {:error, {:live_redirect, %{to: _target}}} =
               view
               |> form("#provider-profile-form",
                 provider_profile: %{
                   display_name: "TCP Client Provider",
                   tcp_mode: "connect",
                   direction: "uplink",
                   host: "ground.example",
                   port: "6000",
                   framing_mode: "line_delimited",
                   reconnect_policy: "always",
                   tls_enabled: "true"
                 }
               )
               |> render_submit()

      [provider] = Cadence.list_provider_profiles(org.organization_id, mission.mission_id)
      assert provider.configuration["mode"] == "connect"
      assert provider.configuration["direction"] == "uplink"
      assert provider.configuration["host"] == "ground.example"
      assert provider.configuration["port"] == 6000
      assert provider.configuration["framing"] == %{"mode" => "line_delimited"}
      assert provider.configuration["reconnect"] == %{"policy" => "always"}
      assert provider.configuration["tls"] == %{"enabled" => true}
    end

    test "shows and versions TCP providers" do
      {conn, org, mission} = signed_in_org_and_mission()

      provider =
        ProviderProfile.new(%{
          mission_id: mission.mission_id,
          adapter_key: :tcp_socket,
          configuration: %{
            "adapter" => "tcp_socket",
            "mode" => "listen",
            "direction" => "downlink",
            "host" => "127.0.0.1",
            "port" => 5000,
            "framing" => %{"mode" => "raw"},
            "tls" => %{"enabled" => false},
            "reconnect" => %{"policy" => "on_disconnect"}
          },
          metadata: %{"display_name" => "TCP Provider"}
        })

      assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

      {:ok, show_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}"
        )

      assert has_element?(show_view, "#comms-provider-profile-show-page")
      assert html =~ "TCP Provider"
      assert html =~ "127.0.0.1:5000"
      assert html =~ "Version History"

      {:ok, version_view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}/new-version"
        )

      assert html =~ "New Provider Version"

      assert has_element?(
               version_view,
               "input[name='provider_profile[port]'][value='5000']"
             )

      assert {:error, {:live_redirect, %{to: target}}} =
               version_view
               |> form("#provider-profile-form",
                 provider_profile: %{
                   display_name: "TCP Provider",
                   tcp_mode: "listen",
                   direction: "downlink",
                   host: "127.0.0.1",
                   port: "5100",
                   framing_mode: "fixed_size",
                   frame_size: "32",
                   reconnect_policy: "on_disconnect",
                   tls_enabled: "true"
                 }
               )
               |> render_submit()

      assert target ==
               ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_profile_id}"

      [v2, v1] =
        Cadence.list_provider_profile_versions(
          org.organization_id,
          mission.mission_id,
          provider.provider_profile_id
        )

      assert v1.version == 1
      assert v2.version == 2
      assert v2.configuration["port"] == 5100
      assert v2.configuration["fixed_message_bytes"] == 32
      assert v2.configuration["tls"] == %{"enabled" => true}
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/some-mission-id/comms")
    end
  end

  defp persist_transport!(organization_id, mission_id) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, persisted} = Cadence.persist_transport(organization_id, transport)
    persisted
  end
end
