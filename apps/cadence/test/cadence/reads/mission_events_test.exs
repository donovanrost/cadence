defmodule Cadence.Reads.MissionEventsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.Schemas.{BindingSetActivationRow, MissionEventRow}
  alias Cadence.Projections.MissionEvents
  alias Cadence.Repo
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  setup do
    organization_id =
      "org-mission-events-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "mission-events-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    on_exit(fn ->
      Cadence.stop_realized_contact(organization_id, mission_id, "managed-runtime-contact")
      Cadence.stop_realized_contact(organization_id, mission_id, "transport-contact")
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
             Cadence.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_scheduled_contact} =
             Cadence.cancel_scheduled_contact(
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
             Cadence.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id
    assert {:ok, ^limit_definition} = Cadence.persist_limit_definition(limit_definition)

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(mission_id, 42, 1, 30, 1_700_060_100),
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, limit_run} = Cadence.evaluate_telemetry_limits(mission_id)
    assert limit_run.status == :completed

    mission_events = Cadence.list_mission_events(organization_id, mission_id, limit: 10)

    assert MapSet.new(Enum.map(mission_events, & &1.kind)) ==
             MapSet.new([:limit_violation, :scheduled_contact_canceled])

    limit_event = Enum.find(mission_events, &(&1.kind == :limit_violation))
    contact_event = Enum.find(mission_events, &(&1.kind == :scheduled_contact_canceled))

    assert limit_event.category == :health
    assert limit_event.severity == :warning
    assert limit_event.subject_kind == :telemetry_point
    assert limit_event.subject_id == "HK.counter"

    assert contact_event.category == :operations
    assert contact_event.summary == "weather"
    assert contact_event.scheduled_contact_id == scheduled_contact.scheduled_contact_id

    assert mission_event_count(mission_id) == 2
    assert {2, _rows} = delete_mission_events(mission_id)

    assert {:ok, 2} = Cadence.rebuild_mission_events(organization_id, mission_id)

    rebuilt_events = Cadence.list_mission_events(organization_id, mission_id, limit: 10)

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
             Cadence.persist_binding_set(organization_id, binding_set)

    assert persisted_binding_set.binding_set_id == binding_set.binding_set_id
    assert persisted_binding_set.organization_id == organization_id

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
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
      Cadence.list_mission_events(
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

  test "projects binding-set activations through the operational event envelope and rebuilds them",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    activated_at = DateTime.from_unix!(1_700_060_050, :second)
    binding_set = telemetry_binding_set(mission_id, "runtime-activation-basis")

    assert {:ok, _persisted_binding_set} =
             Cadence.persist_binding_set(organization_id, binding_set)

    assert {:ok, activation} =
             Cadence.activate_binding_set(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: activated_at,
               metadata: %{"change_request" => "CR-17"}
             )

    [activation_event] =
      Cadence.list_mission_events(
        organization_id,
        mission_id,
        category: :runtime,
        kind: :binding_set_activated,
        limit: 10
      )

    assert DateTime.compare(activation_event.occurred_at, activated_at) == :eq
    assert activation_event.kind == :binding_set_activated
    assert activation_event.status == "active"
    assert activation_event.subject_kind == :binding_set
    assert activation_event.subject_id == binding_set.binding_set_id
    assert activation_event.correlation_key == binding_set.binding_set_id
    assert activation_event.activation_id == activation.activation_id
    assert activation_event.source_record_kind == :operational_event

    assert activation_event.source_record_id ==
             "operational_event:binding_set_activation:#{activation.activation_id}"

    assert activation_event.metadata["operational_event_id"] ==
             activation_event.source_record_id

    assert activation_event.metadata["source_record_kind"] == "binding_set_activation"
    assert activation_event.metadata["source_record_id"] == activation.activation_id
    assert activation_event.metadata["binding_set_id"] == binding_set.binding_set_id
    assert activation_event.metadata["binding_set_version"] == binding_set.version
    assert activation_event.metadata["change_request"] == "CR-17"

    [operational_event] =
      Cadence.list_operational_events(
        organization_id,
        mission_id,
        kind: :binding_set_activated,
        source_record_kind: :binding_set_activation,
        source_record_id: activation.activation_id
      )

    assert operational_event.event_id == activation_event.source_record_id
    assert operational_event.subject == %{kind: :binding_set, id: binding_set.binding_set_id}

    assert mission_event_count(mission_id) == 1
    assert {1, _rows} = delete_mission_events(mission_id)
    assert {1, _rows} = delete_binding_set_activations(mission_id)

    assert {:ok, 1} = Cadence.rebuild_mission_events(organization_id, mission_id)

    [rebuilt_event] =
      Cadence.list_mission_events(
        organization_id,
        mission_id,
        category: :runtime,
        kind: :binding_set_activated,
        limit: 10
      )

    assert rebuilt_event.source_record_id == activation_event.source_record_id
    assert rebuilt_event.activation_id == activation.activation_id
    assert rebuilt_event.metadata["change_request"] == "CR-17"
  end

  test "projects canonical operational event scope into mission timeline filters", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    occurred_at = DateTime.from_unix!(1_700_060_075, :second)

    event =
      Event.new(%{
        event_id: "operational_event:binding_set_activation:scoped-projection",
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: occurred_at,
        recorded_at: occurred_at,
        effective_at: occurred_at,
        category: :runtime,
        kind: :binding_set_activated,
        severity: :info,
        actor: %{kind: :system, id: "projection-test"},
        subject: %{kind: :binding_set, id: "scoped-binding-set"},
        scope: %{
          spacecraft_id: "sc-alpha",
          source_endpoint_ref: "endpoint-alpha"
        },
        causality: %{
          correlation_id: "scoped-binding-set",
          source_record_kind: :binding_set_activation,
          source_record_id: "activation-scoped"
        },
        payload: %{
          binding_set_id: "scoped-binding-set",
          binding_set_version: 1,
          activation_id: "activation-scoped"
        }
      })

    assert {:ok, persisted_event} = OperationalEvents.persist_event(event)

    assert {:ok, 1} =
             MissionEvents.persist_entries(Repo, MissionEvents.project_many([persisted_event]))

    assert [scoped_event] =
             Cadence.list_mission_events(
               organization_id,
               mission_id,
               category: :runtime,
               kind: :binding_set_activated,
               spacecraft_id: "sc-alpha",
               source_endpoint_ref: "endpoint-alpha"
             )

    assert scoped_event.source_record_kind == :operational_event
    assert scoped_event.source_record_id == persisted_event.event_id
    assert scoped_event.spacecraft_id == "sc-alpha"
    assert scoped_event.source_endpoint_ref == "endpoint-alpha"

    assert [] =
             Cadence.list_mission_events(
               organization_id,
               mission_id,
               category: :runtime,
               kind: :binding_set_activated,
               spacecraft_id: "sc-beta",
               source_endpoint_ref: "endpoint-alpha"
             )
  end

  test "lists mission events inside an occurred-at range in ascending order", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    before_window = DateTime.from_unix!(1_700_060_000, :second)
    first_in_window = DateTime.from_unix!(1_700_060_100, :second)
    second_in_window = DateTime.from_unix!(1_700_060_200, :second)
    after_window = DateTime.from_unix!(1_700_060_300, :second)

    for {event_id, occurred_at} <- [
          {"before-window", before_window},
          {"first-window", first_in_window},
          {"second-window", second_in_window},
          {"after-window", after_window}
        ] do
      event =
        Entry.new(%{
          mission_event_id: event_id,
          mission_id: mission_id,
          occurred_at: occurred_at,
          category: :health,
          kind: :limit_violation,
          severity: :warning,
          title: event_id,
          source_record_kind: :limit_event,
          source_record_id: event_id,
          subject_kind: :telemetry_point,
          subject_id: "HK.counter"
        })

      assert {:ok, _row} =
               event
               |> MissionEventRow.changeset()
               |> Repo.insert()
    end

    events =
      Cadence.list_mission_events(
        organization_id,
        mission_id,
        from_occurred_at: first_in_window,
        to_occurred_at: after_window,
        order: :asc,
        limit: 10
      )

    assert Enum.map(events, & &1.mission_event_id) == ["first-window", "second-window"]

    assert Enum.map(events, &DateTime.truncate(&1.occurred_at, :second)) == [
             first_in_window,
             second_in_window
           ]
  end

  test "projects downlink combiner outputs into mission events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: "transport-contact",
        mission_id: mission_id,
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_060_500, :second),
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: [
          Path.new(%{
            path_id: "uplink-path-alpha",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-heartbeat-alpha",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "downlink-path-alpha",
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat-alpha",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          }),
          Path.new(%{
            path_id: "downlink-path-beta",
            direction: :downlink,
            selection_role: :contributing,
            source_endpoint_ref: "source-endpoint-alpha",
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "downlink-heartbeat-beta",
                family_key: :heartbeat_monitor,
                configuration: %{"heartbeat_interval_ms" => 25}
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.persist_realized_contact(organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.start_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert {:ok, _first_outputs} =
             Cadence.handle_path_transport_event(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-beta",
               "downlink-heartbeat-beta",
               %{
                 kind: :downlink_observation,
                 observation_key: "frame-001",
                 payload: %{frame: 1, source: "beta"},
                 quality_score: 10
               },
               occurred_at: DateTime.from_unix!(1_700_060_510, :second),
               call_timeout: :infinity
             )

    assert {:ok, _second_outputs} =
             Cadence.handle_path_transport_event(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha",
               "downlink-heartbeat-alpha",
               %{
                 kind: :downlink_observation,
                 observation_key: "frame-001",
                 payload: %{frame: 1, source: "alpha"},
                 quality_score: 5
               },
               occurred_at: DateTime.from_unix!(1_700_060_515, :second),
               call_timeout: :infinity
             )

    transport_events =
      Cadence.list_mission_events(organization_id, mission_id, category: :transport, limit: 10)

    assert Enum.map(transport_events, & &1.kind) == [
             :downlink_selection_changed,
             :downlink_record_combined,
             :downlink_observation_accepted,
             :downlink_record_combined
           ]

    [selection_event | _rest] = transport_events
    assert selection_event.realized_contact_id == realized_contact.realized_contact_id
    assert selection_event.path_id == "downlink-path-alpha"
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
             Cadence.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_scheduled_contact} =
             Cadence.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "antenna maintenance"
             )

    assert mission_event_count(mission_id) == 1
    assert {1, _rows} = delete_mission_events(mission_id)

    assert {:ok, rebuild_run} = Cadence.start_rebuild_mission_events(organization_id, mission_id)
    assert rebuild_run.status == :running

    assert {:ok, queued_job} = Cadence.fetch_mission_event_rebuild_job(rebuild_run.rebuild_run_id)
    assert queued_job.status == :queued
    assert queued_job.job_type == :mission_event_rebuild

    [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_mission_event_rebuild_run(rebuild_run.rebuild_run_id)

    assert completed_run.status == :completed
    assert completed_run.rebuilt_event_count == 1

    [rebuilt_event] = Cadence.list_mission_events(organization_id, mission_id, [])
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

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        source_ref: "provider/station-a",
        protocol_context: %{scid: 1001}
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    assert persisted_source_endpoint.source_endpoint_id == source_endpoint.source_endpoint_id
    assert persisted_source_endpoint.organization_id == organization_id
    persisted_source_endpoint
  end

  defp raw_evidence_fixture(mission_id, apid, sequence_count, counter_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: mission_id,
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(apid, sequence_count, <<counter_value::16>>)
    })
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

  defp delete_binding_set_activations(mission_id) do
    BindingSetActivationRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.delete_all()
  end
end
