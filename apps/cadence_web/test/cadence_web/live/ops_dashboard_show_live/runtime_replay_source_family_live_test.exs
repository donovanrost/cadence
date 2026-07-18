defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures

  alias CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceScenario,
    as: ReplayTransportRuntimeEvidenceScenario

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.Schemas.ReplayRunRow
  alias Cadence.Replay.Run
  alias Cadence.Repo

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  test "replay URL runtime params drive event and operational observable source families" do
    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)

    replay_run =
      Run.new(%{
        replay_run_id: "replay_run_events_ops",
        mission_id: mission.mission_id,
        binding_set_id: "replay-events-ops-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 0,
        replayed_sample_count: 0,
        started_at: ~U[2026-06-17 11:59:00Z],
        completed_at: ~U[2026-06-17 12:06:00Z]
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "dashboard-replay-contact-alpha",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: DateTime.from_unix!(1_700_000_080, :second),
        ends_at: DateTime.from_unix!(1_700_000_220, :second)
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    replay_contact_starts_at = ~U[2026-06-17 12:01:00Z]
    replay_contact_ends_at = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _contact_operational_event} =
             Event.new(%{
               event_id:
                 "operational_event:scheduled_contact_interval:#{scheduled_contact.scheduled_contact_id}:replay_run_events_ops",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               occurred_at: replay_contact_starts_at,
               recorded_at: replay_contact_starts_at,
               effective_at: replay_contact_starts_at,
               category: :contact,
               kind: :scheduled_contact_interval,
               severity: :info,
               actor: %{kind: :replay, id: "replay_run_events_ops"},
               subject: %{kind: :contact, id: scheduled_contact.scheduled_contact_id},
               scope: %{
                 replay_run_id: "replay_run_events_ops",
                 source_endpoint_ref: "source-endpoint-alpha"
               },
               causality: %{
                 correlation_id: scheduled_contact.scheduled_contact_id,
                 replay_run_id: "replay_run_events_ops"
               },
               payload: %{
                 scheduled_contact_id: scheduled_contact.scheduled_contact_id,
                 starts_at: replay_contact_starts_at,
                 ends_at: replay_contact_ends_at,
                 status: :scheduled,
                 source_endpoint_refs: scheduled_contact.source_endpoint_refs
               }
             })
             |> OperationalEvents.persist_event()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Event Operations",
        widgets: [
          %{
            type: :event_timeline,
            title: "Replay Mission Events",
            binding: %{source: :events, observables: []}
          },
          %{
            type: :status_matrix,
            title: "Replay Contact Phase",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "events" => %{
                    "source_binding_id" => replay_sources.events_binding_id
                  },
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    events_widget = render_item_by_title(document, "Replay Mission Events").widget
    matrix_widget = render_item_by_title(document, "Replay Contact Phase").widget

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=replay_run_events_ops"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-dashboard-replay-run-id="replay_run_events_ops"][data-dashboard-data-realm="replay"])
           )

    event_row_selector =
      ~s(#widget-#{events_widget.widget_id} [data-event-timeline-record-id="#{scheduled_contact.scheduled_contact_id}"])

    assert has_element?(
             view,
             event_row_selector <>
               ~s([data-event-timeline-logical-source="events"][data-event-timeline-realm="replay"][data-event-timeline-data-source-id="#{replay_sources.events_data_source_id}"][data-event-timeline-source-binding-id="#{replay_sources.events_binding_id}"][data-event-timeline-replay-run-id="replay_run_events_ops"][data-event-timeline-dataset="mission_events_replay"])
           )

    assert has_element?(
             view,
             event_row_selector <>
               ~s( [data-event-timeline-row-link-target="contact"][data-event-timeline-row-link-id="#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    matrix_row_selector =
      ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="contacts.phase:#{scheduled_contact.scheduled_contact_id}"])

    assert has_element?(
             view,
             matrix_row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="contact_phase"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="replay_run_events_ops"][data-status-matrix-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             matrix_row_selector <>
               ~s( [data-status-matrix-row-link-target="contact"][data-status-matrix-row-link-id="#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             matrix_row_selector <>
               ~s( [data-status-matrix-row-evidence="contacts.phase:#{scheduled_contact.scheduled_contact_id}"][phx-value-replay-run-id="replay_run_events_ops"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    stop_dashboard_view(view)
  end

  test "opens replay command queue entry evidence from rendered operational observable frame panel" do
    replay_run_id = "replay_run_command_queue_ops"

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    queue_entry =
      persist_command_queue_entry!(
        org,
        mission,
        "replay-command-queue-entry-1",
        "replay-command-endpoint"
      )

    _released_entry =
      persist_command_queue_entry!(
        org,
        mission,
        "replay-command-queue-entry-released",
        "replay-command-endpoint",
        :released
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Command Queue Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget = render_item_by_title(document, "Replay Command Queue").widget
    matrix_widget_id = matrix_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="commanding.queue_depth:#{mission.mission_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="metric_value"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-product-family="commanding"][data-status-matrix-supported-capability="command_queue_depth"])
           )

    assert has_element?(
             view,
             row_selector <> ~s( [data-status-matrix-field="value"]),
             "1"
           )

    assert has_element?(
             view,
             row_selector <>
               ~s( [data-status-matrix-row-evidence="commanding.queue_depth:#{mission.mission_id}"][data-status-matrix-row-evidence-observable="commanding.queue_depth"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"
    assert evidence_path =~ "selected_observable=commanding.queue_depth"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])
           )

    refute has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-id="replay-command-queue-entry-released"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("commanding.queue_depth")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    command_queue_entry_route_id = URI.encode_www_form(queue_entry.command_queue_entry_id)
    command_queue_entry_at_ms = DateTime.to_unix(queue_entry.enqueued_at, :millisecond)

    command_queue_entry_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])

    view
    |> element(command_queue_entry_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_queue_entry:#{queue_entry.command_queue_entry_id}",
      "target" => "command_queue_entry",
      "target-id" => queue_entry.command_queue_entry_id,
      "timestamp-ms" => command_queue_entry_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    command_queue_entry_path = assert_patch(view)
    assert command_queue_entry_path =~ "panel=data_link"
    assert command_queue_entry_path =~ "selected_target=command_queue_entry"
    assert command_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_queue_entry_path =~ "selected_time=#{command_queue_entry_at_ms}"
    assert command_queue_entry_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    command_queue_entry_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert command_queue_entry_copied_path =~ "panel=data_link"
    assert command_queue_entry_copied_path =~ "selected_target=command_queue_entry"
    assert command_queue_entry_copied_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_queue_entry_copied_path =~ "selected_time=#{command_queue_entry_at_ms}"
    assert command_queue_entry_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert command_queue_entry_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert command_queue_entry_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_command_queue_entry_view, _html} = live(conn, command_queue_entry_copied_path)

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "pending"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-command-endpoint"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Queue lane"]),
             "replay-command-endpoint"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Priority"]),
             "3"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Enqueued at"]),
             "2026-06-17T12:00:00"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

    assert has_element?(reopened_command_queue_entry_view, command_request_related_selector)

    reopened_command_queue_entry_view
    |> element(command_request_related_selector)
    |> render_click()

    command_request_path = assert_patch(reopened_command_queue_entry_view)
    command_request_route_id = URI.encode_www_form(queue_entry.command_request_id)
    assert command_request_path =~ "panel=data_link"
    assert command_request_path =~ "selected_target=command_request"
    assert command_request_path =~ "selected_id=#{command_request_route_id}"
    assert command_request_path =~ "nav_from_target=command_queue_entry"
    assert command_request_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
    assert command_request_path =~ "nav_trail="
    assert command_request_path =~ "replay_run_id=#{replay_run_id}"

    assert command_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert command_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_queue_entry"][data-clipboard-text*="nav_from_target_id=#{command_queue_entry_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    command_request_copied_path =
      reopened_command_queue_entry_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert command_request_copied_path =~ "panel=data_link"
    assert command_request_copied_path =~ "selected_target=command_request"
    assert command_request_copied_path =~ "selected_id=#{command_request_route_id}"
    assert command_request_copied_path =~ "nav_from_target=command_queue_entry"
    assert command_request_copied_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
    assert command_request_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert command_request_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert command_request_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_command_request_view, _html} = live(conn, command_request_copied_path)

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "queued"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-command-endpoint"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command id"]),
             queue_entry.command_queue_entry_id <> "-command"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested at"]),
             "2026-06-17T12:00:00"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    command_request_queue_entry_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{queue_entry.command_queue_entry_id}"])

    assert has_element?(
             reopened_command_request_view,
             command_request_queue_entry_related_selector
           )

    reopened_command_request_view
    |> element(command_request_queue_entry_related_selector)
    |> render_click()

    command_request_queue_entry_path = assert_patch(reopened_command_request_view)
    assert command_request_queue_entry_path =~ "panel=data_link"
    assert command_request_queue_entry_path =~ "selected_target=command_queue_entry"
    assert command_request_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_request_queue_entry_path =~ "nav_from_target=command_request"
    assert command_request_queue_entry_path =~ "nav_from_target_id=#{command_request_route_id}"
    assert command_request_queue_entry_path =~ "replay_run_id=#{replay_run_id}"

    assert command_request_queue_entry_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert command_request_queue_entry_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_request"][data-clipboard-text*="nav_from_target_id=#{command_request_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    command_request_queue_entry_copied_path =
      reopened_command_request_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert command_request_queue_entry_copied_path =~ "panel=data_link"
    assert command_request_queue_entry_copied_path =~ "selected_target=command_queue_entry"

    assert command_request_queue_entry_copied_path =~
             "selected_id=#{command_queue_entry_route_id}"

    assert command_request_queue_entry_copied_path =~ "nav_from_target=command_request"

    assert command_request_queue_entry_copied_path =~
             "nav_from_target_id=#{command_request_route_id}"

    assert command_request_queue_entry_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_command_request_queue_entry_view, _html} =
      live(conn, command_request_queue_entry_copied_path)

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_command_request_queue_entry_view)
    stop_dashboard_view(reopened_command_request_view)
    stop_dashboard_view(reopened_command_queue_entry_view)
    stop_dashboard_view(view)
  end

  test "opens replay metric sample operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_metric_sample_ops"
    observed_at = ~U[2026-06-17 12:04:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "metric-sample-replay-rendered-1",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.snr_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: "replay-source-health-endpoint",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 12.25,
        snr_db: 12.25,
        unit: "dB",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Metric Sample Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay SNR Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    metric_widget = render_item_by_title(document, "Replay SNR Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.snr_db"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.snr_db")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.snr_db")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "scope-link-id" => "link-alpha"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "metric-sample-replay-rendered-1"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.snr_db"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "12.250"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "dB"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF Eb/N0 operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_eb_n0_ops"
    observed_at = ~U[2026-06-17 12:04:55Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-ebn0-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.eb_n0_db",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 9.25,
        eb_n0_db: 9.25,
        unit: "dB",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Eb/N0 Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Eb/N0 Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    metric_widget = render_item_by_title(document, "Replay Eb/N0 Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.eb_n0_db"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.eb_n0_db")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "rf-ebn0-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.eb_n0_db"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "9.250"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "dB"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF Doppler operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_doppler_ops"
    observed_at = ~U[2026-06-17 12:05:05Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-doppler-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.doppler_hz",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: -42.5,
        doppler_hz: -42.5,
        frequency_offset_hz: -42.5,
        carrier_frequency_offset_hz: -42.5,
        unit: "Hz",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Doppler Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Doppler Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.doppler_hz"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    metric_widget = render_item_by_title(document, "Replay Doppler Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.doppler_hz"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.doppler_hz")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.doppler_hz")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "rf-doppler-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.doppler_hz"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "-42.500"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "Hz"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF symbol-rate operational-event copied route from rendered metric-history frame evidence" do
    replay_run_id = "replay_run_rf_symbol_rate_ops"
    observed_at = ~U[2026-06-17 12:05:15Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "rf-symbol-rate-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "link.symbol_rate_sps",
        resource_id: "link-alpha",
        scope_kind: :link,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        value: 1_048_000.0,
        symbol_rate_sps: 1_048_000.0,
        symbol_rate: 1_048_000.0,
        symbols_per_second: 1_048_000.0,
        unit: "sym/s",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Symbol Rate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Symbol Rate Metric",
            binding: %{
              source: :operational_observables,
              observables: ["link.symbol_rate_sps"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    metric_widget = render_item_by_title(document, "Replay Symbol Rate Metric").widget
    metric_widget_id = metric_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=link&scope_id=link-alpha"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="link"][data-dashboard-scope-id="link-alpha"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{metric_widget_id} [data-widget-frame-evidence][phx-value-observable-id="link.symbol_rate_sps"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="link"][phx-value-scope-id="link-alpha"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(metric_widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=link"
    assert evidence_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("link.symbol_rate_sps")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "link",
      "scope-id" => "link-alpha",
      "resource-id" => "link-alpha",
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id,
      "scope-link-id" => "link-alpha"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=link"
    assert metric_event_path =~ "scope_id=link-alpha"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=link"][data-clipboard-text*="scope_id=link-alpha"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_copied_path =~ "scope_kind=link"
    assert metric_event_copied_path =~ "scope_id=link-alpha"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "rf-symbol-rate-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "link.symbol_rate_sps"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "1048000"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "sym/s"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay source-endpoint ingress-latency operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_ingress_latency_ops"
    observed_at = ~U[2026-06-17 12:04:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-ingress-latency-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Replay ingress latency endpoint",
        metadata: %{"spacecraft_id" => "spacecraft-alpha"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    metric_event =
      %{
        sample_id: "ingress-latency-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "ingress.processing_latency_ms",
        resource_id: source_endpoint.source_endpoint_id,
        scope_kind: :source_endpoint,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        spacecraft_id: "spacecraft-alpha",
        value: 8.75,
        processing_latency_ms: 8.75,
        unit: "ms",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Ingress Latency Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    latency_widget = render_item_by_title(document, "Replay Ingress Latency").widget
    latency_widget_id = latency_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{latency_widget_id} [data-widget-frame-evidence][phx-value-observable-id="ingress.processing_latency_ms"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="source_endpoint"][phx-value-scope-id="#{source_endpoint.source_endpoint_id}"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(latency_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=source_endpoint"
    assert evidence_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ingress.processing_latency_ms")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "source_endpoint",
      "scope-id" => source_endpoint.source_endpoint_id,
      "resource-id" => source_endpoint.source_endpoint_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=source_endpoint"
    assert metric_event_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=source_endpoint"
    assert metric_event_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "ingress-latency-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "ingress.processing_latency_ms"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "8.750"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "ms"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay transport-bitrate operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_transport_bitrate_ops"
    observed_at = ~U[2026-06-17 12:04:45Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "transport-bitrate-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "comms.transport.downlink_bitrate",
        resource_id: transport.transport_id,
        scope_kind: :transport,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        value: 72_000.0,
        downlink_bitrate: 72_000.0,
        unit: "bit/s",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Bitrate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    bitrate_widget = render_item_by_title(document, "Replay Downlink Bitrate").widget
    bitrate_widget_id = bitrate_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=transport&scope_id=#{transport.transport_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.downlink_bitrate"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(bitrate_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("comms.transport.downlink_bitrate")}"

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=transport"
    assert evidence_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.downlink_bitrate")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "transport",
      "scope-id" => transport.transport_id,
      "resource-id" => transport.transport_id,
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=transport"
    assert metric_event_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=transport"
    assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "transport-bitrate-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "comms.transport.downlink_bitrate"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "72000"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "bit/s"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay transport-uplink-bitrate operational-event copied route from frame evidence" do
    replay_run_id = "replay_run_transport_uplink_bitrate_ops"
    observed_at = ~U[2026-06-17 12:04:50Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    metric_event =
      %{
        sample_id: "transport-uplink-bitrate-replay-rendered-alpha",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        observable_id: "comms.transport.uplink_bitrate",
        resource_id: transport.transport_id,
        scope_kind: :transport,
        transport_id: transport.transport_id,
        source_endpoint_id: source_endpoint.source_endpoint_id,
        ground_station_id: "dss-14",
        value: 5_600.0,
        uplink_bitrate: 5_600.0,
        unit: "bit/s",
        replay_run_id: replay_run_id,
        observed_at: observed_at
      }
      |> Event.from_operational_observable_metric_sample()
      |> persist_operational_event!()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Uplink Bitrate Evidence",
        widgets: [
          %{
            type: :time_series,
            title: "Replay Uplink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.uplink_bitrate"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    bitrate_widget = render_item_by_title(document, "Replay Uplink Bitrate").widget
    bitrate_widget_id = bitrate_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=transport&scope_id=#{transport.transport_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"][data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{transport.transport_id}"])

    assert has_element?(view, root_selector)

    frame_button_selector =
      ~s(#widget-#{bitrate_widget_id} [data-widget-frame-evidence][phx-value-observable-id="comms.transport.uplink_bitrate"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-requested-dataset="operational_observables_replay"][phx-value-scope-kind="transport"][phx-value-scope-id="#{transport.transport_id}"])

    assert has_element?(view, frame_button_selector)

    view
    |> element(frame_button_selector)
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(bitrate_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("comms.transport.uplink_bitrate")}"

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"
    assert evidence_path =~ "scope_kind=transport"
    assert evidence_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    metric_event_id = metric_event.event_id
    metric_event_route_id = URI.encode_www_form(metric_event_id)
    metric_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    metric_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{metric_event_id}"][data-evidence-ref-link-target="operational_event"])

    assert has_element?(view, metric_event_selector)

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("comms.transport.uplink_bitrate")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    view
    |> element(metric_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{metric_event_id}",
      "target" => "operational_event",
      "target-id" => metric_event_id,
      "timestamp-ms" => metric_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id,
      "scope-kind" => "transport",
      "scope-id" => transport.transport_id,
      "resource-id" => transport.transport_id,
      "transport-id" => transport.transport_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    metric_event_path = assert_patch(view)
    assert metric_event_path =~ "panel=data_link"
    assert metric_event_path =~ "selected_target=operational_event"
    assert metric_event_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_path =~ "replay_run_id=#{replay_run_id}"
    assert metric_event_path =~ "scope_kind=transport"
    assert metric_event_path =~ "scope_id=#{transport.transport_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"][data-clipboard-text*="scope_kind=transport"][data-clipboard-text*="scope_id=#{transport.transport_id}"])
           )

    metric_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert metric_event_copied_path =~ "panel=data_link"
    assert metric_event_copied_path =~ "selected_target=operational_event"
    assert metric_event_copied_path =~ "selected_id=#{metric_event_route_id}"
    assert metric_event_copied_path =~ "selected_time=#{metric_event_at_ms}"
    assert metric_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert metric_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert metric_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert metric_event_copied_path =~ "scope_kind=transport"
    assert metric_event_copied_path =~ "scope_id=#{transport.transport_id}"

    {:ok, reopened_metric_event_view, _html} = live(conn, metric_event_copied_path)

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{metric_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{metric_event_route_id}"][data-clipboard-text*="selected_time=#{metric_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational metric sample"]),
             "transport-uplink-bitrate-replay-rendered-alpha"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "comms.transport.uplink_bitrate"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Value"]),
             "5600"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Unit"]),
             "bit/s"
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_metric_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    stop_dashboard_view(reopened_metric_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay managed runtime action and timer evidence from rendered operational observable frame panel" do
    replay_run_id = "replay_run_managed_runtime_ops"
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    {action_event, timer_event} =
      persist_replay_managed_runtime_events!(
        org,
        mission,
        replay_run_id,
        action_at,
        timer_at
      )

    assert Map.get(action_event.payload, "request_document") == %{
             "delay_ms" => 1_000,
             "timer_key" => "flush"
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Managed Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    timeline_widget = render_item_by_title(document, "Replay Managed Runtime").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    action_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(action_at, :millisecond)}:0"

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed action requested"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:1"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed timer fired"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])

    timer_event_id = timer_event.event_id
    timer_event_route_id = URI.encode_www_form(timer_event_id)
    timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target")

    assert [^timer_event_id] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-link-id")

    view
    |> element(timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{timer_event_id}",
      "target" => "operational_event",
      "target-id" => timer_event_id,
      "timestamp-ms" => timer_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    timer_event_path = assert_patch(view)
    assert timer_event_path =~ "panel=data_link"
    assert timer_event_path =~ "selected_target=operational_event"
    assert timer_event_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert timer_event_copied_path =~ "panel=data_link"
    assert timer_event_copied_path =~ "selected_target=operational_event"
    assert timer_event_copied_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_copied_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert timer_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert timer_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_timer_event_view, _html} = live(conn, timer_event_copied_path)

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_managed_timer_runtime_context!(reopened_timer_event_view, replay_run_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    {:ok, action_evidence_view, _html} = live(conn, evidence_path)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      action_evidence_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    action_evidence_view
    |> element(action_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{action_event_id}",
      "target" => "operational_event",
      "target-id" => action_event_id,
      "timestamp-ms" => action_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    action_event_path = assert_patch(action_evidence_view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_copied_path =
      action_evidence_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_copied_path =~ "panel=data_link"
    assert action_event_copied_path =~ "selected_target=operational_event"
    assert action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_event_view, _html} = live(conn, action_event_copied_path)

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed action request"]),
             "managed-action-request-1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "schedule_timer"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "timer_key"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed action request"])
           )

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"])
           )

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    stop_dashboard_view(action_evidence_view)
    stop_dashboard_view(view)
  end

  test "opens live managed runtime action and timer operational-event copied routes from frame evidence" do
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    {action_event, timer_event} =
      persist_live_managed_runtime_events!(org, mission, action_at, timer_at)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Managed Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Managed Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Managed Runtime").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])

    assert has_element?(view, root_selector)

    action_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(action_at, :millisecond)}:0"

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed action requested"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:1"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed timer fired"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
           )

    timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])

    timer_event_id = timer_event.event_id
    timer_event_route_id = URI.encode_www_form(timer_event_id)
    timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target")

    assert [^timer_event_id] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-link-id")

    view
    |> element(timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{timer_event_id}",
      "target" => "operational_event",
      "target-id" => timer_event_id,
      "timestamp-ms" => timer_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    timer_event_path = assert_patch(view)
    assert timer_event_path =~ "panel=data_link"
    assert timer_event_path =~ "selected_target=operational_event"
    assert timer_event_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert timer_event_copied_path =~ "panel=data_link"
    assert timer_event_copied_path =~ "selected_target=operational_event"
    assert timer_event_copied_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_copied_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_copied_path =~ "time_mode=live"
    assert timer_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert timer_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_timer_event_view, _html} = live(conn, timer_event_copied_path)

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"])
           )

    assert_live_managed_timer_runtime_context!(reopened_timer_event_view)

    {:ok, action_evidence_view, _html} = live(conn, evidence_path)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      action_evidence_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    action_evidence_view
    |> element(action_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{action_event_id}",
      "target" => "operational_event",
      "target-id" => action_event_id,
      "timestamp-ms" => action_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    action_event_path = assert_patch(action_evidence_view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "time_mode=live"

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    action_event_copied_path =
      action_evidence_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_copied_path =~ "panel=data_link"
    assert action_event_copied_path =~ "selected_target=operational_event"
    assert action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_copied_path =~ "time_mode=live"
    assert action_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert action_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_action_event_view, _html} = live(conn, action_event_copied_path)

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed action request"]),
             "managed-action-request-live-1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "schedule_timer"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "timer_key"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-live-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-live-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-live-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-live-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-live-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    stop_dashboard_view(action_evidence_view)
    stop_dashboard_view(reopened_action_event_view)
    stop_dashboard_view(reopened_timer_event_view)
    stop_dashboard_view(view)
  end

  test "opens live managed capability-record operational-event copied route from frame evidence" do
    initialized_at = ~U[2026-06-17 12:00:30Z]
    record_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    capability_events =
      persist_live_managed_capability_record_events!(
        org,
        mission,
        initialized_at,
        record_at,
        timer_at
      )

    record_event =
      Enum.find(capability_events, &(&1.kind == :managed_capability_record_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["managed-action-request-live-2"],
             "emitted_record_refs" => ["limit-state-live-1", "derived-metric-live-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Managed Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Managed Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Managed Capability").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    initialized_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(initialized_at, :millisecond)}:0"

    record_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(record_at, :millisecond)}:1"

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    initialized_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{initialized_row_id}"])

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             initialized_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability initialized"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability record handled"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability timer handled"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for capability_event <- capability_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{capability_event.event_id}"])
             )
    end

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
           )

    record_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{record_event.event_id}"])

    record_event_id = record_event.event_id
    record_event_route_id = URI.encode_www_form(record_event_id)
    record_event_at_ms = DateTime.to_unix(record_at, :millisecond)

    record_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(record_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target")

    assert [^record_event_id] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(record_event_evidence, "phx-value-link-id")

    view
    |> element(record_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{record_event_id}",
      "target" => "operational_event",
      "target-id" => record_event_id,
      "timestamp-ms" => record_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    record_event_path = assert_patch(view)
    assert record_event_path =~ "panel=data_link"
    assert record_event_path =~ "selected_target=operational_event"
    assert record_event_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    record_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert record_event_copied_path =~ "panel=data_link"
    assert record_event_copied_path =~ "selected_target=operational_event"
    assert record_event_copied_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_copied_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_copied_path =~ "time_mode=live"
    assert record_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert record_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_record_event_view, _html} = live(conn, record_event_copied_path)

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed capability record"]),
             "managed-capability-record-live-handled-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "record_handled"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-live-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-live-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-live-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-live-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-live-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "derived_metric"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "2"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "heartbeat_count"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "managed-action-request-live-2"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "limit-state-live-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "derived-metric-live-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end

  test "opens live transport runtime capability-record operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    record_event =
      Enum.find(transport_events, &(&1.kind == :transport_control_input_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["transport-action-request-live-1"],
             "emitted_record_refs" => ["uplink-frame-live-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Capability").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    record_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(record_at, :millisecond)}:0"

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{record_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(record_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    record_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{record_event.event_id}"])

    record_event_id = record_event.event_id
    record_event_route_id = URI.encode_www_form(record_event_id)
    record_event_at_ms = DateTime.to_unix(record_at, :millisecond)

    record_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(record_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target")

    assert [^record_event_id] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(record_event_evidence, "phx-value-link-id")

    view
    |> element(record_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{record_event_id}",
      "target" => "operational_event",
      "target-id" => record_event_id,
      "timestamp-ms" => record_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    record_event_path = assert_patch(view)
    assert record_event_path =~ "panel=data_link"
    assert record_event_path =~ "selected_target=operational_event"
    assert record_event_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    record_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert record_event_copied_path =~ "panel=data_link"
    assert record_event_copied_path =~ "selected_target=operational_event"
    assert record_event_copied_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_copied_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_copied_path =~ "time_mode=live"
    assert record_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert record_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_record_event_view, _html} = live(conn, record_event_copied_path)

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"])
           )

    assert_live_transport_capability_runtime_context!(reopened_record_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end

  test "opens live transport runtime action-request operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    action_event =
      Enum.find(transport_events, &(&1.kind == :transport_action_requested))

    assert Map.get(action_event.payload, "request_document") == %{
             "command_request_id" => "command-request-live-1",
             "frame_count" => 1
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Runtime").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    record_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(record_at, :millisecond)}:0"

    action_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(action_at, :millisecond)}:1"

    timer_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport action requested"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.transport_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
           )

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    view
    |> element(action_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{action_event_id}",
      "target" => "operational_event",
      "target-id" => action_event_id,
      "timestamp-ms" => action_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    action_event_path = assert_patch(view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    action_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_copied_path =~ "panel=data_link"
    assert action_event_copied_path =~ "selected_target=operational_event"
    assert action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_copied_path =~ "time_mode=live"
    assert action_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert action_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_action_event_view, _html} = live(conn, action_event_copied_path)

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"])
           )

    assert_live_transport_action_runtime_context!(reopened_action_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"])
           )

    stop_dashboard_view(reopened_action_event_view)
    stop_dashboard_view(view)
  end

  test "opens live transport runtime timer operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    timer_event =
      Enum.find(transport_events, &(&1.kind == :transport_timer_fired))

    assert Map.get(timer_event.payload, "timer_metadata") == %{
             "action_request_id" => "transport-action-request-live-1"
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Timer Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Timer",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Timer").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    timer_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])

    timer_event_id = timer_event.event_id
    timer_event_route_id = URI.encode_www_form(timer_event_id)
    timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target")

    assert [^timer_event_id] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-link-id")

    view
    |> element(timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{timer_event_id}",
      "target" => "operational_event",
      "target-id" => timer_event_id,
      "timestamp-ms" => timer_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    timer_event_path = assert_patch(view)
    assert timer_event_path =~ "panel=data_link"
    assert timer_event_path =~ "selected_target=operational_event"
    assert timer_event_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert timer_event_copied_path =~ "panel=data_link"
    assert timer_event_copied_path =~ "selected_target=operational_event"
    assert timer_event_copied_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_copied_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_copied_path =~ "time_mode=live"
    assert timer_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert timer_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_timer_event_view, _html} = live(conn, timer_event_copied_path)

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"])
           )

    assert_live_transport_timer_runtime_context!(reopened_timer_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"])
           )

    stop_dashboard_view(reopened_timer_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay managed capability record lifecycle evidence from rendered operational observable frame panel" do
    replay_run_id = "replay_run_managed_capability_record_ops"
    initialized_at = ~U[2026-06-17 12:00:30Z]
    record_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    capability_events =
      persist_replay_managed_capability_record_events!(
        org,
        mission,
        replay_run_id,
        initialized_at,
        record_at,
        timer_at
      )

    record_event =
      Enum.find(capability_events, &(&1.kind == :managed_capability_record_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["managed-action-request-2"],
             "emitted_record_refs" => ["limit-state-1", "derived-metric-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Managed Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    timeline_widget = render_item_by_title(document, "Replay Managed Capability").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])
           )

    initialized_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(initialized_at, :millisecond)}:0"

    record_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(record_at, :millisecond)}:1"

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    initialized_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{initialized_row_id}"])

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             initialized_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability initialized"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability record handled"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability timer handled"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for capability_event <- capability_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{capability_event.event_id}"])
             )
    end

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    record_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{record_event.event_id}"])

    record_event_id = record_event.event_id
    record_event_route_id = URI.encode_www_form(record_event_id)
    record_event_at_ms = DateTime.to_unix(record_at, :millisecond)

    record_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(record_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target")

    assert [^record_event_id] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(record_event_evidence, "phx-value-link-id")

    view
    |> element(record_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{record_event_id}",
      "target" => "operational_event",
      "target-id" => record_event_id,
      "timestamp-ms" => record_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    record_event_path = assert_patch(view)
    assert record_event_path =~ "panel=data_link"
    assert record_event_path =~ "selected_target=operational_event"
    assert record_event_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    record_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert record_event_copied_path =~ "panel=data_link"
    assert record_event_copied_path =~ "selected_target=operational_event"
    assert record_event_copied_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_copied_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_record_event_view, _html} = live(conn, record_event_copied_path)

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed capability record"]),
             "managed-capability-record-handled-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "record_handled"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "derived_metric"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "2"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "heartbeat_count"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "managed-action-request-2"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "limit-state-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "derived-metric-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay transport runtime action evidence from rendered operational observable frame panel" do
    ReplayTransportRuntimeEvidenceScenario.run()
  end

  test "opens replay source-health and connection interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_source_health_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _connection_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "connection-replay-source-health-1",
               :degraded,
               observed_at,
               replay_run_id: replay_run_id,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [connection_interval] =
      Cadence.operational_connection_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "comms.transport.connection_state",
        resource_id: transport.transport_id,
        replay_run_id: replay_run_id
      )

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Source Health Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget = render_item_by_title(document, "Replay Connection State").widget
    matrix_widget_id = matrix_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{source_health_event.data_source_id}"][data-status-matrix-source-binding-id="#{source_health_event.source_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-connection-state="degraded"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"
    assert evidence_path =~ "selected_observable=comms.transport.connection_state"
    assert evidence_path =~ "selected_data_source=#{source_health_event.data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{source_health_event.source_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport connection state interval"][data-evidence-ref-id="#{connection_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{connection_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.connection_state"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    source_health_interval_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])

    view
    |> element(source_health_interval_selector)
    |> render_click()

    source_health_interval_route_id = URI.encode_www_form(source_health_interval.interval_id)
    source_health_interval_path = assert_patch(view)

    assert source_health_interval_path =~ "panel=data_link"
    assert source_health_interval_path =~ "selected_target=source_health_interval"
    assert source_health_interval_path =~ "selected_id=#{source_health_interval_route_id}"
    assert source_health_interval_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    source_health_interval_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    {:ok, reopened_source_health_interval_view, _html} =
      live(conn, source_health_interval_copied_path)

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"])
           )

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational interval"]),
             source_health_interval.interval_id
           )

    assert has_element?(
             reopened_source_health_interval_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source event"]),
             source_health_interval.source_event_id
           )

    stop_dashboard_view(reopened_source_health_interval_view)
    stop_dashboard_view(view)

    {:ok, view, _html} = live(conn, evidence_path)

    connection_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{connection_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    connection_operational_event_id = connection_interval.source_event_id
    connection_operational_event_route_id = URI.encode_www_form(connection_operational_event_id)
    connection_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    connection_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(connection_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-target")

    assert [^connection_operational_event_id] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(connection_operational_event_evidence, "phx-value-link-id")

    view
    |> element(connection_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{connection_operational_event_id}",
      "target" => "operational_event",
      "target-id" => connection_operational_event_id,
      "timestamp-ms" => connection_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    connection_event_path = assert_patch(view)
    assert connection_event_path =~ "panel=data_link"
    assert connection_event_path =~ "selected_target=operational_event"
    assert connection_event_path =~ "selected_id=#{connection_operational_event_route_id}"
    assert connection_event_path =~ "selected_time=#{connection_event_at_ms}"
    assert connection_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    connection_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert connection_event_copied_path =~ "panel=data_link"
    assert connection_event_copied_path =~ "selected_target=operational_event"
    assert connection_event_copied_path =~ "selected_id=#{connection_operational_event_route_id}"
    assert connection_event_copied_path =~ "selected_time=#{connection_event_at_ms}"
    assert connection_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert connection_event_copied_path =~ "data_source_id=#{source_health_event.data_source_id}"

    assert connection_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_connection_event_view, _html} = live(conn, connection_event_copied_path)

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{connection_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{connection_operational_event_route_id}"][data-clipboard-text*="selected_time=#{connection_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "connection-replay-source-health-1"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
             "degraded"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "comms.transport.connection_state"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "transport"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Adapter"]),
             "tcp_socket"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "degraded"
           )

    assert has_element?(
             reopened_connection_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "connection-replay-source-health-1"
           )

    stop_dashboard_view(reopened_connection_event_view)
    stop_dashboard_view(view)

    {:ok, view, _html} = live(conn, evidence_path)

    source_health_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    source_health_operational_event_id = source_health_interval.source_event_id

    source_health_operational_event_route_id =
      URI.encode_www_form(source_health_operational_event_id)

    source_health_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    source_health_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(source_health_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-target")

    assert [^source_health_operational_event_id] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(source_health_operational_event_evidence, "phx-value-link-id")

    view
    |> element(source_health_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{source_health_operational_event_id}",
      "target" => "operational_event",
      "target-id" => source_health_operational_event_id,
      "timestamp-ms" => source_health_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    source_health_event_path = assert_patch(view)
    assert source_health_event_path =~ "panel=data_link"
    assert source_health_event_path =~ "selected_target=operational_event"
    assert source_health_event_path =~ "selected_id=#{source_health_operational_event_route_id}"
    assert source_health_event_path =~ "selected_time=#{source_health_event_at_ms}"
    assert source_health_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    source_health_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_health_event_copied_path =~ "panel=data_link"
    assert source_health_event_copied_path =~ "selected_target=operational_event"

    assert source_health_event_copied_path =~
             "selected_id=#{source_health_operational_event_route_id}"

    assert source_health_event_copied_path =~ "selected_time=#{source_health_event_at_ms}"
    assert source_health_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_health_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert source_health_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_source_health_event_view, _html} = live(conn, source_health_event_copied_path)

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{source_health_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{source_health_operational_event_route_id}"][data-clipboard-text*="selected_time=#{source_health_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health event"]),
             source_health_event.source_health_event_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Logical source"]),
             "operational_observables"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Data source"]),
             source_health_event.data_source_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source binding"]),
             source_health_event.source_binding_id
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realm"]),
             "replay"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Dataset"]),
             "operational_observables_replay"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
             "degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health"]),
             "degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Reason"]),
             "source_probe_failed"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source payload"]),
             "Replay operational observables source probe degraded"
           )

    assert has_element?(
             reopened_source_health_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source health event"]),
             source_health_event.source_health_event_id
           )

    stop_dashboard_view(reopened_source_health_event_view)
    stop_dashboard_view(view)
  end

  test "reopens replay source-health interval copied from rendered frame evidence" do
    observed_at = ~U[2026-07-11 12:02:00Z]
    replay_run_id = "replay_run_source_health_interval_route"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _connection_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "connection-replay-source-health-interval-route",
               :degraded,
               observed_at,
               replay_run_id: replay_run_id,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Source Health Interval Route",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget_id =
      document
      |> render_item_by_title("Replay Connection State")
      |> Map.fetch!(:widget)
      |> Map.fetch!(:widget_id)

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    interval_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"][data-evidence-ref-link-target="source_health_interval"])

    assert has_element?(view, interval_selector)

    view
    |> element(interval_selector)
    |> render_click()

    interval_route_id = URI.encode_www_form(source_health_interval.interval_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert copied_path =~ "selected_target=source_health_interval"
    assert copied_path =~ "selected_id=#{interval_route_id}"
    assert copied_path =~ "replay_run_id=#{replay_run_id}"
    assert copied_path =~ "data_source_id=#{source_health_event.data_source_id}"
    assert copied_path =~ "source_binding_id=#{source_health_event.source_binding_id}"

    stop_dashboard_view(view)

    {:ok, reopened_view, _html} = live(conn, copied_path)

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"][data-data-link-target-id="#{source_health_interval.interval_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational interval"]),
             source_health_interval.interval_id
           )

    assert has_element?(
             reopened_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source event"]),
             source_health_interval.source_event_id
           )

    stop_dashboard_view(reopened_view)
  end

  test "opens replay antenna pointing operational-event copied route from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:03:00Z]
    replay_run_id = "replay_run_antenna_pointing_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _antenna_pointing_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "antenna-pointing-replay-rendered-1",
               :tracking,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "ground.station.antenna_pointing_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [antenna_pointing_interval] =
      Cadence.operational_observable_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "ground.station.antenna_pointing_state",
        resource_id: "dss-14",
        replay_run_id: replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Antenna Pointing Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Antenna Pointing",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget = render_item_by_title(document, "Replay Antenna Pointing").widget
    matrix_widget_id = matrix_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="ground.station.antenna_pointing_state:dss-14"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-ground-station-id="dss-14"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"

    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="ground station antenna pointing state interval"][data-evidence-ref-id="#{antenna_pointing_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{antenna_pointing_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ground.station.antenna_pointing_state")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    antenna_pointing_event_id = antenna_pointing_interval.source_event_id
    antenna_pointing_event_route_id = URI.encode_www_form(antenna_pointing_event_id)
    antenna_pointing_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    antenna_pointing_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{antenna_pointing_event_id}"][data-evidence-ref-link-target="operational_event"])

    view
    |> element(antenna_pointing_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{antenna_pointing_event_id}",
      "target" => "operational_event",
      "target-id" => antenna_pointing_event_id,
      "timestamp-ms" => antenna_pointing_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    antenna_pointing_event_path = assert_patch(view)
    assert antenna_pointing_event_path =~ "panel=data_link"
    assert antenna_pointing_event_path =~ "selected_target=operational_event"
    assert antenna_pointing_event_path =~ "selected_id=#{antenna_pointing_event_route_id}"
    assert antenna_pointing_event_path =~ "selected_time=#{antenna_pointing_event_at_ms}"
    assert antenna_pointing_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    antenna_pointing_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert antenna_pointing_event_copied_path =~ "panel=data_link"
    assert antenna_pointing_event_copied_path =~ "selected_target=operational_event"

    assert antenna_pointing_event_copied_path =~
             "selected_id=#{antenna_pointing_event_route_id}"

    assert antenna_pointing_event_copied_path =~ "selected_time=#{antenna_pointing_event_at_ms}"
    assert antenna_pointing_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert antenna_pointing_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert antenna_pointing_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_antenna_pointing_event_view, _html} =
      live(conn, antenna_pointing_event_copied_path)

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{antenna_pointing_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{antenna_pointing_event_route_id}"][data-clipboard-text*="selected_time=#{antenna_pointing_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational observable snapshot"]),
             "antenna-pointing-replay-rendered-1"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "ground.station.antenna_pointing_state"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "dss-14"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "ground_station"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "tracking"
           )

    assert has_element?(
             reopened_antenna_pointing_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational observable snapshot"]),
             "antenna-pointing-replay-rendered-1"
           )

    stop_dashboard_view(reopened_antenna_pointing_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay source-health and ground-station connection interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_ground_station_connection_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _connection_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "ground-station-connection-replay-source-health-1",
               :connected,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "ground.station.connection_state",
               resource_id: "dss-14",
               scope_kind: :ground_station,
               transport_id: transport.transport_id
             )
             |> OperationalEvents.persist_event()

    [ground_station_interval] =
      Cadence.operational_connection_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "ground.station.connection_state",
        resource_id: "dss-14",
        replay_run_id: replay_run_id
      )

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Ground Station Connection Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Ground Station Connection",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.connection_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    matrix_widget = render_item_by_title(document, "Replay Ground Station Connection").widget
    matrix_widget_id = matrix_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_selector =
      ~s(#widget-#{matrix_widget_id} [data-status-matrix-row="ground.station.connection_state:dss-14"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{source_health_event.data_source_id}"][data-status-matrix-source-binding-id="#{source_health_event.source_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-resource-id="dss-14"][data-status-matrix-scope-kind="ground_station"][data-status-matrix-ground-station-id="dss-14"][data-status-matrix-connection-state="connected"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget_id)}"

    assert evidence_path =~
             "selected_observable=#{URI.encode_www_form("ground.station.connection_state")}"

    assert evidence_path =~ "selected_data_source=#{source_health_event.data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{source_health_event.source_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="ground station connection state interval"][data-evidence-ref-id="#{ground_station_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{ground_station_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("ground.station.connection_state")}"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    ground_station_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{ground_station_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    ground_station_operational_event_id = ground_station_interval.source_event_id

    ground_station_operational_event_route_id =
      URI.encode_www_form(ground_station_operational_event_id)

    ground_station_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    ground_station_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(ground_station_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-target")

    assert [^ground_station_operational_event_id] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(ground_station_operational_event_evidence, "phx-value-link-id")

    view
    |> element(ground_station_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{ground_station_operational_event_id}",
      "target" => "operational_event",
      "target-id" => ground_station_operational_event_id,
      "timestamp-ms" => ground_station_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    ground_station_event_path = assert_patch(view)
    assert ground_station_event_path =~ "panel=data_link"
    assert ground_station_event_path =~ "selected_target=operational_event"
    assert ground_station_event_path =~ "selected_id=#{ground_station_operational_event_route_id}"
    assert ground_station_event_path =~ "selected_time=#{ground_station_event_at_ms}"
    assert ground_station_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    ground_station_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert ground_station_event_copied_path =~ "panel=data_link"
    assert ground_station_event_copied_path =~ "selected_target=operational_event"

    assert ground_station_event_copied_path =~
             "selected_id=#{ground_station_operational_event_route_id}"

    assert ground_station_event_copied_path =~ "selected_time=#{ground_station_event_at_ms}"
    assert ground_station_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert ground_station_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert ground_station_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_ground_station_event_view, _html} =
      live(conn, ground_station_event_copied_path)

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{ground_station_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{ground_station_operational_event_route_id}"][data-clipboard-text*="selected_time=#{ground_station_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "ground-station-connection-replay-source-health-1"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state"]),
             "connected"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             "ground.station.connection_state"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "dss-14"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "ground_station"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Adapter"]),
             "tcp_socket"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State"]),
             "connected"
           )

    assert has_element?(
             reopened_ground_station_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Connection state snapshot"]),
             "ground-station-connection-replay-source-health-1"
           )

    stop_dashboard_view(reopened_ground_station_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay source-health and transport execution interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_transport_execution_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _transport_execution_event} =
             transport_capability_record(
               mission.mission_id,
               "transport-execution-replay-source-health-1",
               transport.transport_id,
               :initialized,
               observed_at,
               state_snapshot: %{active?: true, heartbeat_count: 1}
             )
             |> Event.from_transport_capability_record(replay_run_id)
             |> OperationalEvents.persist_event()

    [transport_execution_interval] =
      Cadence.operational_transport_execution_intervals(org.organization_id, mission.mission_id,
        capability_instance_id: transport.transport_id,
        replay_run_id: replay_run_id,
        order: :asc
      )

    {source_health_event, source_health_interval} =
      record_replay_operational_source_health!(
        org,
        mission,
        replay_sources,
        observed_at,
        replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Execution Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Transport Execution",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    timeline_widget = render_item_by_title(document, "Replay Transport Execution").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    row_id =
      "state:comms.transport.execution_state:#{DateTime.to_unix(observed_at, :millisecond)}:0"

    row_selector = ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{row_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-state-timeline-observable="comms.transport.execution_state"][data-state-timeline-state="Initialized"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{source_health_event.data_source_id}"][data-state-timeline-source-binding-id="#{source_health_event.source_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    view
    |> element(row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=comms.transport.execution_state"
    assert evidence_path =~ "selected_data_source=#{source_health_event.data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{source_health_event.source_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health interval"][data-evidence-ref-id="#{source_health_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport execution interval"][data-evidence-ref-id="#{transport_execution_interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{transport_execution_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{source_health_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="source health event"][data-evidence-ref-id="#{source_health_event.source_health_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=comms.transport.execution_state"][data-clipboard-text*="selected_data_source=#{source_health_event.data_source_id}"][data-clipboard-text*="selected_source_binding=#{source_health_event.source_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    transport_execution_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{transport_execution_interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])

    transport_execution_operational_event_id = transport_execution_interval.source_event_id

    transport_execution_operational_event_route_id =
      URI.encode_www_form(transport_execution_operational_event_id)

    transport_execution_event_at_ms = DateTime.to_unix(observed_at, :millisecond)

    transport_execution_operational_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_execution_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-target"
             )

    assert [^transport_execution_operational_event_id] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-target-id"
             )

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(
               transport_execution_operational_event_evidence,
               "phx-value-link-id"
             )

    view
    |> element(transport_execution_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{transport_execution_operational_event_id}",
      "target" => "operational_event",
      "target-id" => transport_execution_operational_event_id,
      "timestamp-ms" => transport_execution_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => source_health_event.data_source_id,
      "source-binding-id" => source_health_event.source_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    transport_execution_event_path = assert_patch(view)
    assert transport_execution_event_path =~ "panel=data_link"
    assert transport_execution_event_path =~ "selected_target=operational_event"

    assert transport_execution_event_path =~
             "selected_id=#{transport_execution_operational_event_route_id}"

    assert transport_execution_event_path =~ "selected_time=#{transport_execution_event_at_ms}"
    assert transport_execution_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{source_health_event.data_source_id}"][data-clipboard-text*="source_binding_id=#{source_health_event.source_binding_id}"])
           )

    transport_execution_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_execution_event_copied_path =~ "panel=data_link"
    assert transport_execution_event_copied_path =~ "selected_target=operational_event"

    assert transport_execution_event_copied_path =~
             "selected_id=#{transport_execution_operational_event_route_id}"

    assert transport_execution_event_copied_path =~
             "selected_time=#{transport_execution_event_at_ms}"

    assert transport_execution_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_execution_event_copied_path =~
             "data_source_id=#{source_health_event.data_source_id}"

    assert transport_execution_event_copied_path =~
             "source_binding_id=#{source_health_event.source_binding_id}"

    {:ok, reopened_transport_execution_event_view, _html} =
      live(conn, transport_execution_event_copied_path)

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_execution_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{source_health_event.data_source_id}"][data-data-link-selected-source-binding-id="#{source_health_event.source_binding_id}"])
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_execution_operational_event_route_id}"][data-clipboard-text*="selected_time=#{transport_execution_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-execution-replay-source-health-1"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "initialized"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             transport.transport_id
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "heartbeat_monitor"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "replay-binding-set-1"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "replay-activation-1"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "heartbeat_count"
           )

    assert has_element?(
             reopened_transport_execution_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-execution-replay-source-health-1"
           )

    stop_dashboard_view(reopened_transport_execution_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay RF state interval evidence from rendered operational observable frame panel" do
    observed_at = ~U[2026-06-17 12:02:00Z]
    replay_run_id = "replay_run_rf_state_ops"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)
    {_source_endpoint, transport} = persist_replay_connection_state_resources!(org, mission)

    assert {:ok, _rf_lock_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "rf-lock-replay-rendered-1",
               :locked,
               observed_at,
               replay_run_id: replay_run_id,
               observable_id: "link.rf_lock_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: transport.transport_id,
               link_id: "link-alpha"
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _frame_sync_event} =
             operational_observable_state_event(
               org.organization_id,
               mission.mission_id,
               "frame-sync-replay-rendered-1",
               :synchronized,
               DateTime.add(observed_at, 1, :second),
               replay_run_id: replay_run_id,
               observable_id: "link.frame_sync_state",
               resource_id: "link-alpha",
               scope_kind: :link,
               transport_id: transport.transport_id,
               link_id: "link-alpha"
             )
             |> OperationalEvents.persist_event()

    [rf_lock_interval] =
      Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "link.rf_lock_state",
        resource_id: "link-alpha",
        replay_run_id: replay_run_id
      )

    [frame_sync_interval] =
      Cadence.operational_link_rf_state_intervals(org.organization_id, mission.mission_id,
        observable_id: "link.frame_sync_state",
        resource_id: "link-alpha",
        replay_run_id: replay_run_id
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay RF Evidence",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay RF Lock",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state"]
            }
          },
          %{
            type: :status_matrix,
            title: "Replay Frame Sync",
            binding: %{
              source: :operational_observables,
              observables: ["link.frame_sync_state"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    rf_lock_widget = render_item_by_title(document, "Replay RF Lock").widget
    frame_sync_widget = render_item_by_title(document, "Replay Frame Sync").widget

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    rf_lock_row_selector =
      ~s(#widget-#{rf_lock_widget.widget_id} [data-status-matrix-row="link.rf_lock_state:link-alpha"])

    assert has_element?(
             view,
             rf_lock_row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="#{transport.transport_id}"])
           )

    open_and_assert_replay_rf_evidence!(
      view,
      conn,
      %{
        row_selector: rf_lock_row_selector,
        widget_id: rf_lock_widget.widget_id,
        observable_id: "link.rf_lock_state",
        replay_sources: replay_sources,
        replay_run_id: replay_run_id,
        interval: rf_lock_interval,
        expected_snapshot_id: "rf-lock-replay-rendered-1",
        expected_state: "locked",
        expected_transport_id: transport.transport_id
      }
    )

    frame_sync_row_selector =
      ~s(#widget-#{frame_sync_widget.widget_id} [data-status-matrix-row="link.frame_sync_state:link-alpha"])

    assert has_element?(
             view,
             frame_sync_row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-realm="replay"][data-status-matrix-data-source-id="#{replay_sources.operational_data_source_id}"][data-status-matrix-source-binding-id="#{replay_sources.operational_binding_id}"][data-status-matrix-replay-run-id="#{replay_run_id}"][data-status-matrix-dataset="operational_observables_replay"][data-status-matrix-link-id="link-alpha"][data-status-matrix-transport-id="#{transport.transport_id}"])
           )

    open_and_assert_replay_rf_evidence!(
      view,
      conn,
      %{
        row_selector: frame_sync_row_selector,
        widget_id: frame_sync_widget.widget_id,
        observable_id: "link.frame_sync_state",
        replay_sources: replay_sources,
        replay_run_id: replay_run_id,
        interval: frame_sync_interval,
        expected_snapshot_id: "frame-sync-replay-rendered-1",
        expected_state: "synchronized",
        expected_transport_id: transport.transport_id
      }
    )

    stop_dashboard_view(view)
  end
end
