defmodule CadenceWeb.OpsContactDetailLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{Transport, TransportStore}

  alias Cadence.Contacts.{
    ProviderReservation,
    ProviderReservations,
    ScheduledContact,
    ScheduledContactRevisions
  }

  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  test "detail mounts with the authenticated provider reservation subject" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    reservation_id = persist_contact!(org, mission)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts/#{reservation_id}")

    assert_surface(
      view,
      "ops-contact-detail-component",
      "contact_detail",
      mission,
      %{"provider_reservation_id" => reservation_id}
    )
  end

  test "missing provider reservations preserve the authenticated ledger redirect" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    ledger_path = "/missions/#{mission.mission_id}/ops/contacts"

    assert {:error, {:live_redirect, %{to: ^ledger_path}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/contacts/missing")
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp persist_contact!(org, mission) do
    suffix = System.unique_integer([:positive])
    starts_at = ~U[2026-07-20 12:00:00Z]
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

    assert {:ok, transport} = TransportStore.persist_transport(org.organization_id, transport)

    requested = %{
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

    response =
      requested
      |> Map.delete("delivery_descriptor")
      |> Map.merge(%{
        "id" => "provider-contact-#{suffix}",
        "provider_contact_ref" => "provider-contact-#{suffix}",
        "status" => "confirmed"
      })

    assert {:ok, reservation} =
             ProviderReservations.record_provider_response(
               org.organization_id,
               mission.mission_id,
               reservation.provider_reservation_id,
               response
             )

    scheduled =
      ScheduledContact.new(%{
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: reservation.scheduled_contact_id,
        starts_at: starts_at,
        ends_at: ends_at,
        provider_contact_ref: reservation.provider_contact_ref,
        metadata: %{"provider_reservation_id" => reservation.provider_reservation_id}
      })

    assert {:ok, row} = scheduled |> ScheduledContactRow.changeset() |> Repo.insert()

    assert {:ok, _revision} =
             ScheduledContactRevisions.ensure_initial(Repo, ScheduledContactRow.to_domain(row))

    reservation.provider_reservation_id
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "contact-detail")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
