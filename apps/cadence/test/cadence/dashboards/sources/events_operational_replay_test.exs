defmodule Cadence.Dashboards.Sources.EventsOperationalReplayTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Dashboards.{Field, PlannedSourceRequest, ResolvedSourceBinding, SourceResult}

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Dashboards.Sources.Events
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Runtime.ManagedActionRequest

  test "replay mission timeline reads canonical operational events instead of live projection rows" do
    organization_id = "org-events-operational-replay"
    mission_id = "mission-events-operational-replay"
    replay_run_id = "replay-run-operational-events"
    other_replay_run_id = "other-replay-run-operational-events"
    event_time = ~U[2026-06-30 12:04:00Z]

    persist_mission_scope(organization_id, mission_id)

    assert {:ok, matching_event} =
             operational_event(
               organization_id,
               mission_id,
               "matching",
               event_time,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_replay_event} =
             operational_event(
               organization_id,
               mission_id,
               "other-replay",
               event_time,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    result =
      Events.resolve(
        source_request(organization_id, mission_id, replay_run_id),
        source_binding: replay_source_binding(organization_id, mission_id)
      )

    assert %SourceResult{frames: [timeline]} = result
    assert timeline.meta.projection == :operational_events
    assert timeline.meta.realm == :replay
    assert timeline.meta.replay_run_id == replay_run_id
    assert timeline.meta.returned_events == 1
    assert timeline.meta.cursor.mission_event_id == "mission_event:#{matching_event.event_id}"

    fields = fields_by_name(timeline.fields)

    assert fields["source_record_id"].values == [matching_event.event_id]
    assert fields["kind"].values == [:binding_set_activated]
    assert fields["title"].values == ["Binding Set Activated"]

    assert [
             %{kind: :mission_event, id: "mission_event:" <> _},
             %{
               kind: :operational_event,
               id: matching_event_id,
               confidence: :direct,
               source: :events
             }
           ] = timeline.meta.evidence

    assert matching_event_id == matching_event.event_id

    assert [%{target: :mission_event, context: %{data: %{replay_run_id: ^replay_run_id}}}] =
             timeline.meta.links
  end

  test "replay mission timeline projects managed runtime operational events" do
    organization_id = "org-events-managed-runtime-replay"
    mission_id = "mission-events-managed-runtime-replay"
    replay_run_id = "replay-run-managed-runtime-events"
    other_replay_run_id = "other-replay-run-managed-runtime-events"
    event_time = ~U[2026-06-30 12:06:00Z]

    persist_mission_scope(organization_id, mission_id)

    assert {:ok, matching_event} =
             managed_action_operational_event(
               mission_id,
               "matching",
               event_time,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_replay_event} =
             managed_action_operational_event(
               mission_id,
               "other-replay",
               event_time,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    result =
      Events.resolve(
        source_request(organization_id, mission_id, replay_run_id),
        source_binding: replay_source_binding(organization_id, mission_id)
      )

    assert %SourceResult{frames: [timeline]} = result
    assert timeline.meta.projection == :operational_events
    assert timeline.meta.replay_run_id == replay_run_id
    assert timeline.meta.returned_events == 1

    fields = fields_by_name(timeline.fields)

    assert fields["source_record_id"].values == [matching_event.event_id]
    assert fields["kind"].values == [:managed_action_requested]
    assert fields["title"].values == ["Managed Action Requested"]

    assert [
             %{kind: :mission_event, id: "mission_event:" <> _},
             %{
               kind: :operational_event,
               id: matching_event_id,
               confidence: :direct,
               source: :events
             }
           ] = timeline.meta.evidence

    assert matching_event_id == matching_event.event_id

    assert [%{target: :mission_event, context: %{data: %{replay_run_id: ^replay_run_id}}}] =
             timeline.meta.links
  end

  test "replay contact intervals read canonical operational events instead of live contact rows" do
    organization_id = "org-events-contact-operational-replay"
    mission_id = "mission-events-contact-operational-replay"
    replay_run_id = "replay-run-contact-operational-events"
    other_replay_run_id = "other-replay-run-contact-operational-events"
    starts_at = ~U[2026-06-30 12:02:00Z]
    ends_at = ~U[2026-06-30 12:08:00Z]

    persist_mission_scope(organization_id, mission_id)

    assert {:ok, matching_event} =
             contact_operational_event(
               organization_id,
               mission_id,
               "matching",
               starts_at,
               ends_at,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_replay_event} =
             contact_operational_event(
               organization_id,
               mission_id,
               "other-replay",
               starts_at,
               ends_at,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    result =
      Events.resolve(
        source_request(organization_id, mission_id, replay_run_id, [:contact_intervals]),
        source_binding: replay_source_binding(organization_id, mission_id)
      )

    assert %SourceResult{frames: [contacts]} = result
    assert contacts.meta.projection == :operational_events
    assert contacts.meta.realm == :replay
    assert contacts.meta.replay_run_id == replay_run_id
    assert contacts.meta.returned_intervals == 1

    fields = fields_by_name(contacts.fields)

    assert fields["contact_id"].values == ["contact-matching"]
    assert fields["kind"].values == [:scheduled_contact]
    assert fields["starts_at"].values == [starts_at]
    assert fields["ends_at"].values == [ends_at]
    assert fields["status"].values == ["scheduled"]
    assert fields["label"].values == ["Replay contact matching"]
    assert fields["source_event_id"].values == [matching_event.event_id]

    assert [
             %{kind: :scheduled_contact, id: "contact-matching", confidence: :direct},
             %{
               kind: :operational_interval,
               id: "effective_interval:contact:" <> _,
               confidence: :projected
             },
             %{kind: :operational_interval, id: matching_event_id, confidence: :direct}
           ] = contacts.meta.evidence

    assert matching_event_id == matching_event.event_id

    assert [
             %{
               target: :contact,
               target_id: "contact-matching",
               context: %{data: %{replay_run_id: ^replay_run_id}}
             },
             %{
               target: :operational_event,
               target_id: ^matching_event_id,
               context: %{data: %{replay_run_id: ^replay_run_id}}
             }
           ] = contacts.meta.links
  end

  defp operational_event(organization_id, mission_id, suffix, occurred_at, replay_run_id) do
    Event.new(%{
      event_id: "operational_event:binding_set_activation:#{suffix}",
      organization_id: organization_id,
      mission_id: mission_id,
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :runtime,
      kind: :binding_set_activated,
      severity: :info,
      actor: %{kind: :replay, id: replay_run_id},
      subject: %{kind: :binding_set, id: "binding-set-#{suffix}"},
      causality: %{
        correlation_id: "binding-set-#{suffix}",
        source_record_kind: :binding_set_activation,
        source_record_id: "activation-#{suffix}",
        replay_run_id: replay_run_id
      },
      payload: %{
        binding_set_id: "binding-set-#{suffix}",
        binding_set_version: 7,
        activation_id: "activation-#{suffix}"
      },
      metadata: %{"source" => "replay"}
    })
  end

  defp managed_action_operational_event(mission_id, suffix, occurred_at, replay_run_id) do
    %ManagedActionRequest{
      action_request_id: "managed-action-#{suffix}",
      mission_id: mission_id,
      capability_instance_id: "packet-counter-#{suffix}",
      family_key: :packet_counter,
      activation_id: "activation-#{suffix}",
      binding_set_id: "binding-set-#{suffix}",
      binding_set_version: 7,
      partition_affinity: :source_endpoint,
      partition_value: "endpoint-#{suffix}",
      action_kind: :schedule_timer,
      packet_id: "packet-#{suffix}",
      evidence_id: "evidence-#{suffix}",
      request_document: %{"timer_key" => "flush"},
      requested_at: occurred_at
    }
    |> Event.from_managed_action_request(replay_run_id)
  end

  defp contact_operational_event(
         organization_id,
         mission_id,
         suffix,
         starts_at,
         ends_at,
         replay_run_id
       ) do
    Event.new(%{
      event_id: "operational_event:scheduled_contact_interval:#{suffix}",
      organization_id: organization_id,
      mission_id: mission_id,
      occurred_at: starts_at,
      recorded_at: starts_at,
      effective_at: starts_at,
      category: :contact,
      kind: :scheduled_contact_interval,
      severity: :info,
      actor: %{kind: :replay, id: replay_run_id},
      subject: %{kind: :contact, id: "contact-#{suffix}"},
      scope: %{
        replay_run_id: replay_run_id,
        source_endpoint_ref: "endpoint-#{suffix}"
      },
      causality: %{
        correlation_id: "contact-#{suffix}",
        replay_run_id: replay_run_id
      },
      payload: %{
        scheduled_contact_id: "contact-#{suffix}",
        starts_at: starts_at,
        ends_at: ends_at,
        status: :scheduled,
        provider_contact_ref: "Replay contact #{suffix}",
        source_endpoint_refs: ["endpoint-#{suffix}"]
      },
      metadata: %{"source" => "replay"}
    })
  end

  defp source_request(
         organization_id,
         mission_id,
         replay_run_id,
         products \\ [:mission_timeline]
       ) do
    PlannedSourceRequest.new(%{
      request_id: "events-replay-operational-request",
      organization_id: organization_id,
      mission_id: mission_id,
      logical_source: :events,
      scope_context: %{
        organization_id: organization_id,
        mission_id: mission_id,
        primary: %{kind: "mission", mode: "one", ids: [mission_id]}
      },
      time_context: %{
        mode: :replay_run,
        axis: :occurred_at,
        from: ~U[2026-06-30 12:00:00Z],
        to: ~U[2026-06-30 12:10:00Z],
        replay_run_id: replay_run_id
      },
      data_context: %{
        realm: :replay,
        replay_run_id: replay_run_id,
        source_contexts: %{
          events: %{
            data_source_id: "replay-events-projection",
            source_binding_id: "replay-events",
            dataset: "replay_mission_events",
            replay_run_id: replay_run_id
          }
        }
      },
      sampling: %{mode: :event_history, products: products, limit: 25},
      overlays: []
    })
  end

  defp replay_source_binding(organization_id, mission_id) do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-events",
        organization_id: organization_id,
        mission_id: mission_id,
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
        capabilities: %{contact_intervals?: true, mission_timeline?: true}
      },
      realm: :replay,
      dataset: "replay_mission_events"
    }
  end

  defp fields_by_name(fields) do
    Map.new(fields, fn %Field{name: name} = field -> {name, field} end)
  end
end
