defmodule CadenceWeb.CommsTransportLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.Transport
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "primary",
        display_name: "Primary Mission"
      )

    {TestFixtures.member_conn(user), organization, mission}
  end

  describe "transport routes" do
    test "lists transports with origin, operator summary, and readiness" do
      {conn, organization, mission} = signed_in_org_and_mission()
      transport = persist_transport!(organization.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      assert has_element?(view, "#comms-transports-page")
      assert has_element?(view, "#new-transport-link")
      assert has_element?(view, "#transports[phx-update='stream']")
      assert has_element?(view, "td", transport.display_name)
      assert has_element?(view, "#transport-origin-#{transport.transport_id}", "Direct")
      assert has_element?(view, "#transport-provider-#{transport.transport_id}", "Cadence")
      assert has_element?(view, "#transport-readiness-#{transport.transport_id}", "Configured")
      assert has_element?(view, "details[open] a", "Transports")
      refute has_element?(view, "#comms-transports-page", "Link Assignment")
      refute has_element?(view, "#comms-transports-page", "Link Template")
    end

    test "search narrows the transport list" do
      {conn, organization, mission} = signed_in_org_and_mission()
      _lab = persist_transport!(organization.organization_id, mission.mission_id, "Lab TCP")

      _ground =
        persist_transport!(organization.organization_id, mission.mission_id, "Ground Uplink")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      view
      |> element("#transports-toolbar form")
      |> render_change(%{"q" => "ground"})

      assert has_element?(view, "td", "Ground Uplink")
      refute has_element?(view, "td", "Lab TCP")

      view
      |> element("#transports-toolbar form")
      |> render_change(%{"q" => "no-such-transport"})

      assert has_element?(
               view,
               "#comms-transports-page",
               "No transports match the current search."
             )
    end

    test "progressively configures and shows a direct TCP transport" do
      {conn, organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      assert has_element?(view, "#comms-transport-new-page")
      assert has_element?(view, "#transport-form")
      assert has_element?(view, "#transport-identity-section")
      assert has_element?(view, "#transport-origin-section")
      assert has_element?(view, "#transport-source-section")
      assert has_element?(view, "#transport-capability-section")

      assert has_element?(
               view,
               "#transport-direct-configuration[data-extension-presentation='transport_kind']"
             )

      assert has_element?(view, "#transport-capability-section-fields")
      assert has_element?(view, "#transport-framing-section")
      assert has_element?(view, "#transport-reliability-section")
      assert has_element?(view, "#transport-summary-section")
      assert has_element?(view, "#transport-admin-diagnostics")
      assert has_element?(view, "#create-transport-button[disabled]")
      refute has_element?(view, "#transport-provider")

      refute has_element?(
               view,
               "#transport-direct-configuration-input-frame-size"
             )

      view
      |> form("#transport-form",
        transport: %{
          display_name: "AI&T TCP",
          origin: "direct",
          transport_kind: "tcp_socket",
          tcp_mode: "connect",
          direction_capability: "inbound",
          host: "lab.example",
          port: "5001",
          framing_mode: "fixed_size",
          tls_enabled: "false"
        }
      )
      |> render_change()

      assert has_element?(view, "#transport-direct-configuration-input-frame-size")
      assert has_element?(view, "#transport-direct-configuration-input-reconnect-policy")

      view
      |> form("#transport-form", transport: direct_transport_params())
      |> render_change()

      assert has_element?(view, "#create-transport-button:not([disabled])")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#transport-form", transport: direct_transport_params())
               |> render_submit()

      [transport] =
        TransportStore.list_transports(
          organization.organization_id,
          mission.mission_id
        )

      assert transport.display_name == "AI&T TCP"
      assert transport.origin == :direct
      assert transport.direction_capability == :inbound
      assert transport.configuration["host"] == "lab.example"
      assert is_binary(transport.materialized_provider_profile_id)

      {:ok, show_view, _show_html} = live(conn, target)
      assert has_element?(show_view, "#comms-transport-show-page")
      assert has_element?(show_view, "#transport-origin-summary", "Direct")
      assert has_element?(show_view, "#transport-provider-summary", "Cadence")
      assert has_element?(show_view, "#transport-readiness-summary", "Configured")
      assert has_element?(show_view, "#transport-admin-diagnostics-json")
      assert has_element?(show_view, "#transport-versions[phx-update='stream']")
      refute has_element?(show_view, "#comms-transport-show-page", "Link Template")
    end

    test "derives a provider-managed Transport from compatible synchronized profiles" do
      {conn, organization, mission} = signed_in_org_and_mission()
      provider = persist_ready_provider!(organization.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      view
      |> form("#transport-form",
        transport: %{
          display_name: "Provider Downlink",
          origin: "provider_managed"
        }
      )
      |> render_change()

      assert has_element?(view, "#transport-provider")
      assert has_element?(view, "#transport-kind-provider-managed[value='tcp_socket']")
      assert has_element?(view, "#transport-service-profile")
      assert has_element?(view, "#transport-delivery-profile")
      assert has_element?(view, "#transport-provider-operator-summary", "Streaming to Cadence")
      assert has_element?(view, "#transport-provider-derived-section")
      assert has_element?(view, "#transport-provider-derived-configuration", "127.0.0.1:5100")
      assert has_element?(view, "#create-transport-button:not([disabled])")
      refute has_element?(view, "#transport-direct-configuration")
      refute has_element?(view, "#transport-framing-section")
      refute has_element?(view, "#transport-reliability-section")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#transport-form",
                 transport: %{
                   display_name: "Provider Downlink",
                   origin: "provider_managed",
                   mission_provider_id: provider.provider_id
                 }
               )
               |> render_submit()

      [transport] =
        TransportStore.list_transports(
          organization.organization_id,
          mission.mission_id
        )

      assert transport.origin == :provider_managed
      assert transport.mission_provider_id == provider.provider_id
      assert transport.mission_provider_version == provider.version
      assert transport.service_profile_ref == %{"id" => "service-downlink", "version" => 3}
      assert transport.delivery_profile_ref == %{"id" => "delivery-cadence", "version" => 7}
      assert transport.configuration["host"] == "127.0.0.1"

      {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

      assert has_element?(
               list_view,
               "#transport-origin-#{transport.transport_id}",
               "Provider managed"
             )

      assert has_element?(
               list_view,
               "#transport-provider-#{transport.transport_id}",
               provider.display_name
             )

      assert has_element?(
               list_view,
               "#transport-operator-summary-#{transport.transport_id}",
               "Streaming to Cadence"
             )

      assert has_element?(list_view, "#transport-readiness-#{transport.transport_id}", "Ready")

      {:ok, show_view, _show_html} = live(conn, target)
      assert has_element?(show_view, "#transport-origin-summary", "Provider managed")
      assert has_element?(show_view, "#transport-provider-summary", provider.display_name)
      assert has_element?(show_view, "#transport-operator-summary", "Streaming to Cadence")
      assert has_element?(show_view, "#transport-readiness-summary", "Ready")

      assert has_element?(
               show_view,
               ~s|a[href="/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"]|
             )
    end

    test "keeps unvalidated providers out of the selectable provider flow" do
      {conn, organization, mission} = signed_in_org_and_mission()
      provider = persist_unvalidated_provider!(organization.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      view
      |> form("#transport-form",
        transport: %{display_name: "Downlink", origin: "provider_managed"}
      )
      |> render_change()

      assert has_element?(view, "#transport-provider-empty-state")

      assert has_element?(
               view,
               "#transport-provider option[value='#{provider.provider_id}'][disabled]"
             )

      assert has_element?(view, "#create-transport-button[disabled]")
    end

    test "renders a stable validation outcome for invalid direct TCP setup" do
      {conn, _organization, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

      view
      |> form("#transport-form",
        transport: %{
          display_name: "Bad TCP",
          origin: "direct",
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

      assert has_element?(
               view,
               "#transport-form-error",
               "Port must be an integer from 1 to 65535."
             )

      assert TransportStore.list_transports(
               mission.organization_id,
               mission.mission_id
             ) == []
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/comms/transports")
    end
  end

  defp direct_transport_params do
    %{
      display_name: "AI&T TCP",
      origin: "direct",
      transport_kind: "tcp_socket",
      tcp_mode: "connect",
      direction_capability: "inbound",
      host: "lab.example",
      port: "5001",
      framing_mode: "fixed_size",
      frame_size: "64",
      reconnect_policy: "always",
      tls_enabled: "false"
    }
  end

  defp persist_transport!(organization_id, mission_id, display_name) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: display_name,
        origin: :direct,
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

    assert {:ok, persisted} =
             TransportStore.persist_transport(organization_id, transport)

    persisted
  end

  defp persist_ready_provider!(organization_id, mission_id) do
    provider = provider_fixture(mission_id, ready?: true)
    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp persist_unvalidated_provider!(organization_id, mission_id) do
    provider = provider_fixture(mission_id, ready?: false)
    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp provider_fixture(mission_id, opts) do
    ready? = Keyword.fetch!(opts, :ready?)
    now = ~U[2026-07-14 12:00:00.000000Z]

    MissionProvider.new(%{
      mission_id: mission_id,
      display_name: if(ready?, do: "Ground Network Simulator", else: "Unvalidated Simulator"),
      provider_type: :simulator,
      base_url: "http://127.0.0.1:4101",
      credential_ref: "config://simulator",
      environment_ref: "local",
      last_validated_at: if(ready?, do: now),
      last_synced_at: if(ready?, do: now),
      metadata: if(ready?, do: %{"control_plane" => %{"status" => "healthy"}}, else: %{}),
      inventory_sync_document: if(ready?, do: provider_inventory(), else: %{})
    })
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-downlink",
            "version" => 3,
            "display_name" => "Realtime telemetry",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence",
            "version" => 7,
            "display_name" => "Cadence ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-downlink"],
            "state" => "ready",
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "mode" => "provider_connects",
              "host" => "127.0.0.1",
              "port" => 5100,
              "framing_family" => "ccsds_tm",
              "frame_bytes" => 1115,
              "endpoint_health" => "healthy"
            }
          }
        ]
      }
    }
  end
end
