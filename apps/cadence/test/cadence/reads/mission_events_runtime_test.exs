defmodule Cadence.Reads.MissionEventsRuntimeTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Contacts.{Path, ScheduledContact}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Jobs
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Projections.MissionEvents
  alias Cadence.Projections.MissionEvents.Store.MissionEventRow
  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias Cadence.Repo
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  setup do
    organization_id =
      "org-mission-events-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "mission-events-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    on_exit(fn ->
      Cadence.Contacts.stop_realized_contact(
        organization_id,
        mission_id,
        "managed-runtime-contact"
      )

      Runtime.stop_mission(mission_id)
    end)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "projects contact actions and limit violations into mission events and can rebuild them",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "mission-event-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.from_unix!(1_700_060_000, :second),
        ends_at: DateTime.from_unix!(1_700_060_900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_scheduled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    binding_set = telemetry_binding_set(mission_id, "limits-basis")

    limit_definition =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "hk-counter-limits",
        point_id: "HK.counter",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 20}
      })

    assert {:ok, persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id
    assert {:ok, ^limit_definition} = Cadence.Limits.persist_limit_definition(limit_definition)

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(mission_id, 42, 1, 30, 1_700_060_100),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, limit_run} = Cadence.Limits.evaluate(mission_id)
    assert limit_run.status == :completed

    mission_events = MissionEventReads.list_for_mission(organization_id, mission_id, limit: 10)

    assert MapSet.new(Enum.map(mission_events, & &1.kind)) ==
             MapSet.new([:limit_violation, :scheduled_contact_canceled])

    limit_event = Enum.find(mission_events, &(&1.kind == :limit_violation))
    contact_event = Enum.find(mission_events, &(&1.kind == :scheduled_contact_canceled))

    assert {:ok, ^limit_event} =
             MissionEventReads.fetch_for_mission(
               organization_id,
               mission_id,
               limit_event.mission_event_id
             )

    assert {:error, :mission_event_not_found} =
             MissionEventReads.fetch_for_mission(
               "other-organization",
               mission_id,
               limit_event.mission_event_id
             )

    assert limit_event.category == :health
    assert limit_event.severity == :warning
    assert limit_event.subject_kind == :telemetry_point
    assert limit_event.subject_id == "HK.counter"

    assert contact_event.category == :operations
    assert contact_event.summary == "weather"
    assert contact_event.scheduled_contact_id == scheduled_contact.scheduled_contact_id

    assert mission_event_count(mission_id) == 2
    assert {2, _rows} = delete_mission_events(mission_id)

    assert {:ok, _mission} = Cadence.Missions.fetch_mission(organization_id, mission_id)
    assert {:ok, 2} = MissionEvents.rebuild(mission_id)

    rebuilt_events = MissionEventReads.list_for_mission(organization_id, mission_id, limit: 10)

    assert MapSet.new(Enum.map(rebuilt_events, & &1.kind)) ==
             MapSet.new([:limit_violation, :scheduled_contact_canceled])
  end

  test "projects managed action requests into mission events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    source_endpoint = persist_source_endpoint(organization_id, mission_id)
    binding_set = packet_counter_binding_set(mission_id, source_endpoint.source_endpoint_id)

    assert {:ok, persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, _result} = Cadence.process_telemetry_ingress(raw_evidence)

    [runtime_event] =
      MissionEventReads.list_for_mission(
        organization_id,
        mission_id,
        category: :runtime,
        capability_instance_id: "packet-counter-instance"
      )

    assert runtime_event.kind == :managed_action_requested
    assert runtime_event.status == "schedule_timer"
    assert runtime_event.capability_instance_id == "packet-counter-instance"
    assert runtime_event.subject_kind == :capability_instance
  end

  test "rebuilds mission events through the durable job queue", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "mission-event-job-contact",
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.from_unix!(1_700_061_000, :second),
        ends_at: DateTime.from_unix!(1_700_061_900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_scheduled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "antenna maintenance"
             )

    assert mission_event_count(mission_id) == 1
    assert {1, _rows} = delete_mission_events(mission_id)

    assert {:ok, _mission} = Cadence.Missions.fetch_mission(organization_id, mission_id)
    assert {:ok, rebuild_run} = MissionEvents.start_rebuild(mission_id)
    assert rebuild_run.status == :running

    assert {:ok, queued_job} =
             Jobs.fetch_job_for_run(:mission_event_rebuild, rebuild_run.rebuild_run_id)

    assert queued_job.status == :queued
    assert queued_job.job_type == :mission_event_rebuild

    [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id

    assert {:ok, completed_job} = JobRunner.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} = MissionEvents.fetch_run(rebuild_run.rebuild_run_id)

    assert completed_run.status == :completed
    assert completed_run.rebuilt_event_count == 1

    [rebuilt_event] = MissionEventReads.list_for_mission(organization_id, mission_id, [])
    assert rebuilt_event.kind == :scheduled_contact_canceled
    assert rebuilt_event.summary == "antenna maintenance"
  end

  defp telemetry_binding_set(mission_id, binding_set_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: binding_set_id <> "-packet",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: binding_set_id,
      version: 1,
      rules: [
        BindingRule.new(%{
          handler_key: :definition_bound_telemetry,
          selector: %{match: %{packet_kind: :space_packet, apid: 42}},
          handler_configuration: packet_definition
        })
      ]
    })
  end

  defp raw_evidence_fixture(mission_id, apid, sequence_count, counter_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: mission_id,
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(apid, sequence_count, <<counter_value::16>>)
    })
  end

  defp contact_paths do
    [
      Path.new(%{
        path_id: "downlink-path-alpha",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: "source-endpoint-alpha",
        transport_bindings: []
      })
    ]
  end

  defp mission_event_count(mission_id) do
    MissionEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.aggregate(:count, :mission_event_id)
  end

  defp delete_mission_events(mission_id) do
    MissionEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.delete_all()
  end

  defp packet_counter_binding_set(mission_id, source_endpoint_ref) do
    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: "managed-runtime-basis",
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "packet-counter-instance",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => "packet_window",
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "packet-counter-rule",
          capability_instance_id: "packet-counter-instance",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: 42}
          },
          fanout_mode: :multi,
          priority: 10
        })
      ]
    })
  end

  defp persist_source_endpoint(organization_id, mission_id) do
    spacecraft_id = "#{mission_id}-spacecraft-alpha"
    source_endpoint_id = "#{mission_id}-source-endpoint-alpha"

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: spacecraft_id,
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "Spacecraft Alpha"
      })

    assert {:ok, _persisted_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        source_ref: "provider/station-a",
        protocol_context: %{scid: 1001}
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(organization_id, source_endpoint)

    assert persisted_source_endpoint.source_endpoint_id == source_endpoint.source_endpoint_id
    assert persisted_source_endpoint.organization_id == organization_id
    persisted_source_endpoint
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
