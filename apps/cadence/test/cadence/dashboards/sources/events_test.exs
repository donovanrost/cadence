defmodule Cadence.Dashboards.Sources.EventsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Contacts.{RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DataBinding,
    DataLink,
    DataSource,
    EvidenceRef,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceHealthEvent,
    SourceResult,
    SourceWatermarkEvent
  }

  alias Cadence.Dashboards.Sources.Events
  alias Cadence.Jobs.Job
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents.Event
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias Cadence.Telemetry.Storage.ObservationIdentityDecisionEvent

  test "resolves contact intervals and mission timeline annotations" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:10:00Z]
    scheduled_start = ~U[2026-06-17 12:01:00Z]
    scheduled_end = ~U[2026-06-17 12:05:00Z]
    event_time = ~U[2026-06-17 12:03:00Z]
    parent = self()

    scheduled_contacts_fun = fn organization_id, mission_id, opts ->
      send(parent, {:scheduled_contacts, organization_id, mission_id, opts})

      [
        ScheduledContact.new(%{
          scheduled_contact_id: "contact-scheduled-1",
          organization_id: organization_id,
          mission_id: mission_id,
          source_endpoint_refs: ["endpoint-a"],
          starts_at: scheduled_start,
          ends_at: scheduled_end,
          provider_contact_ref: "DSS-14 pass"
        })
      ]
    end

    realized_contacts_fun = fn organization_id, mission_id, opts ->
      send(parent, {:realized_contacts, organization_id, mission_id, opts})

      [
        RealizedContact.new(%{
          realized_contact_id: "contact-realized-1",
          organization_id: organization_id,
          mission_id: mission_id,
          source_endpoint_refs: ["endpoint-a"],
          realized_at: event_time,
          lifecycle_state: :active
        })
      ]
    end

    mission_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:mission_events, organization_id, mission_id, opts})

      [
        Entry.new(%{
          mission_event_id: "mission-event-1",
          mission_id: mission_id,
          occurred_at: event_time,
          category: :health,
          kind: :limit_violation,
          severity: :warning,
          title: "Battery voltage high",
          source_record_kind: :limit_event,
          source_record_id: "limit-event-1",
          subject_kind: :telemetry_point,
          subject_id: "HK.battery_voltage",
          spacecraft_id: "sc-1"
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :receipt_time, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:contact_intervals, :mission_timeline],
            limit: 25
          }
        ),
        scheduled_contacts_fun: scheduled_contacts_fun,
        realized_contacts_fun: realized_contacts_fun,
        mission_events_fun: mission_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "events-request-1", frames: [contacts, timeline]} = result
    assert %Frame{source: :events, shape: :intervals, time_axis: :occurred_at} = contacts
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = timeline

    assert [
             %Field{name: "starts_at", kind: :time, values: [^scheduled_start, ^event_time]},
             %Field{name: "ends_at", kind: :time, values: [^scheduled_end, nil]},
             %Field{name: "kind", kind: :enum, values: [:scheduled_contact, :realized_contact]},
             %Field{name: "status", kind: :enum, values: [:scheduled, :active]},
             %Field{
               name: "label",
               kind: :string,
               values: ["DSS-14 pass", "realized contact contact-realized-1"]
             },
             %Field{
               name: "contact_id",
               kind: :string,
               values: ["contact-scheduled-1", "contact-realized-1"]
             },
             %Field{name: "source_event_id", kind: :string, values: [nil, nil]}
           ] = contacts.fields

    assert contacts.meta.family == :contacts
    assert contacts.meta.projection == :contacts
    assert contacts.meta.returned_intervals == 2
    assert contacts.meta.realm == :flight
    assert contacts.meta.data_source_id == "managed_events_projection"

    assert [
             %EvidenceRef{kind: :scheduled_contact, id: "contact-scheduled-1", source: :events},
             %EvidenceRef{kind: :realized_contact, id: "contact-realized-1", source: :events}
           ] = contacts.meta.evidence

    assert [
             %DataLink{target: :contact, target_id: "contact-scheduled-1", source: :frame},
             %DataLink{target: :contact, target_id: "contact-realized-1", source: :frame}
           ] = contacts.meta.links

    assert [
             %Field{name: "occurred_at", kind: :time, values: [^event_time]},
             %Field{name: "category", kind: :enum, values: [:health]},
             %Field{name: "kind", kind: :enum, values: [:limit_violation]},
             %Field{name: "severity", kind: :enum, values: [:warning]},
             %Field{name: "title", kind: :string, values: ["Battery voltage high"]},
             %Field{name: "mission_event_id", kind: :string, values: ["mission-event-1"]},
             %Field{name: "source_record_id", kind: :string, values: ["limit-event-1"]}
           ] = timeline.fields

    assert timeline.meta.family == :mission_timeline
    assert timeline.meta.projection == :mission_events
    assert timeline.meta.returned_events == 1
    assert timeline.meta.cursor == %{occurred_at: event_time, mission_event_id: "mission-event-1"}

    assert [%EvidenceRef{kind: :mission_event, id: "mission-event-1", source: :events}] =
             timeline.meta.evidence

    assert [%DataLink{target: :mission_event, target_id: "mission-event-1", source: :frame}] =
             timeline.meta.links

    assert result.meta.supported_capability == [:contact_intervals, :mission_timeline]
    refute result.meta.degraded?

    assert [
             %ResolveWarning{
               code: :event_time_axis_mismatch,
               severity: :info,
               details: %{requested_axis: :receipt_time, returned_axis: :occurred_at}
             }
           ] = result.warnings

    assert_receive {:scheduled_contacts, "org-1", "mission-1", scheduled_opts}
    assert scheduled_opts[:from_occurred_at] == from_time
    assert scheduled_opts[:to_occurred_at] == to_time
    assert scheduled_opts[:realm] == :flight
    assert scheduled_opts[:data_source_id] == "managed_events_projection"
    assert scheduled_opts[:limit] == 25

    assert_receive {:realized_contacts, "org-1", "mission-1", realized_opts}
    assert realized_opts[:dataset] == "mission_events"

    assert_receive {:mission_events, "org-1", "mission-1", mission_event_opts}
    assert mission_event_opts[:spacecraft_id] == "sc-1"
    assert mission_event_opts[:order] == :asc
  end

  test "preserves replay context for contact intervals and mission timeline readers" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:10:00Z]
    event_time = ~U[2026-06-17 12:03:00Z]
    parent = self()

    contact_operational_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:contact_operational_events, organization_id, mission_id, opts})

      [
        Event.new(%{
          event_id: "operational-event-replay-scheduled-contact-1",
          organization_id: organization_id,
          mission_id: mission_id,
          occurred_at: ~U[2026-06-17 12:01:00Z],
          recorded_at: ~U[2026-06-17 12:01:00Z],
          effective_at: ~U[2026-06-17 12:01:00Z],
          category: :contact,
          kind: :scheduled_contact_interval,
          severity: :info,
          actor: %{kind: :replay, id: "replay-run-1"},
          subject: %{kind: :contact, id: "replay-scheduled-contact-1"},
          scope: %{
            source_endpoint_ref: "endpoint-a",
            replay_run_id: "replay-run-1"
          },
          causality: %{replay_run_id: "replay-run-1"},
          payload: %{
            scheduled_contact_id: "replay-scheduled-contact-1",
            starts_at: ~U[2026-06-17 12:01:00Z],
            ends_at: ~U[2026-06-17 12:05:00Z],
            status: :scheduled,
            provider_contact_ref: "Replay DSS-14 pass",
            source_endpoint_refs: ["endpoint-a"]
          }
        }),
        Event.new(%{
          event_id: "operational-event-replay-realized-contact-1",
          organization_id: organization_id,
          mission_id: mission_id,
          occurred_at: event_time,
          recorded_at: event_time,
          effective_at: event_time,
          category: :contact,
          kind: :realized_contact_interval,
          severity: :info,
          actor: %{kind: :replay, id: "replay-run-1"},
          subject: %{kind: :contact, id: "replay-realized-contact-1"},
          scope: %{
            source_endpoint_ref: "endpoint-a",
            replay_run_id: "replay-run-1"
          },
          causality: %{replay_run_id: "replay-run-1"},
          payload: %{
            realized_contact_id: "replay-realized-contact-1",
            starts_at: event_time,
            status: :active,
            source_endpoint_refs: ["endpoint-a"]
          }
        })
      ]
    end

    mission_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:mission_events, organization_id, mission_id, opts})

      [
        Entry.new(%{
          mission_event_id: "replay-mission-event-1",
          mission_id: mission_id,
          occurred_at: event_time,
          category: :runtime,
          kind: :managed_action_requested,
          severity: :info,
          title: "Replay action requested",
          source_record_kind: :managed_action_request,
          source_record_id: "replay-action-1",
          subject_kind: :capability_instance,
          subject_id: "capability-1",
          spacecraft_id: "sc-1"
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            from: from_time,
            to: to_time,
            replay_run_id: "replay-run-1"
          },
          data_context: %{
            realm: :replay,
            replay_run_id: "replay-run-1",
            source_contexts: %{
              events: %{
                data_source_id: "replay-events-projection",
                source_binding_id: "replay-events",
                dataset: "replay_mission_events"
              }
            }
          },
          sampling: %{
            mode: :event_history,
            products: [:contact_intervals, :mission_timeline],
            limit: 25
          }
        ),
        contact_operational_events_fun: contact_operational_events_fun,
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          flunk("replay contact intervals should not read scheduled contacts")
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          flunk("replay contact intervals should not read realized contacts")
        end,
        mission_events_fun: mission_events_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{request_id: "events-request-1", frames: [contacts, timeline]} = result
    assert contacts.meta.realm == :replay
    assert contacts.meta.data_source_id == "replay-events-projection"
    assert contacts.meta.source_binding_id == "replay-events"
    assert contacts.meta.dataset == "replay_mission_events"
    assert contacts.meta.replay_run_id == "replay-run-1"
    assert contacts.meta.projection == :operational_events
    assert hd(contacts.meta.links).context.data.replay_run_id == "replay-run-1"

    contact_fields = Map.new(contacts.fields, &{&1.name, &1})

    assert contact_fields["contact_id"].values == [
             "replay-scheduled-contact-1",
             "replay-realized-contact-1"
           ]

    assert contact_fields["kind"].values == [:scheduled_contact, :realized_contact]

    assert timeline.meta.realm == :replay
    assert timeline.meta.data_source_id == "replay-events-projection"
    assert timeline.meta.source_binding_id == "replay-events"
    assert timeline.meta.dataset == "replay_mission_events"
    assert timeline.meta.replay_run_id == "replay-run-1"
    assert hd(timeline.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:contact_operational_events, "org-1", "mission-1", contact_event_opts}
    assert contact_event_opts[:from_occurred_at] == from_time
    assert contact_event_opts[:to_occurred_at] == to_time
    assert contact_event_opts[:realm] == :replay
    assert contact_event_opts[:data_source_id] == "replay-events-projection"
    assert contact_event_opts[:source_binding_id] == "replay-events"
    assert contact_event_opts[:dataset] == "replay_mission_events"
    assert contact_event_opts[:replay_run_id] == "replay-run-1"
    assert contact_event_opts[:limit] == 25

    assert_receive {:mission_events, "org-1", "mission-1", mission_event_opts}
    assert mission_event_opts[:realm] == :replay
    assert mission_event_opts[:replay_run_id] == "replay-run-1"
    assert mission_event_opts[:data_source_id] == "replay-events-projection"
    assert mission_event_opts[:source_binding_id] == "replay-events"
    assert mission_event_opts[:dataset] == "replay_mission_events"
    assert mission_event_opts[:spacecraft_id] == "sc-1"
  end

  test "returns unsupported-family warning without calling readers for unsupported sampling" do
    result =
      Events.resolve(
        source_request(sampling: %{mode: :latest}),
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          flunk("contacts should not be read")
        end
      )

    assert %SourceResult{frames: [], warnings: [%ResolveWarning{} = warning]} = result
    assert warning.code == :unsupported_sampling
    assert result.meta.degraded?
  end

  test "maps contact primary scope to contact reader filters" do
    parent = self()

    mission_events_fun = fn _organization_id, _mission_id, opts ->
      send(parent, {:mission_event_opts, opts})
      []
    end

    result =
      Events.resolve(
        source_request(
          scope_context: %{
            primary: %{kind: "contact", mode: "one", ids: ["contact-1"]}
          },
          sampling: %{mode: :event_history, products: [:mission_timeline]}
        ),
        mission_events_fun: mission_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [%Frame{}]} = result
    assert_receive {:mission_event_opts, opts}
    assert opts[:scheduled_contact_id] == "contact-1"
    assert opts[:realized_contact_id] == "contact-1"
    refute Keyword.has_key?(opts, :spacecraft_id)
  end

  test "resolves source-health transitions as event markers" do
    from_time = ~U[2026-06-21 12:00:00Z]
    to_time = ~U[2026-06-21 12:10:00Z]
    parent = self()

    source_health_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_health_events, organization_id, mission_id, opts})

      [
        SourceHealthEvent.new(%{
          source_health_event_id: "source-health-1",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :telemetry,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry",
          realm: :flight,
          dataset: "flight",
          source_health: :degraded,
          previous_source_health: :healthy,
          reason: :source_probe_failed,
          observed_at: ~U[2026-06-21 12:02:00Z]
        }),
        SourceHealthEvent.new(%{
          source_health_event_id: "source-health-2",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :limits,
          data_source_id: "limits-projection",
          source_binding_id: "limits-observed",
          realm: :flight,
          dataset: "limits",
          source_health: :healthy,
          previous_source_health: :degraded,
          reason: :source_recovered,
          observed_at: ~U[2026-06-21 12:04:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:source_health],
            limit: 10
          }
        ),
        source_health_events_fun: source_health_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:source_health_transitions"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["occurred_at"].kind == :time

    assert Enum.map(fields["occurred_at"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:02:00.000000Z",
             "2026-06-21T12:04:00.000000Z"
           ]

    assert fields["category"].values == [:source_health, :source_health]
    assert fields["kind"].values == [:degraded, :recovered]
    assert fields["severity"].values == [:warning, :info]
    assert fields["title"].values == ["telemetry source degraded", "limits source healthy"]
    assert fields["source_record_id"].values == ["source-health-1", "source-health-2"]
    assert fields["source_health"].values == [:degraded, :healthy]
    assert fields["previous_source_health"].values == [:healthy, :degraded]
    assert fields["reason"].values == [:source_probe_failed, :source_recovered]
    assert fields["logical_source"].values == [:telemetry, :limits]
    assert fields["data_source_id"].values == ["flight-questdb", "limits-projection"]
    assert fields["source_binding_id"].values == ["flight-telemetry", "limits-observed"]
    assert fields["realm"].values == [:flight, :flight]
    assert fields["replay_run_id"].values == [nil, nil]
    assert fields["dataset"].values == ["flight", "limits"]

    assert frame.meta.family == :source_health
    assert frame.meta.product == :source_health_transitions
    assert frame.meta.projection == :dashboard_source_health_events
    assert frame.meta.returned_events == 2

    assert frame.meta.cursor.source_health_event_id == "source-health-2"
    assert DateTime.to_iso8601(frame.meta.cursor.observed_at) == "2026-06-21T12:04:00.000000Z"

    assert_evidence_ref(frame.meta.evidence, :source_health_event, "source-health-1")
    assert_evidence_ref(frame.meta.evidence, :source_health_event, "source-health-2")

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:source_health_event:source-health-1"
    )

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:source_health_event:source-health-2"
    )

    assert_data_link(frame.meta.links, :source_health_event, "source-health-1")
    assert_data_link(frame.meta.links, :source_health_event, "source-health-2")

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:source_health_event:source-health-1"
    )

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:source_health_event:source-health-2"
    )

    assert result.meta.supported_capability == [:source_health_transitions]

    assert_receive {:source_health_events, "org-1", "mission-1", opts}
    assert opts[:from_observed_at] == from_time
    assert opts[:to_observed_at] == to_time
    assert opts[:realm] == :flight
    assert opts[:limit] == 10
    refute Keyword.has_key?(opts, :data_source_id)
    refute Keyword.has_key?(opts, :logical_source)
  end

  test "resolves source-health transitions with replay run context" do
    parent = self()

    source_health_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_health_events, organization_id, mission_id, opts})

      [
        SourceHealthEvent.new(%{
          source_health_event_id: "replay-source-health-1",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :telemetry,
          data_source_id: "replay-questdb",
          source_binding_id: "replay-telemetry",
          realm: :replay,
          replay_run_id: "replay-run-1",
          dataset: "replay",
          source_health: :degraded,
          previous_source_health: :healthy,
          reason: :source_probe_failed,
          observed_at: ~U[2026-06-21 12:02:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:source_health],
            source_health: %{
              logical_source: :telemetry,
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              dataset: "replay"
            },
            limit: 10
          }
        ),
        source_health_events_fun: source_health_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    operational_event_id =
      "operational_event:source_health_event:replay-run-1:replay-source-health-1"

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert fields["dataset"].values == ["replay"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert_evidence_ref(frame.meta.evidence, :operational_event, operational_event_id)
    assert_data_link(frame.meta.links, :operational_event, operational_event_id)
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:source_health_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:source_binding_id] == "replay-telemetry"
    assert opts[:dataset] == "replay"
  end

  test "resolves source watermark events with movement cursors" do
    from_time = ~U[2026-06-21 12:00:00Z]
    to_time = ~U[2026-06-21 12:10:00Z]
    parent = self()

    source_watermark_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_watermark_events, organization_id, mission_id, opts})

      [
        SourceWatermarkEvent.new(%{
          source_watermark_event_id: "watermark-event-1",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :telemetry,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry",
          realm: :flight,
          dataset: "flight",
          event_type: :advanced,
          previous_complete_through: ~U[2026-06-21 12:01:00Z],
          complete_through: ~U[2026-06-21 12:05:00Z],
          previous_latest_receipt_time: ~U[2026-06-21 12:01:30Z],
          latest_receipt_time: ~U[2026-06-21 12:05:30Z],
          retention_starts_at: ~U[2026-06-20 00:00:00Z],
          sample_count: 42,
          confidence: :authoritative,
          reason: :source_watermark_observed,
          observed_at: ~U[2026-06-21 12:06:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:source_watermarks],
            source_watermark: %{
              logical_source: :telemetry,
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              dataset: "flight"
            },
            limit: 10
          }
        ),
        source_watermark_events_fun: source_watermark_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:source_watermark_events"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert Enum.map(fields["occurred_at"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:06:00.000000Z"
           ]

    assert fields["category"].values == [:source_watermark]
    assert fields["kind"].values == [:advanced]
    assert fields["severity"].values == [:info]
    assert fields["title"].values == ["telemetry watermark advanced"]
    assert fields["source_record_id"].values == ["watermark-event-1"]
    assert fields["logical_source"].values == [:telemetry]
    assert fields["data_source_id"].values == ["flight-questdb"]
    assert fields["source_binding_id"].values == ["flight-telemetry"]
    assert fields["realm"].values == [:flight]
    assert fields["replay_run_id"].values == [nil]
    assert fields["dataset"].values == ["flight"]

    assert Enum.map(fields["previous_complete_through"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:01:00.000000Z"
           ]

    assert Enum.map(fields["complete_through"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:05:00.000000Z"
           ]

    assert Enum.map(fields["previous_latest_receipt_time"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:01:30.000000Z"
           ]

    assert Enum.map(fields["latest_receipt_time"].values, &DateTime.to_iso8601/1) == [
             "2026-06-21T12:05:30.000000Z"
           ]

    assert Enum.map(fields["retention_starts_at"].values, &DateTime.to_iso8601/1) == [
             "2026-06-20T00:00:00.000000Z"
           ]

    assert fields["confidence"].values == [:authoritative]
    assert fields["reason"].values == [:source_watermark_observed]

    assert frame.meta.family == :source_watermark
    assert frame.meta.product == :source_watermark_events
    assert frame.meta.projection == :dashboard_source_watermark_events
    assert frame.meta.returned_events == 1
    assert frame.meta.cursor.source_watermark_event_id == "watermark-event-1"
    assert_evidence_ref(frame.meta.evidence, :source_watermark_event, "watermark-event-1")

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:source_watermark_event:watermark-event-1"
    )

    assert_data_link(frame.meta.links, :source_watermark_event, "watermark-event-1")

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:source_watermark_event:watermark-event-1"
    )

    assert DateTime.to_iso8601(frame.meta.cursor.complete_through) ==
             "2026-06-21T12:05:00.000000Z"

    assert result.meta.supported_capability == [:source_watermark_events]

    assert_receive {:source_watermark_events, "org-1", "mission-1", opts}
    assert opts[:from_observed_at] == from_time
    assert opts[:to_observed_at] == to_time
    assert opts[:realm] == :flight
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "flight-questdb"
    assert opts[:source_binding_id] == "flight-telemetry"
    assert opts[:dataset] == "flight"
    assert opts[:limit] == 10
  end

  test "resolves source capability posture operational events" do
    from_time = ~U[2026-06-21 12:00:00Z]
    to_time = ~U[2026-06-21 12:10:00Z]
    parent = self()

    source_capability_posture_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_capability_posture_events, organization_id, mission_id, opts})

      [
        Event.from_source_capability_posture(%{
          organization_id: organization_id,
          mission_id: mission_id,
          source_capability_posture_id: "dashboard-1:resolve-1:events-request-1",
          dashboard_id: "dashboard-1",
          resolve_id: "resolve-1",
          source_request_id: "events-request-1",
          logical_source: :telemetry,
          data_source_id: "flight-questdb",
          source_binding_id: "flight-telemetry",
          realm: :flight,
          dataset: "flight",
          status: :fallback,
          requested_sampling: :window,
          supported_sampling: [:latest, :window],
          requested_products: [:link_rf_metric_history],
          supported_products: [:transport_bitrate_history],
          requested_time_axis: :generation_time,
          executed_time_axis: :receipt_time,
          supported_time_axes: [:receipt_time],
          fallbacks: [:receipt_time_axis],
          unsupported: [],
          source_execution_status: :resolved,
          source_execution_cache_status: :miss,
          observed_at: ~U[2026-06-21 12:03:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:source_capabilities],
            source_capability: %{
              logical_source: :telemetry,
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              dashboard_id: "dashboard-1",
              status: :fallback,
              dataset: "flight"
            },
            limit: 10
          }
        ),
        source_capability_posture_events_fun: source_capability_posture_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:source_capability_postures"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["occurred_at"].values == [~U[2026-06-21 12:03:00Z]]

    assert fields["category"].values == [:source_capability]
    assert fields["kind"].values == [:source_capability_fallback]
    assert fields["severity"].values == [:warning]
    assert fields["title"].values == ["telemetry capability fallback"]
    assert fields["source_record_id"].values == ["dashboard-1:resolve-1:events-request-1"]

    assert fields["operational_event_id"].values == [
             "operational_event:source_capability_posture:dashboard-1:resolve-1:events-request-1"
           ]

    assert fields["source_request_id"].values == ["events-request-1"]
    assert fields["dashboard_id"].values == ["dashboard-1"]
    assert fields["resolve_id"].values == ["resolve-1"]
    assert fields["logical_source"].values == [:telemetry]
    assert fields["data_source_id"].values == ["flight-questdb"]
    assert fields["source_binding_id"].values == ["flight-telemetry"]
    assert fields["realm"].values == [:flight]
    assert fields["replay_run_id"].values == [nil]
    assert fields["dataset"].values == ["flight"]
    assert fields["capability_status"].values == [:fallback]
    assert fields["requested_time_axis"].values == [:generation_time]
    assert fields["executed_time_axis"].values == [:receipt_time]
    assert fields["supported_time_axes"].values == ["receipt_time"]
    assert fields["requested_sampling"].values == [:window]
    assert fields["supported_sampling"].values == ["latest, window"]
    assert fields["requested_products"].values == ["link_rf_metric_history"]
    assert fields["supported_products"].values == ["transport_bitrate_history"]
    assert fields["fallbacks"].values == ["receipt_time_axis"]
    assert fields["unsupported"].values == [nil]
    assert fields["source_execution_status"].values == [:resolved]
    assert fields["source_execution_cache_status"].values == [:miss]

    assert frame.meta.family == :source_capability
    assert frame.meta.product == :source_capability_postures
    assert frame.meta.projection == :operational_events
    assert frame.meta.returned_events == 1

    assert frame.meta.cursor == %{
             occurred_at: ~U[2026-06-21 12:03:00Z],
             source_capability_posture_id: "dashboard-1:resolve-1:events-request-1",
             source_request_id: "events-request-1",
             capability_status: :fallback
           }

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:source_capability_posture:dashboard-1:resolve-1:events-request-1"
    )

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:source_capability_posture:dashboard-1:resolve-1:events-request-1"
    )

    assert result.meta.supported_capability == [:source_capability_postures]

    assert_receive {:source_capability_posture_events, "org-1", "mission-1", opts}
    assert opts[:from_occurred_at] == from_time
    assert opts[:to_occurred_at] == to_time
    assert opts[:realm] == :flight
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "flight-questdb"
    assert opts[:source_binding_id] == "flight-telemetry"
    assert opts[:dashboard_id] == "dashboard-1"
    assert opts[:status] == :fallback
    assert opts[:dataset] == "flight"
    assert opts[:limit] == 10
  end

  test "resolves source capability posture events with replay run context" do
    from_time = ~U[2026-06-21 12:00:00Z]
    to_time = ~U[2026-06-21 12:10:00Z]
    parent = self()

    source_capability_posture_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_capability_posture_events, organization_id, mission_id, opts})

      [
        Event.from_source_capability_posture(%{
          organization_id: organization_id,
          mission_id: mission_id,
          source_capability_posture_id: "dashboard-1:resolve-1:events-request-1",
          dashboard_id: "dashboard-1",
          resolve_id: "resolve-1",
          source_request_id: "events-request-1",
          logical_source: :telemetry,
          data_source_id: "replay-questdb",
          source_binding_id: "replay-telemetry",
          realm: :replay,
          replay_run_id: "replay-run-1",
          dataset: "replay",
          status: :fallback,
          requested_sampling: :window,
          supported_sampling: [:latest, :window],
          requested_time_axis: :generation_time,
          executed_time_axis: :receipt_time,
          supported_time_axes: [:receipt_time],
          fallbacks: [:receipt_time_axis],
          unsupported: [],
          source_execution_status: :resolved,
          source_execution_cache_status: :miss,
          observed_at: ~U[2026-06-21 12:03:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            from: from_time,
            to: to_time,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:source_capabilities],
            source_capability: %{
              logical_source: :telemetry,
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              dashboard_id: "dashboard-1",
              status: :fallback,
              dataset: "replay"
            },
            limit: 10
          }
        ),
        source_capability_posture_events_fun: source_capability_posture_events_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    operational_event_id =
      "operational_event:source_capability_posture:replay-run-1:dashboard-1:resolve-1:events-request-1"

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"

    assert_evidence_ref(frame.meta.evidence, :operational_event, operational_event_id)
    assert_data_link(frame.meta.links, :operational_event, operational_event_id)
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:source_capability_posture_events, "org-1", "mission-1", opts}
    assert opts[:from_occurred_at] == from_time
    assert opts[:to_occurred_at] == to_time
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:source_binding_id] == "replay-telemetry"
    assert opts[:dashboard_id] == "dashboard-1"
    assert opts[:status] == :fallback
    assert opts[:dataset] == "replay"
    assert opts[:limit] == 10
  end

  test "resolves source watermark events with replay run context" do
    parent = self()

    source_watermark_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:source_watermark_events, organization_id, mission_id, opts})

      [
        SourceWatermarkEvent.new(%{
          source_watermark_event_id: "replay-watermark-event-1",
          organization_id: organization_id,
          mission_id: mission_id,
          logical_source: :telemetry,
          data_source_id: "replay-questdb",
          source_binding_id: "replay-telemetry",
          realm: :replay,
          replay_run_id: "replay-run-1",
          dataset: "replay",
          event_type: :observed,
          complete_through: ~U[2026-06-21 12:05:00Z],
          latest_receipt_time: ~U[2026-06-21 12:05:30Z],
          retention_starts_at: ~U[2026-06-20 00:00:00Z],
          sample_count: 42,
          confidence: :best_effort,
          reason: :source_watermark_observed,
          observed_at: ~U[2026-06-21 12:06:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:source_watermarks],
            source_watermark: %{
              logical_source: :telemetry,
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              dataset: "replay"
            },
            limit: 10
          }
        ),
        source_watermark_events_fun: source_watermark_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    operational_event_id =
      "operational_event:source_watermark_event:replay-run-1:replay-watermark-event-1"

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert_evidence_ref(frame.meta.evidence, :operational_event, operational_event_id)
    assert_data_link(frame.meta.links, :operational_event, operational_event_id)
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:source_watermark_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:logical_source] == :telemetry
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:source_binding_id] == "replay-telemetry"
    assert opts[:dataset] == "replay"
  end

  test "resolves telemetry revision decision events by source window" do
    from_time = ~U[2026-06-22 12:00:00Z]
    to_time = ~U[2026-06-22 12:30:00Z]
    parent = self()

    telemetry_revision_decision_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_revision_decision_events, organization_id, mission_id, opts})

      [
        ObservationIdentityDecisionEvent.new(%{
          decision_event_id: "decision-event-1",
          observation_identity_id: "identity-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :flight,
          data_source_id: "flight-questdb",
          binding_id: "flight-telemetry",
          observable_id: "HK.counter",
          point_id: "HK.counter",
          spacecraft_id: "sc-1",
          decision: :mark_canonical,
          decision_reason: "operator_selected_corrected_value",
          actor_id: "ops-1",
          actor_kind: "operator",
          previous_state: %{
            "validity_state" => "conflict",
            "canonical_revision" => 1
          },
          new_state: %{
            "validity_state" => "canonical",
            "canonical_revision" => 2
          },
          occurred_at: ~U[2026-06-22 12:10:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_revisions],
            telemetry_revision: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              point_id: "HK.counter",
              decision: :mark_canonical
            },
            limit: 10
          }
        ),
        telemetry_revision_decision_events_fun: telemetry_revision_decision_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:telemetry_revision_decisions"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["occurred_at"].values == [~U[2026-06-22 12:10:00Z]]

    assert fields["category"].values == [:telemetry_revision]
    assert fields["kind"].values == [:mark_canonical]
    assert fields["severity"].values == [:info]
    assert fields["title"].values == ["HK.counter revision canonical"]
    assert fields["source_record_id"].values == ["decision-event-1"]
    assert fields["observation_identity_id"].values == ["identity-1"]
    assert fields["realm"].values == [:flight]
    assert fields["replay_run_id"].values == [nil]
    assert fields["data_source_id"].values == ["flight-questdb"]
    assert fields["source_binding_id"].values == ["flight-telemetry"]
    assert fields["observable_id"].values == ["HK.counter"]
    assert fields["point_id"].values == ["HK.counter"]
    assert fields["spacecraft_id"].values == ["sc-1"]
    assert fields["decision_reason"].values == ["operator_selected_corrected_value"]
    assert fields["actor_id"].values == ["ops-1"]
    assert fields["actor_kind"].values == ["operator"]
    assert fields["previous_validity_state"].values == ["conflict"]
    assert fields["new_validity_state"].values == ["canonical"]
    assert fields["previous_canonical_revision"].values == [1]
    assert fields["new_canonical_revision"].values == [2]

    assert frame.meta.family == :telemetry_revision
    assert frame.meta.product == :telemetry_revision_decisions
    assert frame.meta.projection == :telemetry_observation_identity_decision_events
    assert frame.meta.returned_events == 1
    assert frame.meta.cursor.decision_event_id == "decision-event-1"
    assert frame.meta.cursor.observation_identity_id == "identity-1"

    assert_evidence_ref(
      frame.meta.evidence,
      :telemetry_revision_decision_event,
      "decision-event-1"
    )

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:telemetry_observation_identity_decision_event:decision-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :telemetry_revision_decision_event,
      "decision-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:telemetry_observation_identity_decision_event:decision-event-1"
    )

    assert hd(frame.meta.links).context.data.data_source_id == "managed_events_projection"
    assert hd(frame.meta.links).context.data.source_binding_id == "default_flight_events"
    assert result.meta.supported_capability == [:telemetry_revision_decisions]

    assert_receive {:telemetry_revision_decision_events, "org-1", "mission-1", opts}
    assert opts[:from_occurred_at] == from_time
    assert opts[:to_occurred_at] == to_time
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "flight-questdb"
    assert opts[:binding_id] == "flight-telemetry"
    assert opts[:point_id] == "HK.counter"
    assert opts[:decision] == :mark_canonical
    assert opts[:limit] == 10
    refute Keyword.has_key?(opts, :source_binding_id)
  end

  test "resolves telemetry revision decision events with replay run context" do
    parent = self()

    telemetry_revision_decision_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_revision_decision_events, organization_id, mission_id, opts})

      [
        ObservationIdentityDecisionEvent.new(%{
          decision_event_id: "replay-decision-event-1",
          observation_identity_id: "replay-identity-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :replay,
          replay_run_id: "replay-run-1",
          data_source_id: "replay-questdb",
          binding_id: "replay-telemetry",
          observable_id: "HK.counter",
          point_id: "HK.counter",
          spacecraft_id: "sc-1",
          decision: :mark_conflict,
          decision_reason: "operator_reviewed_replay_conflict",
          previous_state: %{"validity_state" => "canonical"},
          new_state: %{"validity_state" => "conflict"},
          occurred_at: ~U[2026-06-22 12:10:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_revisions],
            telemetry_revision: %{
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              point_id: "HK.counter"
            },
            limit: 10
          }
        ),
        telemetry_revision_decision_events_fun: telemetry_revision_decision_events_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:telemetry_revision_decision_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:binding_id] == "replay-telemetry"
    assert opts[:point_id] == "HK.counter"
  end

  test "resolves telemetry backfill lifecycle events by affected source window" do
    from_time = ~U[2026-06-22 11:30:00Z]
    to_time = ~U[2026-06-22 11:45:00Z]
    parent = self()

    telemetry_backfill_lifecycle_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_backfill_lifecycle_events, organization_id, mission_id, opts})

      [
        BackfillLifecycleEvent.new(%{
          backfill_lifecycle_event_id: "backfill-event-1",
          backfill_run_id: "backfill-run-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :flight,
          data_source_id: "flight-questdb",
          binding_id: "flight-telemetry",
          observable_id: "HK.counter",
          point_id: "HK.counter",
          spacecraft_id: "sc-1",
          event_type: :late_data_accepted,
          source_from: ~U[2026-06-22 11:00:00Z],
          source_to: ~U[2026-06-22 12:00:00Z],
          receipt_from: ~U[2026-06-22 12:10:00Z],
          receipt_to: ~U[2026-06-22 12:20:00Z],
          sample_count: 42,
          authority: :authoritative,
          reason: :late_arrival_policy,
          actor_id: "ops-1",
          actor_kind: "operator",
          occurred_at: ~U[2026-06-22 12:21:00Z],
          payload: %{
            selected_sample_count: 2,
            projection_effect: :canonical_history_and_current_projection,
            write_validity_state: :canonical,
            record_current_values: true,
            refresh_latest_value: true
          }
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{axis: :occurred_at, from: from_time, to: to_time},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_backfills],
            telemetry_backfill: %{
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              observable_id: "HK.counter",
              authority: :authoritative
            },
            limit: 10
          }
        ),
        telemetry_backfill_lifecycle_events_fun: telemetry_backfill_lifecycle_events_fun,
        telemetry_backfill_workflow_job_fun: fn _event ->
          Job.new(%{
            mission_id: "mission-1",
            job_type: :telemetry_historical_data_workflow,
            run_id: "backfill-run-1",
            status: :failed,
            failure_reason: "dispatcher unavailable"
          })
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :events, shape: :events, time_axis: :occurred_at} = frame
    assert frame.frame_id == "events-request-1:telemetry_backfill_lifecycle"

    fields = Map.new(frame.fields, &{&1.name, &1})

    assert Enum.map(fields["occurred_at"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:21:00.000000Z"
           ]

    assert fields["category"].values == [:telemetry_backfill]
    assert fields["kind"].values == [:late_data_accepted]
    assert fields["severity"].values == [:info]
    assert fields["title"].values == ["HK.counter late data accepted"]
    assert fields["source_record_id"].values == ["backfill-event-1"]
    assert fields["backfill_run_id"].values == ["backfill-run-1"]
    assert fields["workflow_run_id"].values == ["backfill-run-1"]
    assert Enum.all?(fields["workflow_job_id"].values, &is_binary/1)
    assert fields["workflow_job_status"].values == [:failed]
    assert fields["workflow_job_failure"].values == ["dispatcher unavailable"]
    assert fields["realm"].values == [:flight]
    assert fields["data_source_id"].values == ["flight-questdb"]
    assert fields["source_binding_id"].values == ["flight-telemetry"]
    assert fields["observable_id"].values == ["HK.counter"]
    assert fields["point_id"].values == ["HK.counter"]
    assert fields["spacecraft_id"].values == ["sc-1"]

    assert Enum.map(fields["source_from"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T11:00:00.000000Z"
           ]

    assert Enum.map(fields["source_to"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:00:00.000000Z"
           ]

    assert Enum.map(fields["receipt_from"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:10:00.000000Z"
           ]

    assert Enum.map(fields["receipt_to"].values, &DateTime.to_iso8601/1) == [
             "2026-06-22T12:20:00.000000Z"
           ]

    assert fields["sample_count"].values == [42]
    assert fields["selected_sample_count"].values == [2]
    assert fields["projection_effect"].values == [:canonical_history_and_current_projection]
    assert fields["write_validity_state"].values == [:canonical]
    assert fields["record_current_values"].values == [true]
    assert fields["refresh_latest_value"].values == [true]
    assert fields["authority"].values == [:authoritative]
    assert fields["reason"].values == [:late_arrival_policy]
    assert fields["actor_id"].values == ["ops-1"]
    assert fields["actor_kind"].values == ["operator"]

    assert frame.meta.family == :telemetry_backfill
    assert frame.meta.product == :telemetry_backfill_lifecycle
    assert frame.meta.projection == :telemetry_backfill_lifecycle_events
    assert frame.meta.returned_events == 1
    assert frame.meta.cursor.backfill_lifecycle_event_id == "backfill-event-1"
    assert frame.meta.cursor.backfill_run_id == "backfill-run-1"

    assert_evidence_ref(
      frame.meta.evidence,
      :telemetry_backfill_lifecycle_event,
      "backfill-event-1"
    )

    assert_evidence_ref(
      frame.meta.evidence,
      :operational_event,
      "operational_event:telemetry_backfill_lifecycle_event:backfill-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :telemetry_backfill_lifecycle_event,
      "backfill-event-1"
    )

    assert_data_link(
      frame.meta.links,
      :operational_event,
      "operational_event:telemetry_backfill_lifecycle_event:backfill-event-1"
    )

    assert hd(frame.meta.links).context.data.data_source_id == "managed_events_projection"
    assert hd(frame.meta.links).context.data.source_binding_id == "default_flight_events"
    assert result.meta.supported_capability == [:telemetry_backfill_lifecycle]

    assert_receive {:telemetry_backfill_lifecycle_events, "org-1", "mission-1", opts}
    assert opts[:source_from] == from_time
    assert opts[:source_to] == to_time
    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "flight-questdb"
    assert opts[:binding_id] == "flight-telemetry"
    assert opts[:observable_id] == "HK.counter"
    assert opts[:authority] == :authoritative
    assert opts[:limit] == 10
    refute Keyword.has_key?(opts, :from_occurred_at)
    refute Keyword.has_key?(opts, :source_binding_id)
  end

  test "resolves telemetry backfill lifecycle events with replay run context" do
    parent = self()

    telemetry_backfill_lifecycle_events_fun = fn organization_id, mission_id, opts ->
      send(parent, {:telemetry_backfill_lifecycle_events, organization_id, mission_id, opts})

      [
        BackfillLifecycleEvent.new(%{
          backfill_lifecycle_event_id: "replay-backfill-event-1",
          backfill_run_id: "replay-backfill-run-1",
          organization_id: organization_id,
          mission_id: mission_id,
          realm: :replay,
          replay_run_id: "replay-run-1",
          data_source_id: "replay-questdb",
          binding_id: "replay-telemetry",
          observable_id: "HK.counter",
          event_type: :backfill_completed,
          source_from: ~U[2026-06-22 11:00:00Z],
          source_to: ~U[2026-06-22 12:00:00Z],
          authority: :authoritative,
          occurred_at: ~U[2026-06-22 12:21:00Z]
        })
      ]
    end

    result =
      Events.resolve(
        source_request(
          time_context: %{
            mode: :replay_run,
            axis: :occurred_at,
            replay_run_id: "replay-run-1"
          },
          data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
          sampling: %{
            mode: :event_history,
            products: [:telemetry_backfills],
            telemetry_backfill: %{
              data_source_id: "replay-questdb",
              source_binding_id: "replay-telemetry",
              observable_id: "HK.counter"
            }
          }
        ),
        telemetry_backfill_lifecycle_events_fun: telemetry_backfill_lifecycle_events_fun,
        telemetry_backfill_workflow_job_fun: fn _event -> nil end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    fields = Map.new(frame.fields, &{&1.name, &1})

    assert fields["realm"].values == [:replay]
    assert fields["replay_run_id"].values == ["replay-run-1"]
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert_receive {:telemetry_backfill_lifecycle_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:data_source_id] == "replay-questdb"
    assert opts[:binding_id] == "replay-telemetry"
  end

  defp assert_evidence_ref(evidence_refs, kind, id) do
    assert Enum.any?(evidence_refs, &match?(%EvidenceRef{kind: ^kind, id: ^id}, &1))
  end

  defp assert_data_link(links, target, target_id) do
    assert Enum.any?(links, &match?(%DataLink{target: ^target, target_id: ^target_id}, &1))
  end

  defp source_request(overrides) do
    attrs =
      %{
        request_id: "events-request-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        logical_source: :events,
        observables: ["HK.battery_voltage"],
        scope_context: %{
          organization_id: "org-1",
          mission_id: "mission-1",
          primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
        },
        time_context: %{axis: :occurred_at},
        data_context: %{realm: :flight},
        sampling: %{mode: :event_history},
        overlays: []
      }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "default_flight_events",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        logical_source: :events,
        data_source_id: "managed_events_projection",
        dataset: "mission_events"
      },
      data_source: %DataSource{
        data_source_id: "managed_events_projection",
        owner: :cadence,
        kind: :projection,
        isolation_level: :shared,
        adapter: Events,
        capabilities: %{
          contact_intervals?: true,
          mission_timeline?: true,
          source_health_transitions?: true,
          source_watermark_events?: true,
          source_capability_postures?: true,
          telemetry_backfill_lifecycle?: true,
          telemetry_revision_decisions?: true
        }
      },
      realm: :flight,
      dataset: "mission_events"
    }
  end

  defp replay_source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-events",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :replay,
        logical_source: :events,
        data_source_id: "replay-events-projection",
        dataset: "replay_mission_events"
      },
      data_source: %DataSource{
        data_source_id: "replay-events-projection",
        owner: :cadence,
        kind: :projection,
        isolation_level: :mission,
        adapter: Events,
        capabilities: %{
          contact_intervals?: true,
          mission_timeline?: true,
          source_health_transitions?: true,
          source_watermark_events?: true,
          source_capability_postures?: true,
          telemetry_backfill_lifecycle?: true,
          telemetry_revision_decisions?: true
        }
      },
      realm: :replay,
      dataset: "replay_mission_events"
    }
  end
end
