defmodule CadenceWeb.OpsContactScheduleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @async_timeout 1_000

  @moduletag :config

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 2, track_async_view: 1]

  import Phoenix.LiveViewTest, except: [render_async: 2]

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
  alias CadenceWeb.OpsContactScheduleLive.{LiveDeps, OpportunityToken}
  alias CadenceWeb.TestFixtures

  test "authenticated mission member mounts the active Contacts ops surface" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    vue = contact_schedule_vue(view)

    assert vue.component == "OpsContactSchedule"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props["page"] == empty_page_props(mission.mission_id)
    assert vue.props["search"]["id"] == "contact-opportunity-search-form"
    assert vue.props["readiness"]["id"] == "contact-readiness-empty"

    assert vue.props["readiness"]["action"]["href"] ==
             "/missions/#{mission.mission_id}/comms/routing"

    assert vue.props["busy"] == %{"keys" => [], "actions" => %{}}

    assert stream_mutations(vue, "contact_records") == [
             ["replace", "/contact_records", []]
           ]

    assert stream_mutations(vue, "opportunities") == [["replace", "/opportunities", []]]

    assert stream_mutations(vue, "provider_reservations") == [
             ["replace", "/provider_reservations", []]
           ]

    assert_json_safe(vue)

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/contacts"][class*="text-primary"])
           )

    refute has_element?(view, "#provider-profile-form")
    assert org.organization_id != nil
  end

  test "page and form props preserve exact defaults, options, route reassignment, and readiness" do
    {conn, _user, _org, mission} = signed_in_org_and_mission()

    spacecraft = [
      %{spacecraft_id: "spacecraft-alpha", display_name: "Asteria"},
      %{spacecraft_id: "spacecraft-beta", display_name: "Borealis"},
      %{spacecraft_id: "spacecraft-gamma", display_name: "Cygnus"}
    ]

    routes = %{
      "spacecraft-alpha" => [search_route("route-alpha", "Alpha provider")],
      "spacecraft-beta" => [search_route("route-beta", "Beta provider")]
    }

    live_deps =
      LiveDeps.new(
        list_spacecraft: fn _organization_id, _mission_id -> spacecraft end,
        list_ready_routes: fn _organization_id, _mission_id, spacecraft_id ->
          case Map.get(routes, spacecraft_id, []) do
            [] -> {:ok, %{routes: [], findings: [%{message: "Publish an inbound route."}]}}
            ready_routes -> {:ok, %{routes: ready_routes, findings: []}}
          end
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    mounted = contact_schedule_vue(view)
    form = mounted.props["search"]

    assert form["fields"] ==
             search_fields_props(spacecraft, [search_route("route-alpha", "Alpha provider")])

    assert form["values"]["spacecraft_id"] == "spacecraft-alpha"
    assert form["values"]["route_key"] == "route-alpha"

    assert form["submit"] == %{
             "id" => "search-contact-opportunities",
             "label" => "Search opportunities",
             "busy" => false,
             "disabled" => false
           }

    assert {:ok, starts_at} = NaiveDateTime.from_iso8601(form["values"]["starts_at"])
    assert {:ok, ends_at} = NaiveDateTime.from_iso8601(form["values"]["ends_at"])
    assert NaiveDateTime.diff(ends_at, starts_at) == 6 * 60 * 60
    assert mounted.props["readiness"] == nil

    reassigned_values = %{
      "spacecraft_id" => "spacecraft-beta",
      "route_key" => "stale-route",
      "starts_at" => "2026-08-25T10:00:00",
      "ends_at" => "2026-08-25T11:00:00"
    }

    render_hook(view, "validate", %{"contact_search" => reassigned_values})
    reassigned = contact_schedule_vue(view)

    assert reassigned.props["search"]["values"] ==
             %{reassigned_values | "route_key" => "route-beta"}

    assert reassigned.props["search"]["fields"]["route"]["options"] == [
             %{
               "label" => "Beta provider / Streaming to Cadence / Primary downlink",
               "value" => "route-beta"
             }
           ]

    no_route_values = %{reassigned_values | "spacecraft_id" => "spacecraft-gamma"}
    render_hook(view, "validate", %{"contact_search" => no_route_values})
    not_ready = contact_schedule_vue(view)

    assert not_ready.props["search"]["values"]["route_key"] == ""
    assert not_ready.props["search"]["submit"]["disabled"]

    assert not_ready.props["readiness"]["findings"] == [
             %{"message" => "Publish an inbound route."}
           ]

    assert_json_safe(not_ready)
  end

  test "search streams opportunities and signed reservation creates one durable attempt" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    test_pid = self()
    {window, opportunity} = opportunity_window(setup)
    opportunity = put_in(opportunity, ["extensions", "cost"], 1_250)

    live_deps =
      LiveDeps.new(
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

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)

    render_hook(view, "search", %{"contact_search" => window})

    render_async(view, @async_timeout)

    searched_vue = contact_schedule_vue(view)
    [opportunity_row] = stream_upserts(searched_vue, "opportunities")

    assert opportunity_row["__dom_id"] == "opportunity-opportunity-alpha"
    assert opportunity_row["reserve_action"]["id"] == "reserve-opportunity-opportunity-alpha"
    assert opportunity_row["cost"] == 1_250
    assert opportunity_row["window"]["starts_at"] == format_time(opportunity["starts_at"])
    assert opportunity_row["provider"] == setup.route.provider_display_name

    assert stream_mutations(searched_vue, "opportunities") == [
             ["replace", "/opportunities", []],
             ["upsert", "/opportunities/-", opportunity_row]
           ]

    assert {:ok, token_payload} =
             OpportunityToken.verify(opportunity_row["reserve_action"]["payload"]["token"])

    assert token_payload["organization_id"] == org.organization_id
    assert token_payload["mission_id"] == mission.mission_id
    assert token_payload["route_key"] == setup.route.route_key
    assert token_payload["opportunity"] == Map.drop(opportunity, ["booking_token"])

    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
    render_async(view, @async_timeout)

    assert_received :provider_mutation
    assert has_element?(view, "#flash-info[role='alert']", "Contact reserved and scheduled.")

    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)
    reserved_vue = contact_schedule_vue(view)
    [reservation_row] = stream_upserts(reserved_vue, "provider_reservations")
    [contact_row] = stream_upserts(reserved_vue, "contact_records")

    assert reservation_row["__dom_id"] ==
             "provider-reservation-#{reservation.provider_reservation_id}"

    assert reservation_row["provider"]["id"] ==
             "reservation-provider-#{reservation.provider_reservation_id}"

    assert reservation_row["service"]["id"] ==
             "reservation-service-#{reservation.provider_reservation_id}"

    assert reservation_row["delivery"]["id"] ==
             "reservation-delivery-#{reservation.provider_reservation_id}"

    assert reservation_row["transport"]["id"] ==
             "reservation-transport-#{reservation.provider_reservation_id}"

    assert reservation_row["detail_action"]["href"] ==
             "/missions/#{mission.mission_id}/ops/contacts/#{reservation.provider_reservation_id}"

    assert reservation_row["cancel_action"] == nil
    assert reservation_row["diagnostics"] == nil
    assert contact_row["__dom_id"] == "contact-record-#{reservation.scheduled_contact_id}"
    assert contact_row["kind"] == "scheduled"

    assert contact_row["telemetry_handoff"] == %{
             "owner" => "contact_record_detail",
             "window_available" => true
           }

    assert contact_row["inspect_action"]["href"] ==
             "/missions/#{mission.mission_id}/ops/contacts/records/#{reservation.scheduled_contact_id}"

    assert stream_mutations(reserved_vue, "provider_reservations") == [
             ["replace", "/provider_reservations", []],
             ["upsert", "/provider_reservations/-", reservation_row]
           ]

    assert stream_mutations(reserved_vue, "contact_records") == [
             ["replace", "/contact_records", []],
             ["upsert", "/contact_records/-", contact_row]
           ]

    assert reserved_vue.props["page"]["header"]["contact_count"]["value"] == 1
    assert reserved_vue.props["page"]["header"]["reservation_count"]["value"] == 1
    assert_json_safe(reserved_vue)

    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
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
    test_pid = self()
    refresh_counter = :counters.new(1, [])

    live_deps =
      LiveDeps.new(
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
        list_reservation_rows: fn organization_id, mission_id ->
          :ok = :counters.add(refresh_counter, 1, 1)
          refresh_number = :counters.get(refresh_counter, 1)
          send(test_pid, {:reservation_refresh, refresh_number})
          reservation_rows(organization_id, mission_id)
        end,
        refresh_interval_ms: 20
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    assert_receive {:reservation_refresh, 1}
    track_async_view(view)

    render_hook(view, "search", %{"contact_search" => window})

    render_async(view, @async_timeout)
    [opportunity_row] = view |> contact_schedule_vue() |> stream_upserts("opportunities")

    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
    render_async(view, @async_timeout)

    assert_receive {:reservation_refresh, 2}
    assert_receive {:reservation_refresh, refresh_number} when refresh_number >= 3, 500

    assert has_element?(
             view,
             "#flash-info[role='alert']",
             "Reservation recorded; provider confirmation is pending."
           )

    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)
    [reservation_row] = view |> contact_schedule_vue() |> stream_upserts("provider_reservations")

    assert reservation_row["provider_status"] == "pending"

    assert Enum.find(reservation_row["observations"], &(&1["label"] == "Contact")) == %{
             "id" => "reservation-contact-status-#{reservation.provider_reservation_id}",
             "label" => "Contact",
             "value" => "pending"
           }

    assert Enum.any?(
             reservation_row["observations"],
             &(&1["id"] == "reservation-pass-phase-#{reservation.provider_reservation_id}")
           )

    assert Enum.any?(
             reservation_row["observations"],
             &(&1["id"] == "reservation-delivery-status-#{reservation.provider_reservation_id}")
           )

    assert reservation_row["diagnostics"] == nil

    assert Cadence.Contacts.list_scheduled_contacts(org.organization_id, mission.mission_id) == []
  end

  test "cancellation converges provider and Scheduled Contact state" do
    {conn, _user, org, mission} = signed_in_org_and_mission(role: :organization_admin)
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)
    test_pid = self()

    live_deps =
      LiveDeps.new(
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
          send(test_pid, {:cancel_started, self()})

          receive do
            :finish_cancel -> :ok
          end

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

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)

    render_hook(view, "search", %{"contact_search" => window})

    render_async(view, @async_timeout)
    [opportunity_row] = view |> contact_schedule_vue() |> stream_upserts("opportunities")

    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
    render_async(view, @async_timeout)

    [reservation] = ProviderReservations.list_for_mission(org.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)

    [reservation_row] = view |> contact_schedule_vue() |> stream_upserts("provider_reservations")
    cancel_action = reservation_row["cancel_action"]

    assert cancel_action == %{
             "id" => "cancel-reservation-#{reservation.provider_reservation_id}",
             "label" => "Cancel",
             "confirm" => "Cancel this provider reservation?",
             "busy" => false,
             "disabled" => false,
             "payload" => %{"reservation-id" => reservation.provider_reservation_id}
           }

    assert reservation_row["diagnostics"]["id"] ==
             "reservation-diagnostics-#{reservation.provider_reservation_id}"

    assert {:ok, scheduled_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               org.organization_id,
               mission.mission_id,
               reservation.scheduled_contact_id
             )

    assert Enum.find(
             reservation_row["diagnostics"]["rows"],
             &(&1["label"] == "Cadence contact")
           )["value"] == Atom.to_string(scheduled_contact.lifecycle_state)

    render_hook(view, "cancel", cancel_action["payload"])
    assert_receive {:cancel_started, cancel_pid}

    assert contact_schedule_vue(view).props["busy"] == %{
             "keys" => [reservation.provider_reservation_id],
             "actions" => %{
               reservation.provider_reservation_id => %{"busy" => true, "disabled" => true}
             }
           }

    render_hook(view, "cancel", cancel_action["payload"])
    refute_receive {:cancel_started, _duplicate_pid}

    send(cancel_pid, :finish_cancel)
    render_async(view, @async_timeout)

    [canceled_row] = view |> contact_schedule_vue() |> stream_upserts("provider_reservations")
    assert canceled_row["state"] == "canceled"
    assert canceled_row["cancel_action"] == nil
    assert has_element?(view, "#flash-info[role='alert']", "Cancellation confirmed.")

    assert {:ok, contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               org.organization_id,
               mission.mission_id,
               reservation.scheduled_contact_id
             )

    assert contact.lifecycle_state == :canceled
  end

  test "invalid window, no results, and tampered token remain explicit" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, _opportunity} = opportunity_window(setup)

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          {:ok, %{route: setup.route, opportunities: []}}
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)

    invalid = Map.put(window, "ends_at", window["starts_at"])

    render_hook(view, "search", %{"contact_search" => invalid})

    assert contact_schedule_vue(view).props["search"]["error"] == %{
             "id" => "contact-search-error",
             "message" => "Window end must be after its start."
           }

    render_hook(view, "search", %{"contact_search" => window})

    render_async(view, @async_timeout)
    no_results_vue = contact_schedule_vue(view)
    assert no_results_vue.props["page"]["opportunities"]["count"]["value"] == 0
    assert no_results_vue.props["page"]["opportunities"]["empty"]["visible"]

    assert stream_mutations(no_results_vue, "opportunities") == [
             ["replace", "/opportunities", []]
           ]

    render_hook(view, "reserve", %{"token" => "tampered"})

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "That opportunity is no longer valid."
           )

    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id) == []
  end

  test "signed opportunity scope and immutable route snapshots are revalidated server-side" do
    {scope_conn, _user, org, mission} = signed_in_org_and_mission()

    {:ok, scope_view, _html} =
      live(scope_conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    wrong_scope_token =
      OpportunityToken.sign(%{
        "organization_id" => "other-organization",
        "mission_id" => mission.mission_id
      })

    render_hook(scope_view, "reserve", %{"token" => wrong_scope_token})

    assert has_element?(
             scope_view,
             "#flash-error[role='alert']",
             "That opportunity is no longer valid."
           )

    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id) == []

    {route_conn, _user, route_org, route_mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(route_org, route_mission)
    {window, opportunity} = opportunity_window(setup)
    test_pid = self()
    changed_route = %{setup.route | provider_version: setup.route.provider_version + 1}

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          {:ok, %{route: setup.route, opportunities: [opportunity]}}
        end,
        resolve_ready_route: fn _organization_id, _mission_id, _spacecraft_id, _route_key ->
          {:ok, changed_route}
        end,
        reserve: fn _organization_id, _mission_id, _provider_id, _attrs ->
          send(test_pid, :reserve_called)
          {:ok, :unexpected}
        end
      )

    {:ok, route_view, _html} =
      live_with_deps(
        route_conn,
        ~p"/missions/#{route_mission.mission_id}/ops/contacts",
        live_deps
      )

    track_async_view(route_view)
    render_hook(route_view, "search", %{"contact_search" => window})
    render_async(route_view, @async_timeout)

    [opportunity_row] =
      route_view |> contact_schedule_vue() |> stream_upserts("opportunities")

    render_hook(route_view, "reserve", opportunity_row["reserve_action"]["payload"])

    refute_receive :reserve_called

    assert has_element?(
             route_view,
             "#flash-error[role='alert']",
             "That opportunity is no longer valid."
           )

    assert ProviderReservations.list_for_mission(
             route_org.organization_id,
             route_mission.mission_id
           ) == []
  end

  test "provider search errors remain explicit" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, _opportunity} = opportunity_window(setup)

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          {:error, :provider_unavailable}
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)

    render_hook(view, "search", %{"contact_search" => window})

    render_async(view, @async_timeout)

    assert contact_schedule_vue(view).props["search"]["error"] == %{
             "id" => "contact-search-error",
             "message" => "The provider search failed. Check provider readiness and try again."
           }
  end

  test "search worker exits remain explicit without replacing the last opportunity stream" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, _opportunity} = opportunity_window(setup)

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          exit(:provider_search_crashed)
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)
    render_hook(view, "search", %{"contact_search" => window})
    render_async(view, @async_timeout)

    exited_vue = contact_schedule_vue(view)

    assert exited_vue.props["search"]["submit"]["busy"] == false

    assert exited_vue.props["search"]["error"] == %{
             "id" => "contact-search-error",
             "message" => "The provider search failed. Check provider readiness and try again."
           }

    assert stream_mutations(exited_vue, "opportunities") == []
  end

  test "stale search outcomes cannot replace the latest provider result" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {first_window, opportunity} = opportunity_window(setup)
    second_window = shift_window(first_window, 120)
    test_pid = self()

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, window ->
          send(test_pid, {:search_waiting, window["starts_at"], self()})

          receive do
            {:finish_search, result} -> result
          end
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)
    render_hook(view, "search", %{"contact_search" => first_window})
    assert_receive {:search_waiting, _first_start, first_pid}

    render_hook(view, "search", %{"contact_search" => second_window})
    assert_receive {:search_waiting, _second_start, second_pid}

    send(first_pid, {:finish_search, {:error, :provider_unavailable}})

    send(
      second_pid,
      {:finish_search, {:ok, %{route: setup.route, opportunities: [opportunity]}}}
    )

    render_async(view, @async_timeout)

    latest_vue = contact_schedule_vue(view)
    assert latest_vue.props["search"]["error"] == nil
    assert latest_vue.props["page"]["opportunities"]["count"]["value"] == 1
    assert [row] = stream_upserts(latest_vue, "opportunities")
    assert row["id"] == "opportunity-alpha"
  end

  test "reservation worker exits clear busy state and preserve durable state" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          {:ok, %{route: setup.route, opportunities: [opportunity]}}
        end,
        reserve: fn _organization_id, _mission_id, _provider_id, _attrs ->
          exit(:reservation_worker_crashed)
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)
    render_hook(view, "search", %{"contact_search" => window})
    render_async(view, @async_timeout)

    [opportunity_row] = view |> contact_schedule_vue() |> stream_upserts("opportunities")
    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
    render_async(view, @async_timeout)

    assert contact_schedule_vue(view).props["busy"] == %{"keys" => [], "actions" => %{}}

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Reservation worker stopped unexpectedly; durable state was preserved."
           )

    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id) == []
  end

  test "unconfirmed provider reservation outcomes remain explicit for reconciliation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          {:ok, %{route: setup.route, opportunities: [opportunity]}}
        end,
        reserve: fn _organization_id, _mission_id, _provider_id, _attrs ->
          {:error, {:provider_reservation_not_confirmed, %{}}}
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)
    render_hook(view, "search", %{"contact_search" => window})
    render_async(view, @async_timeout)

    [opportunity_row] = view |> contact_schedule_vue() |> stream_upserts("opportunities")
    render_hook(view, "reserve", opportunity_row["reserve_action"]["payload"])
    render_async(view, @async_timeout)

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Provider outcome is not confirmed; Cadence will reconcile it."
           )
  end

  test "cancellation error and exit outcomes clear busy state after independent remounts" do
    outcomes = [
      {
        fn -> {:error, {:provider_reservation_not_confirmed, %{}}} end,
        "Cancellation is uncertain; Cadence will reconcile it."
      },
      {fn -> {:error, :provider_unavailable} end, "Cancellation failed."},
      {
        fn -> exit(:cancellation_worker_crashed) end,
        "Cancellation worker stopped; durable state was preserved."
      }
    ]

    Enum.each(outcomes, fn {cancel_result, message} ->
      {conn, _user, _org, mission} = signed_in_org_and_mission(role: :organization_admin)

      live_deps =
        LiveDeps.new(
          cancel: fn _organization_id, _mission_id, _reservation_id -> cancel_result.() end
        )

      {:ok, view, _html} =
        live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

      track_async_view(view)
      render_hook(view, "cancel", %{"reservation-id" => "provider-reservation-alpha"})
      render_async(view, @async_timeout)

      assert contact_schedule_vue(view).props["busy"] == %{"keys" => [], "actions" => %{}}
      assert has_element?(view, "#flash-error[role='alert']", message)
    end)
  end

  test "search and reservation busy state remain server-canonical and suppress duplicates" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    setup = persist_ready_comms!(org, mission)
    {window, opportunity} = opportunity_window(setup)
    test_pid = self()

    live_deps =
      LiveDeps.new(
        search_opportunities: fn _organization_id, _mission_id, _route_key, _window ->
          send(test_pid, {:search_started, self()})

          receive do
            :finish_search -> {:ok, %{route: setup.route, opportunities: [opportunity]}}
          end
        end,
        reserve: fn _organization_id, _mission_id, _provider_id, _attrs ->
          send(test_pid, {:reserve_started, self()})

          receive do
            :finish_reserve -> {:error, :provider_unavailable}
          end
        end,
        refresh_interval_ms: 60_000
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    track_async_view(view)
    render_hook(view, "search", %{"contact_search" => window})

    assert_receive {:search_started, search_pid}

    assert contact_schedule_vue(view).props["search"]["submit"] == %{
             "id" => "search-contact-opportunities",
             "label" => "Searching provider",
             "busy" => true,
             "disabled" => true
           }

    send(search_pid, :finish_search)
    render_async(view, @async_timeout)

    [opportunity_row] = view |> contact_schedule_vue() |> stream_upserts("opportunities")
    reserve_payload = opportunity_row["reserve_action"]["payload"]

    render_hook(view, "reserve", reserve_payload)
    assert_receive {:reserve_started, reserve_pid}

    assert contact_schedule_vue(view).props["busy"] == %{
             "keys" => ["opportunity-alpha"],
             "actions" => %{
               "opportunity-alpha" => %{"busy" => true, "disabled" => true}
             }
           }

    render_hook(view, "reserve", reserve_payload)
    refute_receive {:reserve_started, _duplicate_pid}

    send(reserve_pid, :finish_reserve)
    render_async(view, @async_timeout)

    assert contact_schedule_vue(view).props["busy"] == %{"keys" => [], "actions" => %{}}
    assert has_element?(view, "#flash-error[role='alert']", "Reservation could not be completed.")
    assert ProviderReservations.list_for_mission(org.organization_id, mission.mission_id) == []
  end

  test "member cancellation is rejected by both the DTO and server handler" do
    {conn, _user, _org, mission} = signed_in_org_and_mission()
    test_pid = self()

    live_deps =
      LiveDeps.new(
        cancel: fn _organization_id, _mission_id, _reservation_id ->
          send(test_pid, :cancel_called)
          {:ok, :unexpected}
        end
      )

    {:ok, view, _html} =
      live_with_deps(conn, ~p"/missions/#{mission.mission_id}/ops/contacts", live_deps)

    render_hook(view, "cancel", %{"reservation-id" => "provider-reservation-alpha"})

    refute_receive :cancel_called

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Only organization administrators may cancel reservations."
           )
  end

  test "boot configuration is captured as an immutable dependency snapshot" do
    previous = Application.get_env(:cadence_web, :ops_contact_schedule_live)
    first_search = fn _organization_id, _mission_id, _route_key, _window -> :first end
    second_search = fn _organization_id, _mission_id, _route_key, _window -> :second end

    try do
      Application.put_env(:cadence_web, :ops_contact_schedule_live,
        search_opportunities: first_search,
        refresh_interval_ms: 1_234
      )

      snapshot = LiveDeps.from_config()

      Application.put_env(:cadence_web, :ops_contact_schedule_live,
        search_opportunities: second_search,
        refresh_interval_ms: 4_321
      )

      assert LiveDeps.search_opportunities(snapshot, "org", "mission", "route", %{}) == :first
      assert LiveDeps.refresh_interval_ms(snapshot) == 1_234

      current = LiveDeps.from_config()
      assert LiveDeps.search_opportunities(current, "org", "mission", "route", %{}) == :second
      assert LiveDeps.refresh_interval_ms(current) == 4_321
    after
      restore_env(:ops_contact_schedule_live, previous)
    end
  end

  test "opportunity tokens expire and reject tampering" do
    token = OpportunityToken.sign(%{"mission_id" => "mission-alpha"})

    assert {:error, :invalid} = OpportunityToken.verify(token <> "tampered")
    assert {:error, :expired} = OpportunityToken.verify(token, max_age: -1)
  end

  defp contact_schedule_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-contact-schedule-component")
  end

  defp stream_upserts(vue, stream) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", path, _row] -> String.starts_with?(path, "/#{stream}/")
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp stream_mutations(vue, stream) do
    Enum.filter(vue.streams_diff, fn
      [_operation, path | _rest] ->
        path == "/#{stream}" or String.starts_with?(path, "/#{stream}/")

      _operation ->
        false
    end)
  end

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp empty_page_props(mission_id) do
    %{
      "id" => "ops-contacts-page",
      "header" => %{
        "eyebrow" => "Mission operations / contact control",
        "title" => "Contacts",
        "description" =>
          "Inspect scheduled and realized mission contacts, then plan provider capacity without mixing contact state into telemetry charts.",
        "scope" => %{"label" => "Scope", "value" => "Mission contact truth"},
        "contact_count" => %{
          "id" => "contact-record-count",
          "label" => "Contacts",
          "value" => 0
        },
        "reservation_count" => %{
          "id" => "provider-reservation-count",
          "label" => "Reservations",
          "value" => 0
        }
      },
      "contact_ledger" => %{
        "id" => "mission-contact-ledger",
        "eyebrow" => "Canonical contact ledger",
        "title" => "Scheduled and realized mission contacts",
        "description" =>
          "Open a record for lifecycle evidence or hand its exact window to Telemetry Explore.",
        "timeline_action" => %{
          "id" => "contacts-open-timeline",
          "label" => "Mission Timeline",
          "icon" => "hero-clock",
          "href" => "/missions/#{mission_id}/ops/timeline?category=operations"
        },
        "rows_id" => "contact-records",
        "empty" => %{
          "id" => "contact-records-empty",
          "icon" => "hero-signal-slash",
          "copy" => "No scheduled or realized contacts for this mission.",
          "visible" => true
        }
      },
      "opportunity_search" => %{
        "eyebrow" => "01 / Opportunity search",
        "description" => "All times are coordinated universal time.",
        "icon" => "hero-signal"
      },
      "opportunities" => %{
        "eyebrow" => "02 / Provider opportunities",
        "description" =>
          "Select a provider-owned window to create a durable reservation attempt.",
        "count" => %{"id" => "contact-opportunity-count", "value" => 0},
        "rows_id" => "contact-opportunities",
        "empty" => %{
          "id" => "contact-opportunities-empty",
          "icon" => "hero-magnifying-glass",
          "copy" => "Search a UTC window to load provider opportunities.",
          "visible" => true
        }
      },
      "reservations" => %{
        "eyebrow" => "03 / Reservation ledger",
        "description" => "Provider truth and Cadence contact state remain visible independently.",
        "rows_id" => "provider-reservations",
        "empty" => %{
          "id" => "provider-reservations-empty",
          "icon" => "hero-calendar-days",
          "copy" => "No provider reservations for this mission.",
          "visible" => true
        }
      }
    }
  end

  defp search_fields_props(spacecraft, routes) do
    %{
      "spacecraft" => %{
        "id" => "contact-spacecraft",
        "name" => "contact_search[spacecraft_id]",
        "type" => "select",
        "label" => "Spacecraft",
        "options" =>
          Enum.map(spacecraft, &%{"label" => &1.display_name, "value" => &1.spacecraft_id})
      },
      "route" => %{
        "id" => "contact-route",
        "name" => "contact_search[route_key]",
        "type" => "select",
        "label" => "Downlink route / provider",
        "options" =>
          Enum.map(routes, fn route ->
            %{
              "label" =>
                "#{route.provider_display_name} / #{route.delivery_operator_summary} / #{route.route_display_name}",
              "value" => route.route_key
            }
          end)
      },
      "starts_at" => %{
        "id" => "contact-window-start",
        "name" => "contact_search[starts_at]",
        "type" => "datetime-local",
        "label" => "Window starts (UTC)"
      },
      "ends_at" => %{
        "id" => "contact-window-end",
        "name" => "contact_search[ends_at]",
        "type" => "datetime-local",
        "label" => "Window ends (UTC)"
      }
    }
  end

  defp search_route(route_key, provider_display_name) do
    %{
      route_key: route_key,
      provider_display_name: provider_display_name,
      delivery_operator_summary: "Streaming to Cadence",
      route_display_name: "Primary downlink"
    }
  end

  defp format_time(value) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    Calendar.strftime(datetime, "%Y-%m-%d %H:%MZ")
  end

  defp shift_window(window, seconds) do
    Map.new(window, fn
      {key, value} when key in ["starts_at", "ends_at"] ->
        {:ok, datetime} = NaiveDateTime.from_iso8601(value)
        {key, datetime |> NaiveDateTime.add(seconds) |> NaiveDateTime.to_iso8601()}

      pair ->
        pair
    end)
  end

  defp reservation_rows(organization_id, mission_id) do
    organization_id
    |> ProviderReservations.list_for_mission(mission_id)
    |> Enum.map(fn reservation ->
      scheduled_contact =
        case Cadence.Contacts.fetch_scheduled_contact(
               organization_id,
               mission_id,
               reservation.scheduled_contact_id
             ) do
          {:ok, contact} -> contact
          {:error, :scheduled_contact_not_found} -> nil
        end

      %{reservation: reservation, scheduled_contact: scheduled_contact}
    end)
  end

  defp signed_in_org_and_mission(opts \\ []) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, opts)
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

  defp live_with_deps(conn, path, %LiveDeps{} = live_deps) do
    conn
    |> put_connect_params(%{ops_contact_schedule_live_deps: live_deps})
    |> live(path)
  end

  defp restore_env(key, nil), do: Application.delete_env(:cadence_web, key)

  defp restore_env(key, value) do
    Application.put_env(:cadence_web, key, value)
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
