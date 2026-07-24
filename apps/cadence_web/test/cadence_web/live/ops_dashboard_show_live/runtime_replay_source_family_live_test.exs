defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Control.Replay.Store.ReplayRunRow
  alias Cadence.Dashboards.Document
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  defp assert_replay_command_request_round_trip(
         conn,
         command_queue_entry_view,
         queue_entry,
         replay_run_id,
         replay_sources,
         command_queue_entry_route_id
       ) do
    command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

    assert has_element?(command_queue_entry_view, command_request_related_selector)

    command_queue_entry_view
    |> element(command_request_related_selector)
    |> render_click()

    command_request_path = assert_patch(command_queue_entry_view)
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
             command_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             command_queue_entry_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_queue_entry"][data-clipboard-text*="nav_from_target_id=#{command_queue_entry_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    command_request_copied_path =
      command_queue_entry_view
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
    stop_dashboard_view(command_queue_entry_view)
  end

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
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled_contact)

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

    assert_replay_command_request_round_trip(
      conn,
      reopened_command_queue_entry_view,
      queue_entry,
      replay_run_id,
      replay_sources,
      command_queue_entry_route_id
    )

    stop_dashboard_view(view)
  end
end
