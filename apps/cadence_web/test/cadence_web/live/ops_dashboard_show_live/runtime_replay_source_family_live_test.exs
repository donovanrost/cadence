defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandVerifierInstance
  }

  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    RenderItem,
    SourceHealth
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    OpsDashboardRow,
    PacketRecordRow,
    RawEvidenceRow,
    ReplayRunRow
  }

  alias Cadence.Protocol.PacketRecord
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.{Sample, Storage}

  alias Cadence.Runtime.{
    ManagedActionRequest,
    ManagedCapabilityRecord,
    ManagedTimerEvent,
    TransportActionRequest,
    TransportCapabilityRecord,
    TransportTimerEvent
  }

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
    replay_run_id = "replay_run_transport_runtime_activity_ops"
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    telemetry_sample =
      persist_replay_command_verifier_telemetry_sample!(
        org,
        mission,
        replay_run_id,
        telemetry_replay_source,
        DateTime.add(action_at, 10, :second)
      )

    release_attempt = persist_transport_command_release_attempt!(org, mission, action_at)

    verifier_instance =
      persist_transport_command_verifier_instance!(org, mission, release_attempt, action_at)

    failed_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 5, :second),
        command_verifier_instance_id: "verifier-instance-failed",
        verifier_name: "Transport action rejected",
        lifecycle_state: :failed,
        failure_reason: "failure_criteria_matched"
      )

    telemetry_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 10, :second),
        command_verifier_instance_id: "verifier-instance-telemetry-satisfied",
        verifier_id: "telemetry-verifier-1",
        verifier_name: "Telemetry release confirmation",
        matched_record_kind: :telemetry_sample,
        matched_record_id: telemetry_sample.sample_id
      )

    capability_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 15, :second),
        command_verifier_instance_id: "verifier-instance-capability-satisfied",
        verifier_id: "capability-verifier-1",
        verifier_name: "Transport capability confirmation",
        matched_record_kind: :transport_capability_record,
        matched_record_id: "transport-runtime-record-1"
      )

    timed_out_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 60, :second),
        command_verifier_instance_id: "verifier-instance-timed-out",
        verifier_name: "Transport completion timed out",
        lifecycle_state: :timed_out,
        matched_record_kind: nil,
        matched_record_id: nil,
        failure_reason: "timed_out"
      )

    transport_events =
      persist_replay_transport_runtime_events!(
        org,
        mission,
        replay_run_id,
        record_at,
        action_at,
        timer_at
      )

    action_event =
      Enum.find(transport_events, &(&1.kind == :transport_action_requested))

    record_event =
      Enum.find(transport_events, &(&1.kind == :transport_control_input_handled))

    assert Map.get(action_event.payload, "request_document") == %{
             "command_request_id" => "command-request-1",
             "frame_count" => 1
           }

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["transport-action-request-1"],
             "emitted_record_refs" => ["uplink-frame-1"]
           }

    assert {:ok, fetched_release_attempt} =
             Cadence.fetch_command_release_attempt(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.command_release_attempt_id ==
             release_attempt.command_release_attempt_id

    assert fetched_release_attempt.command_request_id == "command-request-1"
    assert fetched_release_attempt.verification_state == :failed

    assert {:ok, fetched_command_request} =
             Cadence.fetch_command_request(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_request_id
             )

    assert fetched_command_request.verification_state == :failed

    assert {:ok, fetched_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               verifier_instance.command_verifier_instance_id
             )

    assert fetched_verifier_instance.lifecycle_state == :satisfied
    assert fetched_verifier_instance.matched_record_id == "transport-action-request-1"

    assert {:ok, fetched_telemetry_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               telemetry_verifier_instance.command_verifier_instance_id
             )

    assert fetched_telemetry_verifier_instance.lifecycle_state == :satisfied
    assert fetched_telemetry_verifier_instance.matched_record_kind == :telemetry_sample
    assert fetched_telemetry_verifier_instance.matched_record_id == telemetry_sample.sample_id

    assert {:ok, fetched_capability_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               capability_verifier_instance.command_verifier_instance_id
             )

    assert fetched_capability_verifier_instance.lifecycle_state == :satisfied

    assert fetched_capability_verifier_instance.matched_record_kind ==
             :transport_capability_record

    assert fetched_capability_verifier_instance.matched_record_id == "transport-runtime-record-1"

    assert {:ok, fetched_failed_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               failed_verifier_instance.command_verifier_instance_id
             )

    assert fetched_failed_verifier_instance.lifecycle_state == :failed
    assert fetched_failed_verifier_instance.failure_reason == "failure_criteria_matched"

    assert {:ok, fetched_timed_out_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               timed_out_verifier_instance.command_verifier_instance_id
             )

    assert fetched_timed_out_verifier_instance.lifecycle_state == :timed_out
    assert fetched_timed_out_verifier_instance.failure_reason == "timed_out"

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Transport Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
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

    timeline_widget = render_item_by_title(document, "Replay Transport Runtime").widget
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
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport action requested"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

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
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command release attempt"][data-evidence-ref-id="#{release_attempt.command_release_attempt_id}"][data-evidence-ref-link-target="command_release_attempt"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport action request"][data-evidence-ref-id="transport-action-request-1"][data-evidence-ref-link-target="transport_action_request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="telemetry sample"][data-evidence-ref-id="#{telemetry_sample.sample_id}"][data-evidence-ref-link-target="telemetry_sample"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport capability record"][data-evidence-ref-id="transport-runtime-record-1"][data-evidence-ref-link-target="transport_capability_record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{telemetry_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{capability_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-evidence-ref-link-target="command_verifier_instance"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{timed_out_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.transport_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    release_attempt_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command release attempt"][data-evidence-ref-id="#{release_attempt.command_release_attempt_id}"])

    release_attempt_id = release_attempt.command_release_attempt_id
    release_attempt_at_ms = DateTime.to_unix(release_attempt.attempted_at, :millisecond)

    release_attempt_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(release_attempt_evidence_selector)

    assert ["command_release_attempt"] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-target")

    assert [^release_attempt_id] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-target-id")

    assert [release_attempt_at_ms_text] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-timestamp-ms")

    assert release_attempt_at_ms_text == Integer.to_string(release_attempt_at_ms)

    assert ["evidence-ref:command_release_attempt:" <> _] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-link-id")

    view
    |> element(release_attempt_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_release_attempt:#{release_attempt_id}",
      "target" => "command_release_attempt",
      "target-id" => release_attempt_id,
      "timestamp-ms" => release_attempt_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    release_attempt_path = assert_patch(view)
    assert release_attempt_path =~ "panel=data_link"
    assert release_attempt_path =~ "selected_target=command_release_attempt"
    assert release_attempt_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_path =~ "selected_time=#{release_attempt_at_ms}"
    assert release_attempt_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    release_attempt_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_copied_path =~ "panel=data_link"
    assert release_attempt_copied_path =~ "selected_target=command_release_attempt"
    assert release_attempt_copied_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_copied_path =~ "selected_time=#{release_attempt_at_ms}"
    assert release_attempt_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_release_attempt_view, _html} = live(conn, release_attempt_copied_path)

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="selected_time=#{release_attempt_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"]),
             "failed"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    release_attempt_command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{release_attempt.command_request_id}"])

    release_attempt_command_queue_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{release_attempt.command_queue_entry_id}"])

    assert has_element?(
             reopened_release_attempt_view,
             release_attempt_command_request_related_selector
           )

    assert has_element?(
             reopened_release_attempt_view,
             release_attempt_command_queue_related_selector
           )

    reopened_release_attempt_view
    |> element(release_attempt_command_request_related_selector)
    |> render_click()

    release_attempt_command_request_path = assert_patch(reopened_release_attempt_view)
    command_request_route_id = URI.encode_www_form(release_attempt.command_request_id)
    assert release_attempt_command_request_path =~ "panel=data_link"
    assert release_attempt_command_request_path =~ "selected_target=command_request"
    assert release_attempt_command_request_path =~ "selected_id=#{command_request_route_id}"
    assert release_attempt_command_request_path =~ "nav_from_target=command_release_attempt"
    assert release_attempt_command_request_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert release_attempt_command_request_path =~ "nav_trail="
    assert release_attempt_command_request_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_command_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_command_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    release_attempt_command_request_copied_path =
      reopened_release_attempt_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_command_request_copied_path =~ "panel=data_link"
    assert release_attempt_command_request_copied_path =~ "selected_target=command_request"

    assert release_attempt_command_request_copied_path =~
             "selected_id=#{command_request_route_id}"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target_id=#{release_attempt_id}"

    assert release_attempt_command_request_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_release_attempt_command_request_view, _html} =
      live(conn, release_attempt_command_request_copied_path)

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             release_attempt.command_name
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_release_attempt_command_request_view)

    {:ok, reopened_release_attempt_queue_view, _html} = live(conn, release_attempt_copied_path)

    assert has_element?(
             reopened_release_attempt_queue_view,
             release_attempt_command_queue_related_selector
           )

    reopened_release_attempt_queue_view
    |> element(release_attempt_command_queue_related_selector)
    |> render_click()

    release_attempt_command_queue_path = assert_patch(reopened_release_attempt_queue_view)
    command_queue_entry_route_id = URI.encode_www_form(release_attempt.command_queue_entry_id)
    assert release_attempt_command_queue_path =~ "panel=data_link"
    assert release_attempt_command_queue_path =~ "selected_target=command_queue_entry"
    assert release_attempt_command_queue_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert release_attempt_command_queue_path =~ "nav_from_target=command_release_attempt"
    assert release_attempt_command_queue_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert release_attempt_command_queue_path =~ "nav_trail="
    assert release_attempt_command_queue_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_command_queue_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_command_queue_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_release_attempt_queue_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{release_attempt.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_queue_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    release_attempt_command_queue_copied_path =
      reopened_release_attempt_queue_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_command_queue_copied_path =~ "panel=data_link"
    assert release_attempt_command_queue_copied_path =~ "selected_target=command_queue_entry"

    assert release_attempt_command_queue_copied_path =~
             "selected_id=#{command_queue_entry_route_id}"

    assert release_attempt_command_queue_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_command_queue_copied_path =~
             "nav_from_target_id=#{release_attempt_id}"

    assert release_attempt_command_queue_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_release_attempt_command_queue_view, _html} =
      live(conn, release_attempt_command_queue_copied_path)

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{release_attempt.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             release_attempt.command_queue_entry_id
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_release_attempt_command_queue_view)
    stop_dashboard_view(reopened_release_attempt_queue_view)
    stop_dashboard_view(reopened_release_attempt_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Metadata"])
           )

    failed_verifier_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command verifier instance"][data-data-link-related-id="#{failed_verifier_instance.command_verifier_instance_id}"])

    assert has_element?(view, failed_verifier_related_selector)

    transport_action_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="transport-action-request-1"])

    assert has_element?(view, transport_action_related_selector)

    view
    |> element(failed_verifier_related_selector)
    |> render_click()

    failed_related_path = assert_patch(view)
    assert failed_related_path =~ "panel=data_link"
    assert failed_related_path =~ "selected_target=command_verifier_instance"

    assert failed_related_path =~
             "selected_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert failed_related_path =~ "nav_from_target=command_release_attempt"
    assert failed_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert failed_related_path =~ "nav_trail="
    assert failed_related_path =~ "replay_run_id=#{replay_run_id}"
    assert failed_related_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert failed_related_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_copied_path =~ "panel=data_link"
    assert failed_verifier_copied_path =~ "selected_target=command_verifier_instance"

    assert failed_verifier_copied_path =~
             "selected_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert failed_verifier_copied_path =~ "nav_from_target=command_release_attempt"
    assert failed_verifier_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert failed_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_view, _html} = live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_instance.command_verifier_instance_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"]),
             "failure_criteria_matched"
           )

    verifier_release_attempt_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command release attempt"][data-data-link-related-id="#{release_attempt_id}"])

    verifier_command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{release_attempt.command_request_id}"])

    assert has_element?(
             reopened_failed_verifier_view,
             verifier_release_attempt_related_selector
           )

    assert has_element?(
             reopened_failed_verifier_view,
             verifier_command_request_related_selector
           )

    {:ok, reopened_failed_verifier_command_request_view, _html} =
      live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             verifier_command_request_related_selector
           )

    reopened_failed_verifier_command_request_view
    |> element(verifier_command_request_related_selector)
    |> render_click()

    verifier_command_request_path = assert_patch(reopened_failed_verifier_command_request_view)
    verifier_command_request_route_id = URI.encode_www_form(release_attempt.command_request_id)
    assert verifier_command_request_path =~ "panel=data_link"
    assert verifier_command_request_path =~ "selected_target=command_request"
    assert verifier_command_request_path =~ "selected_id=#{verifier_command_request_route_id}"
    assert verifier_command_request_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_command_request_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_command_request_path =~ "nav_trail="
    assert verifier_command_request_path =~ "replay_run_id=#{replay_run_id}"

    assert verifier_command_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_command_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{verifier_command_request_route_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    verifier_command_request_copied_path =
      reopened_failed_verifier_command_request_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_command_request_copied_path =~ "panel=data_link"
    assert verifier_command_request_copied_path =~ "selected_target=command_request"

    assert verifier_command_request_copied_path =~
             "selected_id=#{verifier_command_request_route_id}"

    assert verifier_command_request_copied_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_command_request_copied_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_command_request_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_verifier_command_request_view, _html} =
      live(conn, verifier_command_request_copied_path)

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             release_attempt.command_name
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_verifier_command_request_view)
    stop_dashboard_view(reopened_failed_verifier_command_request_view)

    reopened_failed_verifier_view
    |> element(verifier_release_attempt_related_selector)
    |> render_click()

    verifier_release_attempt_path = assert_patch(reopened_failed_verifier_view)
    assert verifier_release_attempt_path =~ "panel=data_link"
    assert verifier_release_attempt_path =~ "selected_target=command_release_attempt"
    assert verifier_release_attempt_path =~ "selected_id=#{release_attempt_id}"
    assert verifier_release_attempt_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_release_attempt_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_release_attempt_path =~ "nav_trail="
    assert verifier_release_attempt_path =~ "replay_run_id=#{replay_run_id}"

    assert verifier_release_attempt_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_release_attempt_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    verifier_release_attempt_copied_path =
      reopened_failed_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_release_attempt_copied_path =~ "panel=data_link"
    assert verifier_release_attempt_copied_path =~ "selected_target=command_release_attempt"
    assert verifier_release_attempt_copied_path =~ "selected_id=#{release_attempt_id}"
    assert verifier_release_attempt_copied_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_release_attempt_copied_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_release_attempt_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_verifier_release_attempt_view, _html} =
      live(conn, verifier_release_attempt_copied_path)

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_verifier_release_attempt_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"])
    )
    |> render_click()

    release_attempt_back_path = assert_patch(view)
    assert release_attempt_back_path =~ "panel=data_link"
    assert release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"])
           )

    source_endpoint_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="source endpoint"][data-data-link-related-id="endpoint-alpha"])

    assert has_element?(view, source_endpoint_related_selector)

    view
    |> element(source_endpoint_related_selector)
    |> render_click()

    source_endpoint_related_path = assert_patch(view)
    assert source_endpoint_related_path =~ "panel=data_link"
    assert source_endpoint_related_path =~ "selected_target=source_endpoint"
    assert source_endpoint_related_path =~ "selected_id=endpoint-alpha"
    assert source_endpoint_related_path =~ "nav_from_target=command_release_attempt"
    assert source_endpoint_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert source_endpoint_related_path =~ "nav_trail="
    assert source_endpoint_related_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="endpoint-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=source_endpoint"][data-clipboard-text*="selected_id=endpoint-alpha"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    source_endpoint_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_endpoint_copied_path =~ "panel=data_link"
    assert source_endpoint_copied_path =~ "selected_target=source_endpoint"
    assert source_endpoint_copied_path =~ "selected_id=endpoint-alpha"
    assert source_endpoint_copied_path =~ "nav_from_target=command_release_attempt"
    assert source_endpoint_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert source_endpoint_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_source_endpoint_view, _html} = live(conn, source_endpoint_copied_path)

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="endpoint-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    reopened_source_endpoint_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    source_endpoint_release_attempt_back_path = assert_patch(reopened_source_endpoint_view)
    assert source_endpoint_release_attempt_back_path =~ "panel=data_link"
    assert source_endpoint_release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert source_endpoint_release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert source_endpoint_release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_release_attempt_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_release_attempt_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    source_endpoint_release_attempt_back_copied_path =
      reopened_source_endpoint_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_endpoint_release_attempt_back_copied_path =~ "panel=data_link"

    assert source_endpoint_release_attempt_back_copied_path =~
             "selected_target=command_release_attempt"

    assert source_endpoint_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert source_endpoint_release_attempt_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_release_attempt_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_release_attempt_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_source_endpoint_release_attempt_view, _html} =
      live(conn, source_endpoint_release_attempt_back_copied_path)

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    release_attempt_resource_back_path = assert_patch(view)
    assert release_attempt_resource_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_resource_back_path =~ "selected_id=#{release_attempt_id}"

    contact_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="contact"][data-data-link-related-id="replay-contact-alpha"])

    assert has_element?(view, contact_related_selector)

    view
    |> element(contact_related_selector)
    |> render_click()

    contact_related_path = assert_patch(view)
    assert contact_related_path =~ "panel=data_link"
    assert contact_related_path =~ "selected_target=contact"
    assert contact_related_path =~ "selected_id=replay-contact-alpha"
    assert contact_related_path =~ "nav_from_target=command_release_attempt"
    assert contact_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert contact_related_path =~ "nav_trail="
    assert contact_related_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="replay-contact-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=contact"][data-clipboard-text*="selected_id=replay-contact-alpha"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    contact_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert contact_copied_path =~ "panel=data_link"
    assert contact_copied_path =~ "selected_target=contact"
    assert contact_copied_path =~ "selected_id=replay-contact-alpha"
    assert contact_copied_path =~ "nav_from_target=command_release_attempt"
    assert contact_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert contact_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert contact_copied_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert contact_copied_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_contact_view, _html} = live(conn, contact_copied_path)

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="replay-contact-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             "replay-contact-alpha"
           )

    reopened_contact_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    contact_release_attempt_back_path = assert_patch(reopened_contact_view)
    assert contact_release_attempt_back_path =~ "panel=data_link"
    assert contact_release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert contact_release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_release_attempt_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_release_attempt_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    contact_release_attempt_back_copied_path =
      reopened_contact_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert contact_release_attempt_back_copied_path =~ "panel=data_link"
    assert contact_release_attempt_back_copied_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert contact_release_attempt_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_release_attempt_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_release_attempt_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_contact_release_attempt_view, _html} =
      live(conn, contact_release_attempt_back_copied_path)

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    release_attempt_contact_back_path = assert_patch(view)
    assert release_attempt_contact_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_contact_back_path =~ "selected_id=#{release_attempt_id}"

    view
    |> element(transport_action_related_selector)
    |> render_click()

    transport_action_related_path = assert_patch(view)
    assert transport_action_related_path =~ "panel=data_link"
    assert transport_action_related_path =~ "selected_target=transport_action_request"
    assert transport_action_related_path =~ "selected_id=transport-action-request-1"
    assert transport_action_related_path =~ "nav_from_target=command_release_attempt"
    assert transport_action_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert transport_action_related_path =~ "nav_trail="
    assert transport_action_related_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_copied_path =~ "panel=data_link"
    assert transport_action_copied_path =~ "selected_target=transport_action_request"
    assert transport_action_copied_path =~ "selected_id=transport-action-request-1"
    assert transport_action_copied_path =~ "nav_from_target=command_release_attempt"
    assert transport_action_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert transport_action_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_view, _html} = live(conn, transport_action_copied_path)

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    transport_action_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{action_event_id}"])

    assert has_element?(
             reopened_transport_action_view,
             transport_action_event_related_selector
           )

    reopened_transport_action_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    transport_action_event_path = assert_patch(reopened_transport_action_view)
    assert transport_action_event_path =~ "panel=data_link"
    assert transport_action_event_path =~ "selected_target=operational_event"
    assert transport_action_event_path =~ "selected_id=#{action_event_route_id}"
    assert transport_action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert transport_action_event_path =~ "nav_from_target=transport_action_request"
    assert transport_action_event_path =~ "nav_from_target_id=transport-action-request-1"
    assert transport_action_event_path =~ "nav_trail="
    assert transport_action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_event_copied_path =
      reopened_transport_action_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_event_copied_path =~ "panel=data_link"
    assert transport_action_event_copied_path =~ "selected_target=operational_event"
    assert transport_action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert transport_action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert transport_action_event_copied_path =~ "nav_from_target=transport_action_request"
    assert transport_action_event_copied_path =~ "nav_from_target_id=transport-action-request-1"
    assert transport_action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_event_view, _html} =
      live(conn, transport_action_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    {:ok, reopened_transport_action_event_back_source_view, _html} =
      live(conn, transport_action_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    reopened_transport_action_event_back_source_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
    )
    |> render_click()

    release_attempt_event_back_path =
      assert_patch(reopened_transport_action_event_back_source_view)

    assert release_attempt_event_back_path =~ "panel=data_link"
    assert release_attempt_event_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_event_back_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_event_back_path =~ "selected_time=#{action_event_at_ms}"
    assert release_attempt_event_back_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_event_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_event_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    release_attempt_event_back_copied_path =
      reopened_transport_action_event_back_source_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_event_back_copied_path =~ "panel=data_link"

    assert release_attempt_event_back_copied_path =~
             "selected_target=command_release_attempt"

    assert release_attempt_event_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_event_back_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert release_attempt_event_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_event_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_event_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_release_attempt_event_back_view, _html} =
      live(conn, release_attempt_event_back_copied_path)

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    failed_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{failed_verifier_instance.command_verifier_instance_id}"])

    failed_verifier_id = failed_verifier_instance.command_verifier_instance_id

    failed_verifier_matched_at_ms =
      DateTime.to_unix(failed_verifier_instance.matched_at, :millisecond)

    failed_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(failed_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-target")

    assert [^failed_verifier_id] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-target-id")

    assert [failed_verifier_matched_at_ms_text] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-timestamp-ms")

    assert failed_verifier_matched_at_ms_text == Integer.to_string(failed_verifier_matched_at_ms)

    assert ["evidence-ref:command_verifier_instance:" <> _] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-link-id")

    view
    |> element(failed_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{failed_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => failed_verifier_id,
      "timestamp-ms" => failed_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_path = assert_patch(view)
    assert failed_verifier_path =~ "panel=data_link"
    assert failed_verifier_path =~ "selected_target=command_verifier_instance"
    assert failed_verifier_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_path =~ "selected_time=#{failed_verifier_matched_at_ms}"
    assert failed_verifier_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_copied_path =~ "panel=data_link"
    assert failed_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert failed_verifier_copied_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_copied_path =~ "selected_time=#{failed_verifier_matched_at_ms}"
    assert failed_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_view, _html} = live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="selected_time=#{failed_verifier_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"]),
             "failure_criteria_matched"
           )

    failed_verifier_transport_action_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="transport-action-request-1"])

    assert has_element?(
             reopened_failed_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_failed_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_path = assert_patch(reopened_failed_verifier_view)
    assert failed_verifier_transport_action_path =~ "panel=data_link"
    assert failed_verifier_transport_action_path =~ "selected_target=transport_action_request"
    assert failed_verifier_transport_action_path =~ "selected_id=transport-action-request-1"
    assert failed_verifier_transport_action_path =~ "nav_from_target=command_verifier_instance"
    assert failed_verifier_transport_action_path =~ "nav_from_target_id=#{failed_verifier_id}"
    assert failed_verifier_transport_action_path =~ "nav_trail="
    assert failed_verifier_transport_action_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_copied_path =
      reopened_failed_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_copied_path =~ "panel=data_link"

    assert failed_verifier_transport_action_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_failed_verifier_transport_action_view, _html} =
      live(conn, failed_verifier_transport_action_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_failed_verifier_transport_action_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_failed_verifier_transport_action_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_path =
      assert_patch(reopened_failed_verifier_transport_action_view)

    assert failed_verifier_transport_action_back_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_transport_action_back_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_copied_path =
      reopened_failed_verifier_transport_action_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_copied_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_transport_action_back_view, _html} =
      live(conn, failed_verifier_transport_action_back_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_failed_verifier_transport_action_back_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_path =
      assert_patch(reopened_failed_verifier_transport_action_back_view)

    assert failed_verifier_transport_action_back_matched_record_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_copied_path =
      reopened_failed_verifier_transport_action_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_transport_action_back_matched_record_view, _html} =
      live(conn, failed_verifier_transport_action_back_matched_record_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_failed_verifier_transport_action_back_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             transport_action_event_related_selector
           )

    failed_verifier_transport_action_event_link =
      reopened_failed_verifier_transport_action_back_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [failed_verifier_transport_action_event_at_ms_text] =
             LazyHTML.attribute(
               failed_verifier_transport_action_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_failed_verifier_transport_action_back_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_path =
      assert_patch(reopened_failed_verifier_transport_action_back_matched_record_view)

    assert failed_verifier_transport_action_back_matched_record_event_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_time=#{failed_verifier_transport_action_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{failed_verifier_transport_action_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_copied_path =
      reopened_failed_verifier_transport_action_back_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_time=#{failed_verifier_transport_action_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_event_view, _html} =
      live(conn, failed_verifier_transport_action_back_matched_record_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    reopened_transport_action_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_path =
      assert_patch(reopened_transport_action_event_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =
      reopened_transport_action_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_verifier_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_copied_path
      )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_back_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_back_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =
      assert_patch(reopened_back_verifier_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =
      reopened_back_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_record_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path
      )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_back_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_back_record_view,
             transport_action_event_related_selector
           )

    failed_verifier_transport_action_event_verifier_matched_record_event_link =
      reopened_back_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               failed_verifier_transport_action_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_back_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_back_record_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =
      reopened_back_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_event_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path
      )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_back_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_back_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =
      assert_patch(reopened_back_event_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_verifier_copied_path =
      reopened_back_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_verifier_copied_path =~
             "panel=data_link"

    assert deep_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_verifier_view, _html} =
      live(conn, deep_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_event_verifier_matched_record_path =
      assert_patch(reopened_deep_event_verifier_view)

    assert deep_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_verifier_matched_record_copied_path =
      reopened_deep_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_verifier_matched_record_copied_path =~ "panel=data_link"

    assert deep_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_matched_record_view, _html} =
      live(conn, deep_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_event_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             transport_action_event_related_selector
           )

    deep_event_matched_record_event_link =
      reopened_deep_event_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_event_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_event_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_event_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_event_matched_record_event_path =
      assert_patch(reopened_deep_event_matched_record_view)

    assert deep_event_matched_record_event_path =~ "panel=data_link"

    assert deep_event_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_event_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_event_matched_record_event_path =~
             "selected_time=#{deep_event_matched_record_event_at_ms_text}"

    assert deep_event_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_event_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_event_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_event_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_matched_record_event_copied_path =
      reopened_deep_event_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_matched_record_event_copied_path =~ "panel=data_link"

    assert deep_event_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_event_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_event_matched_record_event_copied_path =~
             "selected_time=#{deep_event_matched_record_event_at_ms_text}"

    assert deep_event_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_event_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_event_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_matched_record_event_view, _html} =
      live(conn, deep_event_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_event_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_event_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_event_matched_record_event_verifier_path =
      assert_patch(reopened_deep_event_matched_record_event_view)

    assert deep_event_matched_record_event_verifier_path =~ "panel=data_link"

    assert deep_event_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_matched_record_event_verifier_copied_path =
      reopened_deep_event_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_matched_record_event_verifier_copied_path =~ "panel=data_link"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_verifier_again_view, _html} =
      live(conn, deep_event_matched_record_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_event_verifier_again_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_verifier_again_matched_record_path =
      assert_patch(reopened_deep_event_verifier_again_view)

    assert deep_verifier_again_matched_record_path =~ "panel=data_link"

    assert deep_verifier_again_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_verifier_again_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_verifier_again_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_verifier_again_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_verifier_again_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_verifier_again_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_verifier_again_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_verifier_again_matched_record_copied_path =
      reopened_deep_event_verifier_again_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_verifier_again_matched_record_copied_path =~
             "panel=data_link"

    assert deep_verifier_again_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_verifier_again_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_verifier_again_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_verifier_again_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_verifier_again_matched_record_view, _html} =
      live(conn, deep_verifier_again_matched_record_copied_path)

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_verifier_again_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_matched_record_event_link =
      reopened_deep_verifier_again_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_verifier_again_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_matched_record_event_path =
      assert_patch(reopened_deep_verifier_again_matched_record_view)

    assert deep_again_matched_record_event_path =~ "panel=data_link"

    assert deep_again_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_matched_record_event_path =~
             "selected_time=#{deep_again_matched_record_event_at_ms_text}"

    assert deep_again_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_matched_record_event_copied_path =
      reopened_deep_verifier_again_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_matched_record_event_copied_path =~ "panel=data_link"

    assert deep_again_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_matched_record_event_copied_path =~
             "selected_time=#{deep_again_matched_record_event_at_ms_text}"

    assert deep_again_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_matched_record_event_view, _html} =
      live(conn, deep_again_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_event_verifier_path =
      assert_patch(reopened_deep_again_matched_record_event_view)

    assert deep_again_event_verifier_path =~ "panel=data_link"

    assert deep_again_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_copied_path =
      reopened_deep_again_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_copied_path =~ "panel=data_link"

    assert deep_again_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_view, _html} =
      live(conn, deep_again_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_again_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_event_verifier_matched_record_path =
      assert_patch(reopened_deep_again_event_verifier_view)

    assert deep_again_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_again_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_matched_record_copied_path =
      reopened_deep_again_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_matched_record_view, _html} =
      live(conn, deep_again_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_event_verifier_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_event_verifier_matched_record_event_link =
      reopened_deep_again_event_verifier_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_again_event_verifier_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_event_verifier_matched_record_event_path =
      assert_patch(reopened_deep_again_event_verifier_matched_record_view)

    assert deep_again_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_matched_record_event_copied_path =
      reopened_deep_again_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_matched_record_event_view, _html} =
      live(conn, deep_again_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_event_verifier_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_event_verifier_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_record_event_verifier_path =
      assert_patch(reopened_deep_again_event_verifier_matched_record_event_view)

    assert deep_again_record_event_verifier_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_copied_path =
      reopened_deep_again_event_verifier_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_copied_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_view, _html} =
      live(conn, deep_again_record_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_again_record_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_path =
      assert_patch(reopened_deep_again_record_event_verifier_view)

    assert deep_again_record_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_copied_path =
      reopened_deep_again_record_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_matched_record_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_record_event_verifier_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_record_event_verifier_matched_record_event_link =
      reopened_deep_again_record_event_verifier_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_record_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_record_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_again_record_event_verifier_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_deep_again_record_event_verifier_matched_record_view)

    assert deep_again_record_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_copied_path =
      reopened_deep_again_record_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_matched_record_event_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_record_event_verifier_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_record_event_verifier_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_path =
      assert_patch(reopened_deep_again_record_event_verifier_matched_record_event_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_copied_path =
      reopened_deep_again_record_event_verifier_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_record_verifier_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_event_verifier_copied_path)

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_record_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_record_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =
      assert_patch(reopened_record_verifier_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =
      reopened_record_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_record_view, _html} =
      live(
        conn,
        deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path
      )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_verifier_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_verifier_record_view,
             transport_action_event_related_selector
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_link =
      reopened_verifier_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [
             deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text
           ] =
             LazyHTML.attribute(
               deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_verifier_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_verifier_record_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =
      reopened_verifier_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_event_view, _html} =
      live(
        conn,
        deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path
      )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_verifier_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_verifier_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    verifier_path =
      assert_patch(reopened_verifier_event_view)

    assert verifier_path =~
             "panel=data_link"

    assert verifier_path =~
             "selected_target=command_verifier_instance"

    assert verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    verifier_reopen_path =
      reopened_verifier_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_reopen_path =~
             "panel=data_link"

    assert verifier_reopen_path =~
             "selected_target=command_verifier_instance"

    assert verifier_reopen_path =~
             "selected_id=#{failed_verifier_id}"

    assert verifier_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert verifier_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_view, _html} =
      live(
        conn,
        verifier_reopen_path
      )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    action_request_path =
      assert_patch(reopened_verifier_view)

    assert action_request_path =~
             "panel=data_link"

    assert action_request_path =~
             "selected_target=transport_action_request"

    assert action_request_path =~
             "selected_id=transport-action-request-1"

    assert action_request_path =~
             "nav_from_target=command_verifier_instance"

    assert action_request_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert action_request_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_request_reopen_path =
      reopened_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_request_reopen_path =~
             "panel=data_link"

    assert action_request_reopen_path =~
             "selected_target=transport_action_request"

    assert action_request_reopen_path =~
             "selected_id=transport-action-request-1"

    assert action_request_reopen_path =~
             "nav_from_target=command_verifier_instance"

    assert action_request_reopen_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert action_request_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_request_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_request_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_request_view, _html} =
      live(
        conn,
        action_request_reopen_path
      )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_action_request_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_action_request_view,
             transport_action_event_related_selector
           )

    action_event_link =
      reopened_action_request_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [
             action_event_at_ms_text
           ] =
             LazyHTML.attribute(
               action_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_action_request_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    action_event_path =
      assert_patch(reopened_action_request_view)

    assert action_event_path =~
             "panel=data_link"

    assert action_event_path =~
             "selected_target=operational_event"

    assert action_event_path =~
             "selected_id=#{action_event_route_id}"

    assert action_event_path =~
             "selected_time=#{action_event_at_ms_text}"

    assert action_event_path =~
             "nav_from_target=transport_action_request"

    assert action_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert action_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_reopen_path =
      reopened_action_request_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_reopen_path =~
             "panel=data_link"

    assert action_event_reopen_path =~
             "selected_target=operational_event"

    assert action_event_reopen_path =~
             "selected_id=#{action_event_route_id}"

    assert action_event_reopen_path =~
             "selected_time=#{action_event_at_ms_text}"

    assert action_event_reopen_path =~
             "nav_from_target=transport_action_request"

    assert action_event_reopen_path =~
             "nav_from_target_id=transport-action-request-1"

    assert action_event_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_event_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_event_view, _html} =
      live(
        conn,
        action_event_reopen_path
      )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    stop_dashboard_view(reopened_action_event_view)

    stop_dashboard_view(reopened_action_request_view)

    stop_dashboard_view(reopened_verifier_view)

    stop_dashboard_view(reopened_verifier_event_view)

    stop_dashboard_view(reopened_verifier_record_view)

    stop_dashboard_view(reopened_record_verifier_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_view)

    stop_dashboard_view(reopened_deep_again_matched_record_event_view)

    stop_dashboard_view(reopened_deep_verifier_again_matched_record_view)

    stop_dashboard_view(reopened_deep_event_verifier_again_view)

    stop_dashboard_view(reopened_deep_event_matched_record_event_view)

    stop_dashboard_view(reopened_deep_event_matched_record_view)

    stop_dashboard_view(reopened_deep_event_verifier_view)

    stop_dashboard_view(reopened_back_event_view)

    stop_dashboard_view(reopened_back_record_view)

    stop_dashboard_view(reopened_back_verifier_view)

    stop_dashboard_view(reopened_transport_action_event_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_back_matched_record_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_back_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    capability_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{capability_verifier_instance.command_verifier_instance_id}"])

    capability_verifier_id = capability_verifier_instance.command_verifier_instance_id
    capability_related_id = "transport-runtime-record-1"

    capability_verifier_matched_at_ms =
      DateTime.to_unix(capability_verifier_instance.matched_at, :millisecond)

    capability_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(capability_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-target")

    assert [^capability_verifier_id] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-target-id")

    assert [capability_verifier_matched_at_ms_text] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-timestamp-ms")

    assert capability_verifier_matched_at_ms_text ==
             Integer.to_string(capability_verifier_matched_at_ms)

    view
    |> element(capability_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{capability_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => capability_verifier_id,
      "timestamp-ms" => capability_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    capability_verifier_path = assert_patch(view)
    assert capability_verifier_path =~ "panel=data_link"
    assert capability_verifier_path =~ "selected_target=command_verifier_instance"
    assert capability_verifier_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_verifier_path =~ "selected_time=#{capability_verifier_matched_at_ms}"
    assert capability_verifier_path =~ "replay_run_id=#{replay_run_id}"

    capability_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_verifier_copied_path =~ "panel=data_link"
    assert capability_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert capability_verifier_copied_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_verifier_copied_path =~ "selected_time=#{capability_verifier_matched_at_ms}"
    assert capability_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_verifier_view, _html} = live(conn, capability_verifier_copied_path)

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    capability_verifier_transport_capability_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport capability record"][data-data-link-related-id="#{capability_related_id}"])

    assert has_element?(
             reopened_capability_verifier_view,
             capability_verifier_transport_capability_related_selector
           )

    reopened_capability_verifier_view
    |> element(capability_verifier_transport_capability_related_selector)
    |> render_click()

    capability_verifier_transport_capability_path =
      assert_patch(reopened_capability_verifier_view)

    assert capability_verifier_transport_capability_path =~ "panel=data_link"

    assert capability_verifier_transport_capability_path =~
             "selected_target=transport_capability_record"

    assert capability_verifier_transport_capability_path =~
             "selected_id=#{capability_related_id}"

    assert capability_verifier_transport_capability_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_verifier_transport_capability_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_verifier_transport_capability_path =~ "nav_trail="
    assert capability_verifier_transport_capability_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_verifier_transport_capability_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_verifier_transport_capability_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_verifier_transport_capability_copied_path =
      reopened_capability_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_verifier_transport_capability_copied_path =~ "panel=data_link"

    assert capability_verifier_transport_capability_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_verifier_transport_capability_copied_path =~
             "selected_id=#{capability_related_id}"

    assert capability_verifier_transport_capability_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_verifier_transport_capability_copied_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_verifier_transport_capability_copied_path =~
             "replay_run_id=#{replay_run_id}"

    {:ok, reopened_capability_related_view, _html} =
      live(conn, capability_verifier_transport_capability_copied_path)

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    capability_event_id = record_event.event_id
    capability_event_route_id = URI.encode_www_form(capability_event_id)

    capability_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{capability_event_id}"])

    assert has_element?(
             reopened_capability_related_view,
             capability_event_related_selector
           )

    reopened_capability_related_view
    |> element(capability_event_related_selector)
    |> render_click()

    capability_event_path = assert_patch(reopened_capability_related_view)
    assert capability_event_path =~ "panel=data_link"
    assert capability_event_path =~ "selected_target=operational_event"
    assert capability_event_path =~ "selected_id=#{capability_event_route_id}"
    assert capability_event_path =~ "nav_from_target=transport_capability_record"
    assert capability_event_path =~ "nav_from_target_id=#{capability_related_id}"
    assert capability_event_path =~ "nav_trail="
    assert capability_event_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{capability_event_route_id}"][data-clipboard-text*="nav_from_target=transport_capability_record"][data-clipboard-text*="nav_from_target_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_copied_path =
      reopened_capability_related_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_copied_path =~ "panel=data_link"
    assert capability_event_copied_path =~ "selected_target=operational_event"
    assert capability_event_copied_path =~ "selected_id=#{capability_event_route_id}"
    assert capability_event_copied_path =~ "nav_from_target=transport_capability_record"
    assert capability_event_copied_path =~ "nav_from_target_id=#{capability_related_id}"
    assert capability_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_capability_event_view, _html} =
      live(conn, capability_event_copied_path)

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    {:ok, reopened_capability_event_verifier_view, _html} =
      live(conn, capability_event_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    reopened_capability_event_verifier_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    capability_event_verifier_back_path =
      assert_patch(reopened_capability_event_verifier_view)

    assert capability_event_verifier_back_path =~ "panel=data_link"

    assert capability_event_verifier_back_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_verifier_back_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_event_verifier_back_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_back_copied_path =
      reopened_capability_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_back_copied_path =~ "panel=data_link"

    assert capability_event_verifier_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_verifier_back_copied_path =~
             "selected_id=#{capability_verifier_id}"

    assert capability_event_verifier_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_back_view, _html} =
      live(conn, capability_event_verifier_back_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             capability_verifier_transport_capability_related_selector
           )

    reopened_capability_event_verifier_back_view
    |> element(capability_verifier_transport_capability_related_selector)
    |> render_click()

    capability_event_verifier_matched_record_path =
      assert_patch(reopened_capability_event_verifier_back_view)

    assert capability_event_verifier_matched_record_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_path =~
             "selected_target=transport_capability_record"

    assert capability_event_verifier_matched_record_path =~
             "selected_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_event_verifier_matched_record_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_event_verifier_matched_record_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_matched_record_copied_path =
      reopened_capability_event_verifier_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_matched_record_copied_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_event_verifier_matched_record_copied_path =~
             "selected_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_matched_record_view, _html} =
      live(conn, capability_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             capability_event_related_selector
           )

    reopened_capability_event_verifier_matched_record_view
    |> element(capability_event_related_selector)
    |> render_click()

    capability_event_verifier_matched_record_event_path =
      assert_patch(reopened_capability_event_verifier_matched_record_view)

    assert capability_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert capability_event_verifier_matched_record_event_path =~
             "selected_id=#{capability_event_route_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_capability_record"

    assert capability_event_verifier_matched_record_event_path =~
             "nav_from_target_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{capability_event_route_id}"][data-clipboard-text*="nav_from_target=transport_capability_record"][data-clipboard-text*="nav_from_target_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_matched_record_event_copied_path =
      reopened_capability_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_matched_record_event_copied_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{capability_event_route_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_capability_record"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_matched_record_event_view, _html} =
      live(conn, capability_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_capability_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_capability_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_capability_event_verifier_back_view)
    stop_dashboard_view(reopened_capability_event_verifier_view)

    reopened_capability_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
    )
    |> render_click()

    capability_event_back_path = assert_patch(reopened_capability_event_view)
    assert capability_event_back_path =~ "panel=data_link"

    assert capability_event_back_path =~
             "selected_target=transport_capability_record"

    assert capability_event_back_path =~ "selected_id=#{capability_related_id}"
    assert capability_event_back_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_back_copied_path =
      reopened_capability_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_back_copied_path =~ "panel=data_link"

    assert capability_event_back_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_event_back_copied_path =~ "selected_id=#{capability_related_id}"
    assert capability_event_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_back_view, _html} =
      live(conn, capability_event_back_copied_path)

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    reopened_capability_event_back_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    capability_event_back_verifier_path =
      assert_patch(reopened_capability_event_back_view)

    assert capability_event_back_verifier_path =~ "panel=data_link"

    assert capability_event_back_verifier_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_back_verifier_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_event_back_verifier_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_back_verifier_copied_path =
      reopened_capability_event_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_back_verifier_copied_path =~ "panel=data_link"

    assert capability_event_back_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_back_verifier_copied_path =~
             "selected_id=#{capability_verifier_id}"

    assert capability_event_back_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_back_verifier_view, _html} =
      live(conn, capability_event_back_verifier_copied_path)

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             capability_verifier_transport_capability_related_selector
           )

    stop_dashboard_view(reopened_capability_event_back_verifier_view)

    stop_dashboard_view(reopened_capability_event_back_view)

    stop_dashboard_view(reopened_capability_event_view)

    stop_dashboard_view(reopened_capability_related_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    telemetry_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{telemetry_verifier_instance.command_verifier_instance_id}"])

    telemetry_verifier_id = telemetry_verifier_instance.command_verifier_instance_id
    telemetry_related_id = telemetry_sample.sample_id

    telemetry_verifier_matched_at_ms =
      DateTime.to_unix(telemetry_verifier_instance.matched_at, :millisecond)

    telemetry_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(telemetry_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-target")

    assert [^telemetry_verifier_id] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-target-id")

    assert [telemetry_verifier_matched_at_ms_text] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-timestamp-ms")

    assert telemetry_verifier_matched_at_ms_text ==
             Integer.to_string(telemetry_verifier_matched_at_ms)

    view
    |> element(telemetry_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{telemetry_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => telemetry_verifier_id,
      "timestamp-ms" => telemetry_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_path = assert_patch(view)
    assert telemetry_verifier_path =~ "panel=data_link"
    assert telemetry_verifier_path =~ "selected_target=command_verifier_instance"
    assert telemetry_verifier_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_path =~ "selected_time=#{telemetry_verifier_matched_at_ms}"
    assert telemetry_verifier_path =~ "replay_run_id=#{replay_run_id}"

    telemetry_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_copied_path =~ "panel=data_link"
    assert telemetry_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert telemetry_verifier_copied_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_copied_path =~ "selected_time=#{telemetry_verifier_matched_at_ms}"
    assert telemetry_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_verifier_view, _html} = live(conn, telemetry_verifier_copied_path)

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             telemetry_verifier_id
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             telemetry_related_id
           )

    telemetry_verifier_sample_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="telemetry sample"][data-data-link-related-id="#{telemetry_related_id}"])

    assert has_element?(
             reopened_telemetry_verifier_view,
             telemetry_verifier_sample_related_selector
           )

    reopened_telemetry_verifier_view
    |> element(telemetry_verifier_sample_related_selector)
    |> render_click()

    telemetry_verifier_sample_path = assert_patch(reopened_telemetry_verifier_view)
    assert telemetry_verifier_sample_path =~ "panel=data_link"
    assert telemetry_verifier_sample_path =~ "selected_target=telemetry_sample"
    assert telemetry_verifier_sample_path =~ "selected_id=#{telemetry_related_id}"
    assert telemetry_verifier_sample_path =~ "nav_from_target=command_verifier_instance"
    assert telemetry_verifier_sample_path =~ "nav_from_target_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_path =~ "nav_trail="
    assert telemetry_verifier_sample_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{telemetry_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_sample_copied_path =
      reopened_telemetry_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_sample_copied_path =~ "panel=data_link"
    assert telemetry_verifier_sample_copied_path =~ "selected_target=telemetry_sample"
    assert telemetry_verifier_sample_copied_path =~ "selected_id=#{telemetry_related_id}"
    assert telemetry_verifier_sample_copied_path =~ "nav_from_target=command_verifier_instance"
    assert telemetry_verifier_sample_copied_path =~ "nav_from_target_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_telemetry_related_view, _html} =
      live(conn, telemetry_verifier_sample_copied_path)

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{telemetry_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
             telemetry_related_id
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
             telemetry_sample.point_id
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    reopened_telemetry_related_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{telemetry_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    telemetry_verifier_sample_back_path =
      assert_patch(reopened_telemetry_related_view)

    assert telemetry_verifier_sample_back_path =~ "panel=data_link"

    assert telemetry_verifier_sample_back_path =~
             "selected_target=command_verifier_instance"

    assert telemetry_verifier_sample_back_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_back_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{telemetry_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_sample_back_copied_path =
      reopened_telemetry_related_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_sample_back_copied_path =~ "panel=data_link"

    assert telemetry_verifier_sample_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert telemetry_verifier_sample_back_copied_path =~
             "selected_id=#{telemetry_verifier_id}"

    assert telemetry_verifier_sample_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_verifier_back_view, _html} =
      live(conn, telemetry_verifier_sample_back_copied_path)

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             telemetry_verifier_id
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             telemetry_related_id
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             telemetry_verifier_sample_related_selector
           )

    stop_dashboard_view(reopened_telemetry_verifier_back_view)

    stop_dashboard_view(reopened_telemetry_related_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    view
    |> element(failed_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{failed_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => failed_verifier_id,
      "timestamp-ms" => failed_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert_patch(view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_capability_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport capability record"][data-evidence-ref-id="transport-runtime-record-1"])

    transport_capability_id = "transport-runtime-record-1"

    transport_capability_matched_at_ms =
      DateTime.to_unix(capability_verifier_instance.matched_at, :millisecond)

    transport_capability_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_capability_evidence_selector)

    assert ["transport_capability_record"] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-target")

    assert [^transport_capability_id] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-target-id")

    assert [transport_capability_matched_at_ms_text] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-timestamp-ms")

    assert transport_capability_matched_at_ms_text ==
             Integer.to_string(transport_capability_matched_at_ms)

    assert ["evidence-ref:transport_capability_record:" <> _] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-link-id")

    view
    |> element(transport_capability_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:transport_capability_record:#{transport_capability_id}",
      "target" => "transport_capability_record",
      "target-id" => transport_capability_id,
      "timestamp-ms" => transport_capability_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="transport-runtime-record-1"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="transport-runtime-record-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_capability_path = assert_patch(view)
    assert transport_capability_path =~ "panel=data_link"
    assert transport_capability_path =~ "selected_target=transport_capability_record"
    assert transport_capability_path =~ "selected_id=transport-runtime-record-1"
    assert transport_capability_path =~ "selected_time=#{transport_capability_matched_at_ms}"
    assert transport_capability_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=transport-runtime-record-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_capability_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_capability_copied_path =~ "panel=data_link"
    assert transport_capability_copied_path =~ "selected_target=transport_capability_record"
    assert transport_capability_copied_path =~ "selected_id=#{transport_capability_id}"

    assert transport_capability_copied_path =~
             "selected_time=#{transport_capability_matched_at_ms}"

    assert transport_capability_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_capability_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_capability_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_capability_view, _html} =
      live(conn, transport_capability_copied_path)

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{transport_capability_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{transport_capability_id}"][data-clipboard-text*="selected_time=#{transport_capability_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             transport_capability_id
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-runtime-record-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "cop1_state"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-1"
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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_action_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport action request"][data-evidence-ref-id="transport-action-request-1"])

    transport_action_id = "transport-action-request-1"
    transport_action_matched_at_ms = DateTime.to_unix(verifier_instance.matched_at, :millisecond)

    transport_action_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_evidence_selector)

    assert ["transport_action_request"] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-target")

    assert [^transport_action_id] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-target-id")

    assert [transport_action_matched_at_ms_text] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-timestamp-ms")

    assert transport_action_matched_at_ms_text ==
             Integer.to_string(transport_action_matched_at_ms)

    assert ["evidence-ref:transport_action_request:" <> _] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-link-id")

    view
    |> element(transport_action_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:transport_action_request:#{transport_action_id}",
      "target" => "transport_action_request",
      "target-id" => transport_action_id,
      "timestamp-ms" => transport_action_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_action_path = assert_patch(view)
    assert transport_action_path =~ "panel=data_link"
    assert transport_action_path =~ "selected_target=transport_action_request"
    assert transport_action_path =~ "selected_id=transport-action-request-1"
    assert transport_action_path =~ "selected_time=#{transport_action_matched_at_ms}"
    assert transport_action_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_matched_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_matched_copied_path =~ "panel=data_link"
    assert transport_action_matched_copied_path =~ "selected_target=transport_action_request"
    assert transport_action_matched_copied_path =~ "selected_id=#{transport_action_id}"

    assert transport_action_matched_copied_path =~
             "selected_time=#{transport_action_matched_at_ms}"

    assert transport_action_matched_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_matched_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_matched_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_matched_view, _html} =
      live(conn, transport_action_matched_copied_path)

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_id}"][data-clipboard-text*="selected_time=#{transport_action_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_matched_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-1"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-1"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    matched_transport_action_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{action_event_id}"])

    assert has_element?(
             reopened_transport_action_matched_view,
             matched_transport_action_event_related_selector
           )

    reopened_transport_action_matched_view
    |> element(matched_transport_action_event_related_selector)
    |> render_click()

    matched_transport_action_event_path =
      assert_patch(reopened_transport_action_matched_view)

    assert matched_transport_action_event_path =~ "panel=data_link"
    assert matched_transport_action_event_path =~ "selected_target=operational_event"
    assert matched_transport_action_event_path =~ "selected_id=#{action_event_route_id}"
    assert matched_transport_action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert matched_transport_action_event_path =~ "nav_from_target=transport_action_request"
    assert matched_transport_action_event_path =~ "nav_from_target_id=#{transport_action_id}"
    assert matched_transport_action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=#{transport_action_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    matched_transport_action_event_copied_path =
      reopened_transport_action_matched_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert matched_transport_action_event_copied_path =~ "panel=data_link"
    assert matched_transport_action_event_copied_path =~ "selected_target=operational_event"
    assert matched_transport_action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert matched_transport_action_event_copied_path =~ "selected_time=#{action_event_at_ms}"

    assert matched_transport_action_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert matched_transport_action_event_copied_path =~
             "nav_from_target_id=#{transport_action_id}"

    assert matched_transport_action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_matched_transport_action_event_view, _html} =
      live(conn, matched_transport_action_event_copied_path)

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_id}"][phx-value-target="transport_action_request"])
           )

    reopened_matched_transport_action_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_id}"][phx-value-target="transport_action_request"])
    )
    |> render_click()

    matched_transport_action_back_path =
      assert_patch(reopened_matched_transport_action_event_view)

    assert matched_transport_action_back_path =~ "panel=data_link"
    assert matched_transport_action_back_path =~ "selected_target=transport_action_request"
    assert matched_transport_action_back_path =~ "selected_id=#{transport_action_id}"
    assert matched_transport_action_back_path =~ "selected_time=#{action_event_at_ms}"
    assert matched_transport_action_back_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    matched_transport_action_back_copied_path =
      reopened_matched_transport_action_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert matched_transport_action_back_copied_path =~ "panel=data_link"

    assert matched_transport_action_back_copied_path =~
             "selected_target=transport_action_request"

    assert matched_transport_action_back_copied_path =~
             "selected_id=#{transport_action_id}"

    assert matched_transport_action_back_copied_path =~
             "selected_time=#{action_event_at_ms}"

    assert matched_transport_action_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_matched_transport_action_back_view, _html} =
      live(conn, matched_transport_action_back_copied_path)

    assert has_element?(
             reopened_matched_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_matched_transport_action_back_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_matched_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

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
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    action_event_path = assert_patch(view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_copied_path =
      view
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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_timer_event = Enum.find(transport_events, &(&1.kind == :transport_timer_fired))
    assert transport_timer_event

    transport_timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_timer_event.event_id}"])

    transport_timer_event_id = transport_timer_event.event_id
    transport_timer_event_route_id = URI.encode_www_form(transport_timer_event_id)
    transport_timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    transport_timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-target")

    assert [^transport_timer_event_id] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-link-id")

    view
    |> element(transport_timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{transport_timer_event_id}",
      "target" => "operational_event",
      "target-id" => transport_timer_event_id,
      "timestamp-ms" => transport_timer_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_timer_event_path = assert_patch(view)
    assert transport_timer_event_path =~ "panel=data_link"
    assert transport_timer_event_path =~ "selected_target=operational_event"
    assert transport_timer_event_path =~ "selected_id=#{transport_timer_event_route_id}"
    assert transport_timer_event_path =~ "selected_time=#{transport_timer_event_at_ms}"
    assert transport_timer_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_timer_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_timer_event_copied_path =~ "panel=data_link"
    assert transport_timer_event_copied_path =~ "selected_target=operational_event"
    assert transport_timer_event_copied_path =~ "selected_id=#{transport_timer_event_route_id}"
    assert transport_timer_event_copied_path =~ "selected_time=#{transport_timer_event_at_ms}"
    assert transport_timer_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_timer_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_timer_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_timer_event_view, _html} =
      live(conn, transport_timer_event_copied_path)

    assert has_element?(
             reopened_transport_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_timer_event_route_id}"][data-clipboard-text*="selected_time=#{transport_timer_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_transport_timer_runtime_context!(reopened_transport_timer_event_view, replay_run_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    telemetry_sample_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="telemetry sample"][data-evidence-ref-id="#{telemetry_sample.sample_id}"])

    telemetry_sample_id = telemetry_sample.sample_id

    telemetry_sample_matched_at_ms =
      DateTime.to_unix(telemetry_verifier_instance.matched_at, :millisecond)

    telemetry_sample_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(telemetry_sample_evidence_selector)

    assert ["telemetry_sample"] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-target")

    assert [^telemetry_sample_id] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-target-id")

    assert [telemetry_sample_matched_at_ms_text] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-timestamp-ms")

    assert telemetry_sample_matched_at_ms_text ==
             Integer.to_string(telemetry_sample_matched_at_ms)

    assert ["evidence-ref:telemetry_sample:" <> _] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-link-id")

    view
    |> element(telemetry_sample_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:telemetry_sample:#{telemetry_sample_id}",
      "target" => "telemetry_sample",
      "target-id" => telemetry_sample_id,
      "timestamp-ms" => telemetry_sample_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert_push_event(
      view,
      "tlm:select",
      %{
        "selection" => %{
          "target" => "telemetry_sample",
          "target_id" => ^telemetry_sample_id
        }
      },
      1_000
    )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample.sample_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample.sample_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    telemetry_sample_path = assert_patch(view)
    assert telemetry_sample_path =~ "panel=data_link"
    assert telemetry_sample_path =~ "selected_target=telemetry_sample"
    assert telemetry_sample_path =~ "selected_id=#{telemetry_sample.sample_id}"
    assert telemetry_sample_path =~ "selected_time=#{telemetry_sample_matched_at_ms}"
    assert telemetry_sample_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_sample.sample_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_sample_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_sample_copied_path =~ "panel=data_link"
    assert telemetry_sample_copied_path =~ "selected_target=telemetry_sample"
    assert telemetry_sample_copied_path =~ "selected_id=#{telemetry_sample_id}"
    assert telemetry_sample_copied_path =~ "selected_time=#{telemetry_sample_matched_at_ms}"
    assert telemetry_sample_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_sample_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_sample_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_sample_view, _html} = live(conn, telemetry_sample_copied_path)

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_sample_id}"][data-clipboard-text*="selected_time=#{telemetry_sample_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
             telemetry_sample_id
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
             telemetry_sample.point_id
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"])
           )

    stop_dashboard_view(view)
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

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp persist_replay_run!(mission, replay_run_id) do
    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: "#{replay_run_id}-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 0,
        replayed_sample_count: 0,
        started_at: ~U[2026-06-17 11:59:00Z],
        completed_at: ~U[2026-06-17 12:06:00Z]
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
  end

  defp persist_command_queue_entry!(
         org,
         mission,
         command_queue_entry_id,
         source_endpoint_ref,
         lifecycle_state \\ :pending
       ) do
    requested_at = ~U[2026-06-17 12:00:00Z]
    command_request_id = "#{command_queue_entry_id}-request"

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: "#{command_queue_entry_id}-snapshot",
        command_id: "#{command_queue_entry_id}-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-test"},
        requested_at: requested_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-test"},
        enqueued_at: requested_at,
        metadata: %{}
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
  end

  defp persist_replay_command_verifier_telemetry_sample!(
         org,
         mission,
         replay_run_id,
         telemetry_replay_source,
         receipt_time
       ) do
    sample = %Sample{
      sample_id: "verifier-telemetry-sample-1",
      mission_id: mission.mission_id,
      spacecraft_id: "spacecraft-alpha",
      point_id: "CMD.release_confirmed",
      point_name: "CMD.release_confirmed",
      packet_definition_id: "packet-def-command-verifier",
      packet_definition_version: 1,
      packet_id: "packet-command-verifier",
      evidence_id: "evidence-command-verifier",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      generation_time: DateTime.add(receipt_time, -2, :second),
      receipt_time: receipt_time,
      provenance: %{"command_release_attempt_id" => "release-attempt-1"}
    }

    raw_evidence =
      RawEvidence.new(%{
        evidence_id: sample.evidence_id,
        mission_id: mission.mission_id,
        spacecraft_id: sample.spacecraft_id,
        protocol_family: :space_packet,
        direction: :downlink,
        raw: <<0, 1, 2, 3>>,
        source_time: sample.generation_time,
        receipt_time: sample.receipt_time,
        source_ref: "command-verifier-telemetry-test",
        metadata: %{}
      })

    packet_record = %PacketRecord{
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: mission.mission_id,
      spacecraft_id: sample.spacecraft_id,
      protocol_family: :space_packet,
      packet_kind: :space_packet,
      apid: 1,
      sequence_flags: 3,
      sequence_count: 1,
      secondary_header?: false,
      packet_data: <<0, 1, 2, 3>>,
      source_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: %{}
    }

    assert %RawEvidenceRow{} = Repo.insert!(RawEvidenceRow.changeset(raw_evidence))
    assert %PacketRecordRow{} = Repo.insert!(PacketRecordRow.changeset(packet_record))

    assert :ok =
             Storage.persist_samples([sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: telemetry_replay_source.data_source_id,
               binding_id: telemetry_replay_source.binding_id,
               recorded_at: receipt_time,
               source_watermark_events?: false,
               dashboard_runtime_invalidation?: false
             )

    sample
  end

  defp persist_transport_command_release_attempt!(org, mission, attempted_at) do
    command_request =
      CommandRequest.new(%{
        command_request_id: "command-request-1",
        mission_id: mission.mission_id,
        source_endpoint_ref: "endpoint-alpha",
        command_snapshot_id: "transport-command-snapshot-1",
        command_id: "transport-command-1",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        verification_state: :failed,
        priority: 2,
        requested_by: %{"user_id" => "transport-runtime-test"},
        requested_at: attempted_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: "command-queue-entry-1",
        mission_id: mission.mission_id,
        command_request_id: command_request.command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        queue_lane_key: command_request.source_endpoint_ref,
        priority: 2,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: :released,
        enqueued_by: %{"user_id" => "transport-runtime-test"},
        enqueued_at: attempted_at,
        metadata: %{}
      })

    release_attempt =
      CommandReleaseAttempt.new(%{
        command_release_attempt_id: "release-attempt-1",
        mission_id: mission.mission_id,
        command_queue_entry_id: command_queue_entry.command_queue_entry_id,
        command_request_id: command_request.command_request_id,
        source_endpoint_ref: command_request.source_endpoint_ref,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        transport_binding_id: "transport-binding-alpha",
        command_snapshot_id: command_request.command_snapshot_id,
        command_id: command_request.command_id,
        command_name: command_request.command_name,
        layout_kind: :ccsds_space_packet,
        encoded_binary_base64: Base.encode64("NOOP"),
        encoded_size_bytes: 4,
        lifecycle_state: :released,
        verification_state: :failed,
        released_by: %{"user_id" => "transport-runtime-test"},
        attempted_at: attempted_at,
        released_at: attempted_at,
        metadata: %{"transport_action_request_id" => "transport-action-request-1"}
      })

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: command_request.source_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Transport Runtime Endpoint",
        source_ref: "provider/#{command_request.source_endpoint_ref}",
        metadata: %{"contact_id" => release_attempt.realized_contact_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: release_attempt.realized_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [command_request.source_endpoint_ref],
        contact_intents: [:command_window],
        paths: [
          Path.new(%{
            path_id: release_attempt.path_id,
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: command_request.source_endpoint_ref
          })
        ],
        clock_mode: :replay,
        lifecycle_state: :active,
        initial_time: DateTime.add(attempted_at, -60, :second),
        realized_at: DateTime.add(attempted_at, -60, :second),
        metadata: %{"command_release_attempt_id" => release_attempt.command_release_attempt_id}
      })

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    assert %CommandReleaseAttemptRow{} =
             Repo.insert!(
               CommandReleaseAttemptRow.changeset(%CommandReleaseAttempt{
                 release_attempt
                 | organization_id: org.organization_id
               })
             )

    %CommandReleaseAttempt{release_attempt | organization_id: org.organization_id}
  end

  defp persist_transport_command_verifier_instance!(
         org,
         mission,
         release_attempt,
         matched_at,
         opts \\ []
       ) do
    verifier_instance =
      CommandVerifierInstance.new(%{
        command_verifier_instance_id:
          Keyword.get(opts, :command_verifier_instance_id, "verifier-instance-satisfied"),
        mission_id: mission.mission_id,
        command_request_id: release_attempt.command_request_id,
        command_release_attempt_id: release_attempt.command_release_attempt_id,
        source_endpoint_ref: release_attempt.source_endpoint_ref,
        command_snapshot_id: release_attempt.command_snapshot_id,
        command_id: release_attempt.command_id,
        command_name: release_attempt.command_name,
        verifier_id: Keyword.get(opts, :verifier_id, "transport-verifier-1"),
        verifier_name: Keyword.get(opts, :verifier_name, "Transport action accepted"),
        phase: Keyword.get(opts, :phase, :start),
        severity: Keyword.get(opts, :severity, :info),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :satisfied),
        matched_record_kind: Keyword.get(opts, :matched_record_kind, :transport_action_request),
        matched_record_id: Keyword.get(opts, :matched_record_id, "transport-action-request-1"),
        matched_at: matched_at,
        failure_reason: Keyword.get(opts, :failure_reason),
        metadata: %{"transport_action_request_id" => "transport-action-request-1"}
      })

    assert %CommandVerifierInstanceRow{} =
             Repo.insert!(
               CommandVerifierInstanceRow.changeset(%CommandVerifierInstance{
                 verifier_instance
                 | organization_id: org.organization_id
               })
             )

    %CommandVerifierInstance{verifier_instance | organization_id: org.organization_id}
  end

  defp persist_replay_managed_runtime_events!(org, mission, replay_run_id, action_at, timer_at) do
    action_request =
      %ManagedActionRequest{
        action_request_id: "managed-action-request-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        action_kind: :schedule_timer,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        request_document: %{"timer_key" => "flush", "delay_ms" => 1_000},
        requested_at: action_at
      }

    timer_event =
      %ManagedTimerEvent{
        timer_event_id: "managed-timer-event-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        timer_key: "flush",
        event_kind: :fired,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"scheduled_by" => action_request.action_request_id}
      }

    action_event =
      action_request
      |> Event.from_managed_action_request(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    timer_event =
      timer_event
      |> Event.from_managed_timer_event(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    {action_event, timer_event}
  end

  defp persist_live_managed_runtime_events!(org, mission, action_at, timer_at) do
    action_request =
      %ManagedActionRequest{
        action_request_id: "managed-action-request-live-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        action_kind: :schedule_timer,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        request_document: %{"timer_key" => "flush", "delay_ms" => 1_000},
        requested_at: action_at
      }

    timer_event =
      %ManagedTimerEvent{
        timer_event_id: "managed-timer-event-live-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        timer_key: "flush",
        event_kind: :fired,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"scheduled_by" => action_request.action_request_id}
      }

    action_event =
      action_request
      |> Event.from_managed_action_request()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    timer_event =
      timer_event
      |> Event.from_managed_timer_event()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()

    {action_event, timer_event}
  end

  defp persist_replay_managed_capability_record_events!(
         org,
         mission,
         replay_run_id,
         initialized_at,
         record_at,
         timer_at
       ) do
    [
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-initialized-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :initialized,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: nil,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0},
        recorded_at: initialized_at,
        metadata: %{}
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :record_handled,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: nil,
        emitted_record_kinds: [:derived_metric, :limit_state],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["managed-action-request-2"],
          "emitted_record_refs" => ["limit-state-1", "derived-metric-1"]
        }
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-timer-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-alpha",
        binding_set_id: "managed-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :timer_handled,
        packet_id: "managed-packet-alpha",
        evidence_id: "managed-evidence-alpha",
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2},
        recorded_at: timer_at,
        metadata: %{}
      }
    ]
    |> Enum.map(fn capability_record ->
      capability_record
      |> Event.from_managed_capability_record(replay_run_id)
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()
    end)
  end

  defp persist_live_managed_capability_record_events!(
         org,
         mission,
         initialized_at,
         record_at,
         timer_at
       ) do
    [
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-initialized-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :initialized,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: nil,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0},
        recorded_at: initialized_at,
        metadata: %{}
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :record_handled,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: nil,
        emitted_record_kinds: [:derived_metric, :limit_state],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["managed-action-request-live-2"],
          "emitted_record_refs" => ["limit-state-live-1", "derived-metric-live-1"]
        }
      },
      %ManagedCapabilityRecord{
        capability_record_id: "managed-capability-record-live-timer-handled-1",
        mission_id: mission.mission_id,
        capability_instance_id: "managed-capability-live-alpha",
        family_key: :packet_counter,
        activation_id: "managed-activation-live-alpha",
        binding_set_id: "managed-binding-set-live-alpha",
        binding_set_version: 1,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha",
        event_kind: :timer_handled,
        packet_id: "managed-packet-live-alpha",
        evidence_id: "managed-evidence-live-alpha",
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2},
        recorded_at: timer_at,
        metadata: %{}
      }
    ]
    |> Enum.map(fn capability_record ->
      capability_record
      |> Event.from_managed_capability_record()
      |> Map.put(:organization_id, org.organization_id)
      |> persist_operational_event!()
    end)
  end

  defp persist_live_transport_runtime_events!(
         org,
         mission,
         record_at,
         action_at,
         timer_at
       ) do
    [
      %TransportCapabilityRecord{
        transport_record_id: "transport-runtime-live-record-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        event_kind: :control_input_handled,
        timer_key: nil,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["transport-action-request-live-1"],
          "emitted_record_refs" => ["uplink-frame-live-1"]
        }
      },
      %TransportActionRequest{
        action_request_id: "transport-action-request-live-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        command_release_attempt_id: "release-attempt-live-1",
        command_request_id: "command-request-live-1",
        source_endpoint_ref: "endpoint-live-alpha",
        command_name: "NOOP",
        signal_phase: :start,
        action_kind: :release_command,
        request_document: %{"command_request_id" => "command-request-live-1", "frame_count" => 1},
        requested_at: action_at,
        metadata: %{"release_attempt_id" => "release-attempt-live-1"}
      },
      %TransportTimerEvent{
        timer_event_id: "transport-timer-event-live-1",
        mission_id: mission.mission_id,
        realized_contact_id: "live-contact-alpha",
        path_id: "live-uplink-path",
        capability_instance_id: "transport-live-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-live-activation-alpha",
        binding_set_id: "transport-live-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-live-alpha",
        timer_key: "cop1_timeout",
        event_kind: :fired,
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"action_request_id" => "transport-action-request-live-1"}
      }
    ]
    |> Enum.map(fn
      %TransportCapabilityRecord{} = capability_record ->
        capability_record
        |> Event.from_transport_capability_record()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportActionRequest{} = action_request ->
        action_request
        |> Event.from_transport_action_request()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportTimerEvent{} = timer_event ->
        timer_event
        |> Event.from_transport_timer_event()
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()
    end)
  end

  defp persist_replay_transport_runtime_events!(
         org,
         mission,
         replay_run_id,
         record_at,
         action_at,
         timer_at
       ) do
    [
      %TransportCapabilityRecord{
        transport_record_id: "transport-runtime-record-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        event_kind: :control_input_handled,
        timer_key: nil,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        recorded_at: record_at,
        metadata: %{
          "action_request_ids" => ["transport-action-request-1"],
          "emitted_record_refs" => ["uplink-frame-1"]
        }
      },
      %TransportActionRequest{
        action_request_id: "transport-action-request-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        command_release_attempt_id: "release-attempt-1",
        command_request_id: "command-request-1",
        source_endpoint_ref: "endpoint-alpha",
        command_name: "NOOP",
        signal_phase: :start,
        action_kind: :release_command,
        request_document: %{"command_request_id" => "command-request-1", "frame_count" => 1},
        requested_at: action_at,
        metadata: %{"release_attempt_id" => "release-attempt-1"}
      },
      %TransportTimerEvent{
        timer_event_id: "transport-timer-event-1",
        mission_id: mission.mission_id,
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: "transport-alpha",
        family_key: :uplink_gateway,
        activation_id: "transport-activation-alpha",
        binding_set_id: "transport-binding-set-alpha",
        binding_set_version: 1,
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha",
        timer_key: "cop1_timeout",
        event_kind: :fired,
        due_at: action_at,
        occurred_at: timer_at,
        metadata: %{"action_request_id" => "transport-action-request-1"}
      }
    ]
    |> Enum.map(fn
      %TransportCapabilityRecord{} = capability_record ->
        capability_record
        |> Event.from_transport_capability_record(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportActionRequest{} = action_request ->
        action_request
        |> Event.from_transport_action_request(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()

      %TransportTimerEvent{} = timer_event ->
        timer_event
        |> Event.from_transport_timer_event(replay_run_id)
        |> Map.put(:organization_id, org.organization_id)
        |> persist_operational_event!()
    end)
  end

  defp persist_operational_event!(%Event{} = event) do
    assert {:ok, %Event{} = persisted_event} = OperationalEvents.persist_event(event)
    persisted_event
  end

  defp contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "dashboard-uplink-path",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "dashboard-downlink-path",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  defp persist_dashboard_realm!(
         mission,
         realm,
         capabilities \\ %{range_scan?: true, latest?: true}
       ) do
    data_source_id = "test-#{realm}-questdb-#{System.unique_integer([:positive])}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: capabilities
             })

    binding_id = "test-#{realm}-binding-#{System.unique_integer([:positive])}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  defp persist_replay_event_and_operational_sources!(mission) do
    unique = System.unique_integer([:positive])

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    operational_binding_id = "replay-operational-observables-#{unique}"
    events_binding_id = "replay-events-#{unique}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | binding_id: operational_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 metadata: %{bootstrap_default?: false}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_events_binding()
               | binding_id: events_binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "mission_events_replay",
                 metadata: %{bootstrap_default?: false}
             })

    %{
      operational_binding_id: operational_binding_id,
      operational_data_source_id:
        DataSources.default_operational_observables_data_source().data_source_id,
      events_binding_id: events_binding_id,
      events_data_source_id: DataSources.default_events_data_source().data_source_id
    }
  end

  defp persist_replay_connection_state_resources!(org, mission) do
    ground_station =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "replay-source-health-endpoint",
          "transport_id" => "replay-source-health-transport"
        }
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, ground_station)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-source-health-endpoint",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Endpoint",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    transport =
      Transport.new(%{
        transport_id: "replay-source-health-transport",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Transport",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => source_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, transport} = Cadence.persist_transport(org.organization_id, transport)

    {source_endpoint, transport}
  end

  defp record_replay_operational_source_health!(
         org,
         mission,
         replay_sources,
         observed_at,
         replay_run_id
       ) do
    assert {:ok, event, _status} =
             SourceHealth.record_source_health(
               %{
                 source_health_event_id: "source-health-rendered-replay-operational-observables",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: observed_at,
                 payload: %{
                   probe_kind: :connection_test,
                   probe_message: "Replay operational observables source probe degraded"
                 }
               },
               invalidate_runtime_cache?: false
             )

    intervals =
      Cadence.operational_source_health_intervals(org.organization_id, mission.mission_id,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        dataset: event.dataset,
        replay_run_id: replay_run_id,
        at: observed_at,
        order: :asc
      )

    interval =
      case intervals do
        [interval] ->
          interval

        other ->
          flunk("expected one filtered replay source-health interval, got #{inspect(other)}")
      end

    {event, interval}
  end

  defp transport_capability_record(
         mission_id,
         transport_record_id,
         capability_instance_id,
         event_kind,
         recorded_at,
         opts
       ) do
    %TransportCapabilityRecord{
      transport_record_id: transport_record_id,
      mission_id: mission_id,
      realized_contact_id: Keyword.get(opts, :contact_id, "replay-contact-alpha"),
      path_id: Keyword.get(opts, :path_id, "replay-uplink-path"),
      capability_instance_id: capability_instance_id,
      family_key: :heartbeat_monitor,
      activation_id: "replay-activation-1",
      binding_set_id: "replay-binding-set-1",
      binding_set_version: 1,
      partition_affinity: :source_endpoint,
      partition_value: "replay-source-health-endpoint",
      event_kind: event_kind,
      timer_key: Keyword.get(opts, :timer_key),
      emitted_record_kinds: Keyword.get(opts, :emitted_record_kinds, []),
      emitted_record_count: Keyword.get(opts, :emitted_record_count, 0),
      action_request_count: Keyword.get(opts, :action_request_count, 0),
      state_snapshot: Keyword.fetch!(opts, :state_snapshot),
      recorded_at: recorded_at,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp assert_transport_action_runtime_context!(
         view,
         release_attempt_id,
         command_request_id,
         replay_run_id
       ) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             command_request_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             release_attempt_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  defp assert_live_transport_action_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             "release-attempt-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-live-1"
           )
  end

  defp assert_live_transport_capability_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-runtime-live-record-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "cop1_state"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "vcid"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "transport-action-request-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )
  end

  defp assert_live_transport_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "live-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "live-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-live-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-live-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-live-1"
           )
  end

  defp assert_transport_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"]),
             "transport-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "cop1_timeout"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "transport-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  defp assert_managed_timer_runtime_context!(view, replay_run_id) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )
  end

  defp assert_live_managed_timer_runtime_context!(view) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"]),
             "managed-timer-event-live-1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-live-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"]),
             "flush"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "fired"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Due"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"]),
             "managed-action-request-live-1"
           )
  end

  defp configure_dashboard_source_health!(now) do
    previous = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:now, now)
      |> Keyword.put(:source_health_freshness, %{default_max_age_ms: 86_400_000})
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous)
    end)
  end

  defp operational_observable_state_event(
         organization_id,
         mission_id,
         snapshot_id,
         state,
         observed_at,
         opts
       ) do
    transport_id = Keyword.fetch!(opts, :transport_id)
    observable_id = Keyword.get(opts, :observable_id, "comms.transport.connection_state")
    resource_id = Keyword.get(opts, :resource_id, transport_id)
    scope_kind = Keyword.get(opts, :scope_kind, :transport)

    Event.from_operational_observable_state_snapshot(%{
      snapshot_id: snapshot_id,
      organization_id: organization_id,
      mission_id: mission_id,
      observable_id: observable_id,
      resource_id: resource_id,
      scope_kind: scope_kind,
      transport_id: transport_id,
      source_endpoint_id: "replay-source-health-endpoint",
      ground_station_id: "dss-14",
      link_id: Keyword.get(opts, :link_id),
      adapter_key: :tcp_socket,
      connection_state: connection_state_value(observable_id, state),
      rf_lock_state: rf_lock_state_value(observable_id, state),
      frame_sync_state: frame_sync_state_value(observable_id, state),
      state: state,
      replay_run_id: Keyword.get(opts, :replay_run_id),
      observed_at: observed_at
    })
  end

  defp connection_state_value("comms.transport.connection_state", state), do: state
  defp connection_state_value("ground.station.connection_state", state), do: state
  defp connection_state_value(_observable_id, _state), do: nil

  defp rf_lock_state_value("link.rf_lock_state", state), do: state
  defp rf_lock_state_value(_observable_id, _state), do: nil

  defp frame_sync_state_value("link.frame_sync_state", state), do: state
  defp frame_sync_state_value(_observable_id, _state), do: nil

  defp open_and_assert_replay_rf_evidence!(view, conn, attrs) do
    row_selector = Map.fetch!(attrs, :row_selector)
    widget_id = Map.fetch!(attrs, :widget_id)
    observable_id = Map.fetch!(attrs, :observable_id)
    replay_sources = Map.fetch!(attrs, :replay_sources)
    replay_run_id = Map.fetch!(attrs, :replay_run_id)
    interval = Map.fetch!(attrs, :interval)
    expected_snapshot_id = Map.fetch!(attrs, :expected_snapshot_id)
    expected_state = Map.fetch!(attrs, :expected_state)
    expected_transport_id = Map.fetch!(attrs, :expected_transport_id)

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(widget_id)}"
    assert evidence_path =~ "selected_observable=#{URI.encode_www_form(observable_id)}"
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
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="#{rf_interval_evidence_kind(observable_id)}"][data-evidence-ref-id="#{interval.interval_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{interval.source_event_id}"][data-evidence-ref-link-target="operational_event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form(observable_id)}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    rf_operational_event_id = interval.source_event_id
    rf_operational_event_route_id = URI.encode_www_form(rf_operational_event_id)
    rf_event_at_ms = DateTime.to_unix(interval.starts_at, :millisecond)

    rf_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational interval"][data-evidence-ref-id="#{rf_operational_event_id}"][data-evidence-ref-link-target="operational_event"])

    view
    |> element(rf_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{rf_operational_event_id}",
      "target" => "operational_event",
      "target-id" => rf_operational_event_id,
      "timestamp-ms" => rf_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    rf_event_path = assert_patch(view)
    assert rf_event_path =~ "panel=data_link"
    assert rf_event_path =~ "selected_target=operational_event"
    assert rf_event_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    rf_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert rf_event_copied_path =~ "panel=data_link"
    assert rf_event_copied_path =~ "selected_target=operational_event"
    assert rf_event_copied_path =~ "selected_id=#{rf_operational_event_route_id}"
    assert rf_event_copied_path =~ "selected_time=#{rf_event_at_ms}"
    assert rf_event_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert rf_event_copied_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert rf_event_copied_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_rf_event_view, _html} = live(conn, rf_event_copied_path)

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{rf_operational_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{rf_operational_event_route_id}"][data-clipboard-text*="selected_time=#{rf_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Observable"]),
             observable_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Resource"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Scope kind"]),
             "link"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport"]),
             expected_transport_id
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "replay-source-health-endpoint"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Ground station"]),
             "dss-14"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Link"]),
             "link-alpha"
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state"]),
             expected_state
           )

    assert has_element?(
             reopened_rf_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="RF state snapshot"]),
             expected_snapshot_id
           )

    stop_dashboard_view(reopened_rf_event_view)
  end

  defp rf_interval_evidence_kind("link.rf_lock_state"), do: "link rf lock state interval"
  defp rf_interval_evidence_kind("link.frame_sync_state"), do: "link frame sync state interval"

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp element_attribute(html, selector, attribute) do
    [value] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    value
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

    document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end
end
