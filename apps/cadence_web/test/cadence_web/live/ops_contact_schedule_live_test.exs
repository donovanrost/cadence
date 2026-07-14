defmodule CadenceWeb.OpsContactScheduleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderBooking, ProviderProfile}
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
      reserve: fn organization_id, mission_id, provider_profile_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_profile_id,
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

    render_async(view)

    assert has_element?(view, "#opportunity-opportunity-alpha")
    assert has_element?(view, "#reserve-opportunity-opportunity-alpha")

    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view)

    assert_received :provider_mutation
    assert has_element?(view, "#provider-reservations article")
    assert has_element?(view, "[id^=provider-reservation-provider_reservation_]")

    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view)

    refute_received :provider_mutation

    assert Cadence.list_provider_reservations(org.organization_id, mission.mission_id) |> length() ==
             1

    assert Cadence.list_scheduled_contacts(org.organization_id, mission.mission_id) |> length() ==
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
      reserve: fn organization_id, mission_id, provider_profile_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_profile_id,
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

    render_async(view)
    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view)

    assert has_element?(view, "#provider-reservations article", "pending")
    assert has_element?(view, "#provider-reservations article", "Not materialized")
    assert Cadence.list_scheduled_contacts(org.organization_id, mission.mission_id) == []
  end

  test "cancellation converges provider and Scheduled Contact state" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:ok, %{route: setup.route, opportunities: [opportunity]}}
      end,
      reserve: fn organization_id, mission_id, provider_profile_id, attrs ->
        ProviderBooking.reserve(
          organization_id,
          mission_id,
          provider_profile_id,
          attrs,
          client: FakeProviderClient
        )
      end,
      cancel: fn organization_id, mission_id, provider_reservation_id ->
        ProviderBooking.cancel(
          organization_id,
          mission_id,
          provider_reservation_id,
          client: FakeProviderClient
        )
      end,
      refresh_interval_ms: 60_000
    )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view)
    view |> element("#reserve-opportunity-opportunity-alpha") |> render_click()
    render_async(view)

    [reservation] = Cadence.list_provider_reservations(org.organization_id, mission.mission_id)
    cancel_selector = "#cancel-reservation-#{reservation.provider_reservation_id}"
    assert has_element?(view, cancel_selector)

    view |> element(cancel_selector) |> render_click()
    render_async(view)

    assert has_element?(view, "#provider-reservations article", "canceled")

    assert {:ok, contact} =
             Cadence.fetch_scheduled_contact(
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

    render_async(view)
    assert has_element?(view, "#contact-opportunity-count", "0")

    configure_live_deps(
      search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
        {:error, :provider_unavailable}
      end
    )

    view
    |> form("#contact-opportunity-search-form", contact_search: window)
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#contact-search-error")

    render_click(view, "reserve", %{"token" => "tampered"})
    assert Cadence.list_provider_reservations(org.organization_id, mission.mission_id) == []
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

    assert {:ok, endpoint} = Cadence.persist_source_endpoint(org.organization_id, endpoint)

    provider =
      ProviderProfile.new(%{
        provider_profile_id: "provider-#{suffix}",
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        configuration: valid_provider_configuration(),
        metadata: %{"display_name" => "Simulated Svalbard"}
      })

    assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

    path =
      PathTemplate.new(%{
        path_template_id: "path-#{suffix}",
        mission_id: mission.mission_id,
        path_id: "asteria-downlink",
        direction: :downlink,
        selection_role: :selected,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        metadata: %{"display_name" => "Primary telemetry downlink"}
      })

    assert {:ok, path} = Cadence.persist_path_template(org.organization_id, path)

    assignment =
      LinkAssignment.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path.path_template_id,
        path_template_version: path.version,
        direction: :downlink,
        selection_role: :selected,
        provider_profile_refs: path.provider_profile_refs
      })

    assert {:ok, _assignment} = Cadence.persist_link_assignment(org.organization_id, assignment)

    assert {:ok, %{routes: [route]}} =
             Cadence.list_ready_downlink_routes(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    %{spacecraft: spacecraft, endpoint: endpoint, provider: provider, path: path, route: route}
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
      "run_id" => "run-alpha",
      "spacecraft_id" => setup.route.provider_spacecraft_ref,
      "ground_station_id" => "station-svalbard",
      "antenna_id" => "svalbard-antenna-1",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => starts_at |> DateTime.add(600) |> DateTime.to_iso8601(),
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

  defp valid_provider_configuration do
    %{
      "adapter" => "tcp_socket",
      "mode" => "listen",
      "direction" => "downlink",
      "host" => "0.0.0.0",
      "port" => 4_100,
      "fixed_message_bytes" => 64,
      "framing" => %{"mode" => "fixed_size", "fixed_message_bytes" => 64},
      "scheduling" => %{
        "client" => "simulator_http",
        "base_url" => "http://simulator.test",
        "delivery_host" => "cadence.test",
        "run_id" => "run-alpha"
      }
    }
  end
end
