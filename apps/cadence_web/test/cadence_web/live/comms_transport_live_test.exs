defmodule CadenceWeb.CommsTransportLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "transport routes" do
    test "lists transports and exposes primary transport navigation" do
      {conn, org, mission} = signed_in_org_and_mission()
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      assert has_element?(view, "#comms-transports-page")
      assert has_element?(view, "#new-transport-link")
      assert has_element?(view, "td", transport.display_name)
      assert has_element?(view, "details[open] a", "Transports")
      assert has_element?(view, "#transports[phx-update='stream']")

      page = render(view)
      assert page =~ "Durable byte-moving capabilities"
      refute page =~ "Link Assignment"
      refute page =~ "Link Template"
    end

    test "creates and shows a TCP transport" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      assert has_element?(view, "#comms-transport-new-page")
      assert has_element?(view, "#transport-form")
      assert html =~ "New Transport"
      assert html =~ "This setup does not mean a connection is currently open."

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#transport-form",
                 transport: %{
                   display_name: "AI&T TCP",
                   transport_kind: "tcp_socket",
                   tcp_mode: "connect",
                   direction_capability: "inbound",
                   host: "lab.example",
                   port: "5001",
                   framing_mode: "line_delimited",
                   reconnect_policy: "always",
                   tls_enabled: "false"
                 }
               )
               |> render_submit()

      assert target =~ "/missions/#{mission.mission_id}/comms/transports/"

      [transport] = Cadence.list_transports(org.organization_id, mission.mission_id)
      assert transport.display_name == "AI&T TCP"
      assert transport.direction_capability == :inbound
      assert transport.configuration["host"] == "lab.example"
      assert is_binary(transport.materialized_provider_profile_id)

      {:ok, show_view, show_html} = live(conn, target)
      assert has_element?(show_view, "#comms-transport-show-page")
      assert show_html =~ "AI&amp;T TCP"
      assert show_html =~ "Durable transport setup"
      assert show_html =~ "Runtime Links and Contacts"
      refute show_html =~ "Link Template"
    end

    test "rejects invalid TCP transport config" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      html =
        view
        |> form("#transport-form",
          transport: %{
            display_name: "Bad TCP",
            transport_kind: "tcp_socket",
            tcp_mode: "listen",
            direction_capability: "inbound",
            host: "0.0.0.0",
            port: "70000",
            framing_mode: "raw",
            tls_enabled: "false"
          }
        )
        |> render_submit()

      assert html =~ "Port must be an integer from 1 to 65535."
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/comms/transports")
    end
  end

  defp persist_transport!(organization_id, mission_id, display_name) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: display_name,
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
