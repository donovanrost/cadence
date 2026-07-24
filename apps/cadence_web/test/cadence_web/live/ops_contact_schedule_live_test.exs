defmodule CadenceWeb.OpsContactScheduleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @async_timeout 1_000

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.RoutingRuleStore

  alias Cadence.Comms.{RoutingRule, Transport}
  alias Cadence.Contacts.{ProviderBooking, ProviderReservations, ProviderScheduling}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Management.Transports
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.OpsContactScheduleLive.OpportunityToken
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.get_env(:cadence_web, :ops_contact_schedule_live)

    on_exit(fn ->
      if previous do
        Application.put_env(:cadence_web, :ops_contact_schedule_live, previous)
      else
        Application.delete_env(:cadence_web, :ops_contact_schedule_live)
      end
    end)

    :ok
  end

  test "authenticated mission member mounts the active Contacts ops surface" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    assert has_element?(view, "#ops-contacts-page")
    assert has_element?(view, "#contact-opportunity-search-form")
    assert has_element?(view, "#provider-reservations")

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/contacts"][class*="text-primary"])
           )

    assert has_element?(
             view,
             ~s(#contact-readiness-empty a[href="/missions/#{mission.mission_id}/comms/routing"])
           )

    refute has_element?(view, "#provider-profile-form")
    assert org.organization_id != nil
  end

  test "authentication and organization membership are enforced at the router boundary", %{
    conn: conn
  } do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    outsider = TestFixtures.persist_user!()
    outsider_org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(outsider, outsider_org)
    outsider_conn = TestFixtures.member_conn(outsider)

    assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _message}}}} =
             live(outsider_conn, ~p"/missions/#{mission.mission_id}/ops/contacts")
  end

  test "search streams opportunities and signed reservation creates one durable attempt" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    test_pid = self()
    {window, opportunity} = opportunity_window(setup)

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:ok, %{route: setup.route, opportunities: [opportunity]}}
      end,
      reserve: fn organization_id, mission_id, provider_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          client: FakeProviderClient,
          on_reserve: fn _request -> send(test_pid, :provider_mutation) end
        )
      end,
      refresh_interval_ms: 60_000
    )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view, @async_timeout)

    assert has_element?(view, "#opportunity-opportunity-alpha")
    assert has_element?(view, "#reserve-opportunity-opportunity-alpha")

    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view, @async_timeout)

    assert_received :provider_mutation
    assert has_element?(view, "#provider-reservations article")
    assert has_element?(view, "[id^=provider-reservation-provider_reservation_]")

    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)

    assert has_element?(
             view,
             "#reservation-provider-#{reservation.provider_reservation_id}"
           )

    assert has_element?(view, "#reservation-service-#{reservation.provider_reservation_id}")
    assert has_element?(view, "#reservation-delivery-#{reservation.provider_reservation_id}")
    assert has_element?(view, "#reservation-transport-#{reservation.provider_reservation_id}")

    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view, @async_timeout)

    refute_received :provider_mutation

    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)
           |> length() ==
             1

    assert Cadence.Contacts.list_scheduled_contacts(org.organization_id, mission.mission_id)
           |> length() ==
             1
  end

  test "pending reservation remains visible without claiming a Scheduled Contact" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:ok, %{route: setup.route, opportunities: [opportunity]}}
      end,
      reserve: fn organization_id, mission_id, provider_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          client: FakeProviderClient,
          reserve_response: {:ok, provider_response(attrs, "pending")}
        )
      end,
      refresh_interval_ms: 60_000
    )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view, @async_timeout)
    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view, @async_timeout)

    assert has_element?(view, "#provider-reservations article", "pending")
    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)

    assert has_element?(
             view,
             "#reservation-contact-status-#{reservation.provider_reservation_id}",
             "pending"
           )

    assert has_element?(view, "#reservation-pass-phase-#{reservation.provider_reservation_id}")

    assert has_element?(
             view,
             "#reservation-delivery-status-#{reservation.provider_reservation_id}"
           )

    assert Cadence.Contacts.list_scheduled_contacts(org.organization_id, mission.mission_id) == []
  end

  test "cancellation converges provider and Scheduled Contact state" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:ok, %{route: setup.route, opportunities: [opportunity]}}
      end,
      reserve: fn organization_id, mission_id, provider_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          client: FakeProviderClient
        )
      end,
      cancel: fn organization_id, mission_id, provider_reservation_id ->
        {:ok, reservation} =
          ProviderReservations.fetch(
            organization_id,
            mission_id,
            provider_reservation_id
          )

        attrs = %{
          "idempotency_key" => reservation.idempotency_key,
          "opportunity_ref" => reservation.provider_opportunity_ref,
          "provider_spacecraft_ref" => reservation.provider_spacecraft_ref,
          "service_profile_ref" => reservation.service_profile_ref,
          "delivery_profile_ref" => reservation.delivery_profile_ref,
          "starts_at" => DateTime.to_iso8601(reservation.starts_at),
          "ends_at" => DateTime.to_iso8601(reservation.ends_at)
        }

        ProviderBooking.cancel(
          organization_id,
          mission_id,
          provider_reservation_id,
          client: FakeProviderClient,
          cancel_response: {:ok, provider_response(attrs, "canceled")}
        )
      end,
      refresh_interval_ms: 60_000
    )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view, @async_timeout)
    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view, @async_timeout)

    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)
    cancel_selector = "#cancel-reservation-#{reservation.provider_reservation_id}"
    assert has_element?(view, cancel_selector)

    view |> element(cancel_selector) |> render_click()
    render_async(view, @async_timeout)

    assert has_element?(view, "#provider-reservations article", "canceled")

    assert {:ok, contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               org.organization_id,
               mission.mission_id,
               reservation.scheduled_contact_id
             )

    assert contact.lifecycle_state == :canceled
  end

  test "invalid window, no results, provider error, and tampered token remain explicit" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, _opportunity} = opportunity_window(setup)

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:ok, %{route: setup.route, opportunities: []}}
      end
    )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    invalid = Map.put(window, "ends_at", window["starts_at"])

    view
    |> form("#contact-opportunity-search-form", contact_search: invalid)
    |> render_submit()

    assert has_element?(view, "#contact-search-error")

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view, @async_timeout)
    assert has_element?(view, "#contact-opportunity-count", "0")

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:error, :provider_unavailable}
      end
    )

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view, @async_timeout)
    assert has_element?(view, "#contact-search-error")

    render_click(view, "reserve", %{"token" => "tampered"})
    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id) == []
  end

  test "opportunity tokens expire and reject tampering" do
    token = OpportunityToken.sign(%{"mission_id" => "mission-alpha"})

    assert {:error, :invalid} = OpportunityToken.verify(token <> "tampered")
    assert {:error, :expired} = OpportunityToken.verify(token, max_age: -1)
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp persist_ready_comms!(org, mission) do
    suffix = System.unique_integer([:positive])
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Asteria")

    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-#{suffix}",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: "SIM-001",
        display_name: "Asteria provider identity"
      })

    assert {:ok, endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, endpoint)

    provider = persist_provider!(org.organization_id, mission.mission_id, suffix)

    transport =
      Transport.new(%{
        transport_id: "transport-#{suffix}",
        mission_id: mission.mission_id,
        display_name: "Simulator telemetry ingress",
        origin: :provider_managed,
        mission_provider_id: provider.provider_id,
        mission_provider_version: provider.version,
        service_profile_ref: %{"id" => "service-downlink", "version" => 3},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
      })

    assert {:ok, transport} =
             Transports.persist_transport(org.organization_id, transport)

    rule =
      RoutingRule.new(%{
        routing_rule_id: "routing-rule-#{suffix}",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Primary telemetry downlink",
        purpose_label: "Telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    assert {:ok, rule} =
             RoutingRuleStore.create_routing_rule(org.organization_id, rule)

    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    %{
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      transport: transport,
      rule: rule,
      route: route
    }
  end

  defp opportunity_window(setup) do
    starts_at = DateTime.utc_now() |> DateTime.add(300) |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 3_600)

    window = %{
      "spacecraft_id" => setup.spacecraft.spacecraft_id,
      "route_key" => setup.route.route_key,
      "starts_at" => Calendar.strftime(starts_at, "%Y-%m-%dT%H:%M:%S"),
      "ends_at" => Calendar.strftime(ends_at, "%Y-%m-%dT%H:%M:%S")
    }

    opportunity = %{
      "id" => "opportunity-alpha",
      "spacecraft_ref" => setup.route.provider_spacecraft_ref,
      "ground_station_ref" => "station-svalbard",
      "antenna_or_service_pool_ref" => "svalbard-antenna-1",
      "service_profile_ref" => setup.route.service_profile_ref["id"],
      "delivery_profile_ref" => setup.route.delivery_profile_ref["id"],
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(600) |> DateTime.to_iso8601(),
      "expires_at" => starts_at |> DateTime.add(-30) |> DateTime.to_iso8601(),
      "availability" => "available",
      "synthetic" => true,
      "extensions" => %{},
      "route_key" => setup.route.route_key
    }

    {window, opportunity}
  end

  defp provider_response(attrs, status) do
    %{
      "id" => "external-reservation",
      "provider_contact_ref" => "external-contact",
      "status" => status,
      "provider_status" => status,
      "pass_phase" => "scheduled",
      "delivery_state" => "pending",
      "client_reference" => attrs["idempotency_key"],
      "opportunity_ref" => attrs["opportunity_ref"],
      "spacecraft_ref" => attrs["provider_spacecraft_ref"],
      "service_profile_ref" => attrs["service_profile_ref"]["id"],
      "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
      "starts_at" => attrs["starts_at"],
      "ends_at" => attrs["ends_at"],
      "provider_evidence" => %{}
    }
  end

  defp configure_live_deps(overrides) do
    current = Application.get_env(:cadence_web, :ops_contact_schedule_live, [])

    Application.put_env(
      :cadence_web,
      :ops_contact_schedule_live,
      Keyword.merge(current, overrides)
    )
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      MissionProvider.new(%{
        provider_id: "provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Simulated Svalbard",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-alpha",
        last_validated_at: now,
        last_synced_at: now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: provider_inventory()
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-downlink",
            "version" => 3,
            "display_name" => "Realtime TT&C downlink",
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
            "display_name" => "Cadence primary ingress",
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
              "frame_bytes" => 1115
            }
          }
        ]
      }
    }
  end
end
