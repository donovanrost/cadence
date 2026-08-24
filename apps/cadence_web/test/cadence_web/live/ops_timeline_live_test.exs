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
  alias Phoenix.LiveView.JS

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

    assert has_element?(view, "#ops-timeline-page-component.contents")
    refute has_element?(view, "#ops-timeline-page")
    assert has_element?(view, "#ops-context-rail-component")

    vue = timeline_vue(view)

    assert vue.component == "OpsTimeline"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]

    assert vue.handlers == %{
             "apply_timeline_filters" => JS.push("apply_timeline_filters"),
             "clear_timeline_selection" => JS.push("clear_timeline_selection")
           }

    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))

    presentation = vue.props["presentation"]
    assert presentation["root"]["attrs"]["id"] == "ops-timeline-page"
    assert presentation["filters"]["attrs"]["id"] == "timeline-filter-form"

    assert presentation["body"]["timeline"]["stream"]["attrs"]["id"] ==
             "mission-timeline-events"

    assert presentation["body"]["timeline"]["stream"]["empty"] == %{
             "attrs" => %{
               "id" => "mission-timeline-events-empty",
               "class" => "hidden only:block p-8 text-center text-sm text-base-content/50"
             },
             "text" => "No canonical mission events match this context."
           }

    fields = Map.new(presentation["filters"]["fields"], &{&1["key"], &1})

    assert presentation["filters"]["values"] == %{
             "category" => "",
             "kind" => "",
             "severity" => "",
             "spacecraft_id" => "",
             "from" => "2026-08-01T11:00:00Z",
             "to" => "2026-08-01T13:00:00Z"
           }

    assert fields["category"]["control"]["attrs"] == %{
             "id" => "timeline_category",
             "name" => "timeline[category]",
             "class" => "w-full select"
           }

    assert fields["category"]["options"] == [
             %{"label" => "All", "value" => ""},
             %{"label" => "Operations", "value" => "operations"},
             %{"label" => "Health", "value" => "health"},
             %{"label" => "Runtime", "value" => "runtime"},
             %{"label" => "Transport", "value" => "transport"}
           ]

    assert fields["kind"]["control"]["attrs"] == %{
             "id" => "timeline_kind",
             "name" => "timeline[kind]",
             "type" => "text",
             "placeholder" => "telemetry_backfill_failed",
             "class" => "w-full input"
           }

    assert fields["severity"]["options"] == [
             %{"label" => "All", "value" => ""},
             %{"label" => "Info", "value" => "info"},
             %{"label" => "Warning", "value" => "warning"},
             %{"label" => "Error", "value" => "error"},
             %{"label" => "Critical", "value" => "critical"}
           ]

    source_health =
      timeline_row!(
        vue,
        "mission-event-mission_event-operational-event-source-health-1"
      )

    assert source_health["attrs"]["data-mission-event-kind"] == "source_health_degraded"

    historical =
      timeline_row!(
        vue,
        "mission-event-mission_event-operational-event-backfill-1"
      )

    assert historical["attrs"]["data-mission-event-kind"] == "telemetry_backfill_failed"
    assert historical["attrs"]["data-mission-event-severity"] == "error"
    assert historical["attrs"]["data-phx-link"] == "patch"
    assert historical["attrs"]["data-phx-link-state"] == "push"
    assert historical["attrs"]["class"] =~ "border-l-2 border-primary bg-primary/10"

    selected = presentation["body"]["detail"]["selected"]
    assert selected["header"]["title"]["attrs"]["id"] == "timeline-selected-event-title"

    copy = selected["copy"]

    assert copy["host_attrs"] == %{
             "id" => "timeline-copy-event-link-component",
             "class" => "contents"
           }

    assert copy["button_id"] == "timeline-copy-event-link"
    assert copy["clipboard_text"] =~ "/missions/#{mission.mission_id}/ops/timeline?"

    assert copy["clipboard_text"] =~
             "event_id=#{URI.encode_www_form(historical_mission_event_id)}"

    assert copy["button_class"] == "btn btn-xs btn-outline w-full justify-start"
    assert copy["icon"] == "hero-link"
    assert copy["icon_class"] == "h-3.5 w-3.5"
    assert copy["label"] == "Copy canonical event link"

    owner = selected["investigation"]["links"]["owner"]["attrs"]

    assert owner["id"] == "timeline-open-event-owner"
    assert owner["data-phx-link"] == "redirect"
    assert owner["data-phx-link-state"] == "push"
    assert owner["href"] =~ "/ops/data-operations"
    assert owner["href"] =~ "group=historical-group-1"

    explore = selected["investigation"]["links"]["explore"]["attrs"]

    assert explore["id"] == "timeline-explore-event"
    assert explore["data-phx-link"] == "redirect"
    assert explore["href"] =~ "/ops/explore"
    assert explore["href"] =~ "point_id=HK.counter"

    return_link = presentation["header"]["return_link"]["attrs"]

    assert return_link["id"] == "timeline-return-to-origin"
    assert return_link["data-phx-link"] == "redirect"
    assert return_link["href"] =~ "/ops/dashboards/#{dashboard.dashboard_id}"
    assert return_link["href"] =~ "replay_run_id=replay-1"
    assert return_link["href"] =~ "selected_data_view=all_revisions"
    assert return_link["href"] =~ "source_binding_id=flight-binding"

    render_hook(view, "apply_timeline_filters", %{
      "timeline" => %{
        "category" => "health",
        "kind" => "",
        "severity" => "",
        "spacecraft_id" => "",
        "from" => "2026-08-01T11:00:00Z",
        "to" => "2026-08-01T13:00:00Z"
      }
    })

    health_vue = timeline_vue(view)

    assert timeline_row(
             health_vue,
             "mission-event-mission_event-operational-event-source-health-1"
           )

    refute timeline_row(
             health_vue,
             "mission-event-mission_event-operational-event-backfill-1"
           )

    render_hook(view, "apply_timeline_filters", %{
      "timeline" => %{
        "category" => "operations",
        "kind" => "scheduled_contact_interval",
        "severity" => "",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "from" => "2026-08-01T11:00:00Z",
        "to" => "2026-08-01T13:00:00Z"
      }
    })

    contact_event_dom_id =
      "#mission-event-mission_event-operational_event-scheduled_contact_interval-timeline-scheduled-contact"

    contact_event_dom_id = String.trim_leading(contact_event_dom_id, "#")
    contact_vue = timeline_vue(view)
    contact_event = timeline_row!(contact_vue, contact_event_dom_id)

    assert contact_event["attrs"]["data-phx-link"] == "patch"
    render_patch(view, contact_event["attrs"]["href"])

    selected_contact =
      view
      |> timeline_vue()
      |> then(& &1.props["presentation"]["body"]["detail"]["selected"])

    contact_owner = selected_contact["investigation"]["links"]["owner"]["attrs"]

    assert contact_owner["id"] == "timeline-open-event-owner"

    assert contact_owner["href"] ==
             "/missions/#{mission.mission_id}/ops/contacts/records/#{scheduled_contact.scheduled_contact_id}"

    assert CadenceWeb.OpsTimelineLive.presentation_attrs(%{
             "nil" => nil,
             "false" => false,
             "true" => true,
             "empty" => "",
             "string_false" => "false",
             "string" => "value",
             "number" => 7
           }) == %{
             "true" => "",
             "empty" => "",
             "string_false" => "false",
             "string" => "value",
             "number" => "7"
           }
  end

  defp timeline_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-timeline-page-component")
  end

  defp timeline_row(vue, dom_id) do
    Enum.find(timeline_rows(vue), &(&1["__dom_id"] == dom_id))
  end

  defp timeline_row!(vue, dom_id) do
    timeline_row(vue, dom_id) || flunk("missing timeline stream row #{dom_id}")
  end

  defp timeline_rows(vue) do
    vue.streams_diff
    |> Enum.flat_map(fn
      ["upsert", "/timeline_events/" <> _index, event] -> [event]
      _operation -> []
    end)
  end
end
