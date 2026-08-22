defmodule CadenceWeb.OpsTimelineLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  test "renders canonical mission events and round-trips originating dashboard context" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Timeline spacecraft")

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "timeline-source-endpoint",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Timeline source endpoint"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(
               organization.organization_id,
               source_endpoint
             )

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "timeline-scheduled-contact",
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint.source_endpoint_id],
        contact_intents: [:telemetry_downlink],
        paths: [
          Path.new(%{
            path_id: "timeline-contact-path",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint.source_endpoint_id
          })
        ],
        starts_at: ~U[2026-08-01 12:10:00Z],
        ends_at: ~U[2026-08-01 12:20:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               organization.organization_id,
               scheduled_contact
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        dashboard_id: "timeline-origin-dashboard",
        name: "Timeline Origin"
      )

    observed_at = ~U[2026-08-01 12:00:00Z]

    source_event =
      Event.new(%{
        event_id: "operational-event-source-health-1",
        organization_id: organization.organization_id,
        mission_id: mission.mission_id,
        occurred_at: observed_at,
        category: :data_source,
        kind: :source_health_degraded,
        severity: :warning,
        subject: %{kind: :data_source, id: "flight-telemetry"},
        scope: %{data_source_id: "flight-telemetry", spacecraft_id: spacecraft.spacecraft_id},
        causality: %{correlation_id: "source-health-1"},
        payload: %{reason: "source_probe_failed"},
        current: %{status: "degraded"}
      })

    historical_event =
      Event.new(%{
        event_id: "operational-event-backfill-1",
        organization_id: organization.organization_id,
        mission_id: mission.mission_id,
        occurred_at: DateTime.add(observed_at, 30, :second),
        category: :telemetry,
        kind: :telemetry_backfill_failed,
        severity: :error,
        subject: %{kind: :telemetry_point, id: "HK.counter"},
        scope: %{point_id: "HK.counter", spacecraft_id: spacecraft.spacecraft_id},
        causality: %{correlation_id: "historical-group-1"},
        payload: %{reason: "archive_gap"},
        metadata: %{"request_group_id" => "historical-group-1"}
      })

    assert {:ok, _source_event} = OperationalEvents.persist_event(source_event)
    assert {:ok, _historical_event} = OperationalEvents.persist_event(historical_event)

    historical_mission_event_id = "mission_event:operational-event-backfill-1"

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/timeline?#{%{event_id: historical_mission_event_id, source_dashboard_id: dashboard.dashboard_id, time_mode: "archive", from: "2026-08-01T11:00:00Z", to: "2026-08-01T13:00:00Z", replay_run_id: "replay-1", data_view: "all_revisions", data_source_id: "flight-telemetry", source_binding_id: "flight-binding", selected_id: historical_mission_event_id}}"
      )

    assert has_element?(view, "#ops-timeline-page")
    assert has_element?(view, "#ops-context-rail")
    assert has_element?(view, "#mission-event-mission_event-operational-event-source-health-1")

    assert has_element?(
             view,
             ~s(#mission-event-mission_event-operational-event-backfill-1[data-mission-event-kind="telemetry_backfill_failed"][data-mission-event-severity="error"])
           )

    assert has_element?(view, "#timeline-selected-event-title")

    assert has_element?(
             view,
             ~s(#timeline-open-event-owner[href*="/ops/data-operations"][href*="group=historical-group-1"])
           )

    assert has_element?(
             view,
             ~s(#timeline-explore-event[href*="/ops/explore"][href*="point_id=HK.counter"])
           )

    assert has_element?(
             view,
             ~s(#timeline-return-to-origin[href*="/ops/dashboards/#{dashboard.dashboard_id}"][href*="replay_run_id=replay-1"][href*="selected_data_view=all_revisions"][href*="source_binding_id=flight-binding"])
           )

    view
    |> form("#timeline-filter-form", timeline: %{category: "health"})
    |> render_submit()

    assert has_element?(view, "#mission-event-mission_event-operational-event-source-health-1")
    refute has_element?(view, "#mission-event-mission_event-operational-event-backfill-1")

    view
    |> form("#timeline-filter-form",
      timeline: %{
        category: "operations",
        kind: "scheduled_contact_interval",
        spacecraft_id: spacecraft.spacecraft_id
      }
    )
    |> render_submit()

    contact_event_selector =
      "#mission-event-mission_event-operational_event-scheduled_contact_interval-timeline-scheduled-contact"

    assert has_element?(view, contact_event_selector)

    view |> element(contact_event_selector) |> render_click()

    assert has_element?(
             view,
             ~s(#timeline-open-event-owner[href="/missions/#{mission.mission_id}/ops/contacts/records/#{scheduled_contact.scheduled_contact_id}"])
           )
  end
end
