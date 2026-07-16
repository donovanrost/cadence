defmodule CadenceWeb.OpsContactDetailLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{
    ProviderReservation,
    ProviderReservationChanges,
    ProviderReservations,
    ScheduledContact,
    ScheduledContactRevisions
  }

  alias Cadence.Comms.Transport
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.Persistence.Schemas.ScheduledContactRow
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  test "reservation rows navigate to the authenticated detail record" do
    {conn, _user, org, mission} = signed_in(:member)
    setup = persist_contact!(org, mission, :baseline)

    {:ok, schedule_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts")

    link = "#open-reservation-#{setup.reservation.provider_reservation_id}"
    assert has_element?(schedule_view, link)

    assert {:ok, detail_view, _html} =
             schedule_view
             |> element(link)
             |> render_click()
             |> follow_redirect(conn)

    assert has_element?(detail_view, "#ops-contact-detail")
    assert has_element?(detail_view, "#contact-values-matrix")
    assert has_element?(detail_view, "#contact-change-timeline")
    assert has_element?(detail_view, "#contact-audit-timeline")
    refute has_element?(detail_view, "#contact-admin-diagnostics")
  end

  test "organization admin approves the current proposal through a reasoned form" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :approval)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    approval_form = "#provider-change-approval-form-#{change.provider_reservation_change_id}"
    rejection_form = "#provider-change-rejection-form-#{change.provider_reservation_change_id}"

    assert has_element?(view, "#contact-admin-diagnostics")
    assert has_element?(view, approval_form)
    assert has_element?(view, rejection_form)

    view
    |> form(approval_form,
      approval: %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "The shifted window remains clear of commanding"
      }
    )
    |> render_submit()

    refute has_element?(view, approval_form)
    assert has_element?(view, "#provider-change-#{change.provider_reservation_change_id}")

    assert {:ok, scheduled} =
             Cadence.fetch_scheduled_contact(
               org.organization_id,
               mission.mission_id,
               setup.reservation.scheduled_contact_id
             )

    assert scheduled.current_revision == 2

    assert [_initial, _accepted] =
             ScheduledContactRevisions.list(
               org.organization_id,
               setup.reservation.scheduled_contact_id
             )

    assert has_element?(view, "#contact-audit-timeline [id^=provider-audit-]")
  end

  test "ordinary mission members may inspect but cannot see decision or diagnostic controls" do
    {conn, _user, org, mission} = signed_in(:member)
    setup = persist_contact!(org, mission, :approval)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    assert has_element?(view, "#provider-change-#{change.provider_reservation_change_id}")

    refute has_element?(
             view,
             "#provider-change-approval-form-#{change.provider_reservation_change_id}"
           )

    refute has_element?(view, "#contact-admin-diagnostics")
  end

  test "already-effective provider facts use acknowledgment and contingency language" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :acknowledgment)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    acknowledgment_form =
      "#provider-change-acknowledgment-form-#{change.provider_reservation_change_id}"

    assert has_element?(view, acknowledgment_form)

    assert has_element?(
             view,
             "#acknowledge-provider-change-#{change.provider_reservation_change_id}"
           )

    refute has_element?(
             view,
             "#provider-change-approval-form-#{change.provider_reservation_change_id}"
           )

    view
    |> form(acknowledgment_form,
      acknowledgment: %{
        "proposal_hash" => change.proposal_hash,
        "reason" => "Flight opened a replacement-pass contingency"
      }
    )
    |> render_submit()

    refute has_element?(view, acknowledgment_form)
  end

  test "configuration conflicts show remediation and never render approval" do
    {conn, _user, org, mission} = signed_in(:organization_admin)
    setup = persist_contact!(org, mission, :configuration_failure)
    change = only_change(setup)

    {:ok, view, _html} = live(conn, detail_path(mission, setup))

    assert has_element?(
             view,
             "#configuration-remediation-#{change.provider_reservation_change_id}"
           )

    refute has_element?(
             view,
             "#provider-change-approval-form-#{change.provider_reservation_change_id}"
           )
  end

  test "router authentication and mission scope protect detail records", %{conn: conn} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    setup = persist_contact!(org, mission, :baseline)

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, detail_path(mission, setup))

    outsider = TestFixtures.persist_user!()
    outsider_org = TestFixtures.persist_org!()
    _outsider_membership = TestFixtures.grant_membership!(outsider, outsider_org)

    assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _message}}}} =
             live(TestFixtures.member_conn(outsider), detail_path(mission, setup))
  end

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: role)
    mission = TestFixtures.persist_mission!(org, display_name: "Contact Ops")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp persist_contact!(org, mission, scenario) do
    suffix = System.unique_integer([:positive])
    starts_at = ~U[2026-07-20 12:00:00.000000Z]
    ends_at = DateTime.add(starts_at, 600)

    provider =
      MissionProvider.new(%{
        provider_id: "detail-provider-#{suffix}",
        mission_id: mission.mission_id,
        display_name: "Detail simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-detail-#{suffix}",
        delivery_policy_document: %{}
      })

    assert {:ok, provider} = MissionProviders.persist_provider(org.organization_id, provider)

    transport =
      Transport.new(%{
        transport_id: "detail-transport-#{suffix}",
        mission_id: mission.mission_id,
        display_name: "Detail TCP transport",
        origin: :direct,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "127.0.0.1",
          "port" => 5_100,
          "framing_mode" => "fixed_size",
          "frame_size" => 1_115,
          "reconnect_policy" => "on_disconnect",
          "tls_enabled" => false,
          "ingress_protocol_family" => "tm"
        }
      })

    assert {:ok, transport} = Cadence.persist_transport(org.organization_id, transport)

    requested = %{
      "provider_contact_ref" => nil,
      "provider_revision" => 1,
      "client_reference" => "detail-client-#{suffix}",
      "opportunity_ref" => "detail-opportunity-#{suffix}",
      "spacecraft_ref" => "SC-DETAIL-#{suffix}",
      "ground_station_ref" => "station-alpha",
      "antenna_or_service_pool_ref" => "pool-alpha",
      "service_profile_ref" => "service-downlink",
      "delivery_profile_ref" => "delivery-cadence",
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at),
      "status" => "requesting",
      "pass_phase" => "scheduled",
      "delivery_state" => "pending",
      "delivery_descriptor" => %{},
      "status_reason" => nil,
      "extensions" => %{}
    }

    reservation =
      ProviderReservation.new(%{
        provider_reservation_id: "detail-reservation-#{suffix}",
        mission_id: mission.mission_id,
        provider_id: provider.provider_id,
        provider_version: provider.version,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        service_profile_ref: %{"id" => "service-downlink", "version" => 3},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7},
        provider_profile_id: "detail-profile-#{suffix}",
        provider_profile_version: 1,
        scheduled_contact_id: "detail-scheduled-contact-#{suffix}",
        provider_opportunity_ref: requested["opportunity_ref"],
        idempotency_key: requested["client_reference"],
        spacecraft_id: "detail-spacecraft-#{suffix}",
        provider_spacecraft_ref: requested["spacecraft_ref"],
        source_endpoint_refs: ["detail-source-#{suffix}"],
        path_template_ids: ["detail-path-#{suffix}"],
        starts_at: starts_at,
        ends_at: ends_at,
        requested_snapshot_document: requested,
        request_document: %{"provider_request" => requested}
      })

    assert {:ok, reservation} =
             ProviderReservations.create_attempt(org.organization_id, reservation)

    baseline =
      requested
      |> Map.delete("delivery_descriptor")
      |> Map.put("id", "provider-contact-#{suffix}")
      |> Map.put("provider_contact_ref", "provider-contact-#{suffix}")
      |> Map.put("status", "confirmed")

    assert {:ok, reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               baseline
             )

    scheduled_contact =
      ScheduledContact.new(%{
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: reservation.scheduled_contact_id,
        starts_at: starts_at,
        ends_at: ends_at,
        provider_contact_ref: reservation.provider_contact_ref,
        metadata: %{"provider_reservation_id" => reservation.provider_reservation_id}
      })

    assert {:ok, row} = scheduled_contact |> ScheduledContactRow.changeset() |> Repo.insert()

    assert {:ok, _revision} =
             ScheduledContactRevisions.ensure_initial(
               Repo,
               ScheduledContactRow.to_domain(row)
             )

    apply_scenario!(org, mission, reservation, baseline, scenario)

    assert {:ok, reservation} =
             ProviderReservations.fetch(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id
             )

    %{reservation: reservation, baseline: baseline}
  end

  defp apply_scenario!(_org, _mission, _reservation, _baseline, :baseline), do: :ok

  defp apply_scenario!(org, mission, reservation, baseline, :approval) do
    shifted =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("starts_at", shift(baseline["starts_at"], 60))
      |> Map.put("ends_at", shift(baseline["ends_at"], 60))

    assert {:ok, _reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               shifted
             )
  end

  defp apply_scenario!(org, mission, reservation, baseline, :acknowledgment) do
    effective =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("status", "canceled")
      |> Map.put("extensions", %{
        "provider_change" => %{"effective" => true, "rejectable" => false}
      })

    assert {:ok, _reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               effective
             )
  end

  defp apply_scenario!(org, mission, reservation, baseline, :configuration_failure) do
    mismatch =
      baseline
      |> Map.put("provider_revision", 2)
      |> Map.put("spacecraft_ref", "SC-UNAPPROVED")

    assert {:error, {:provider_configuration_mismatch, _reason}} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               mismatch
             )
  end

  defp shift(value, seconds) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(value)
    datetime |> DateTime.add(seconds) |> DateTime.to_iso8601()
  end

  defp only_change(setup) do
    assert [change] =
             ProviderReservationChanges.list_for_reservation(
               setup.reservation.organization_id,
               setup.reservation.provider_reservation_id
             )

    change
  end

  defp detail_path(mission, setup),
    do:
      ~p"/missions/#{mission.mission_id}/ops/contacts/#{setup.reservation.provider_reservation_id}"
end
