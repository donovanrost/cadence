defmodule Cadence.Reads.MissionEventsTest do
  use Cadence.DataCase, async: true

  alias Cadence.Activations.BindingSetActivationRow

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet
  }

  alias Cadence.Contacts.{CombinedDownlinkRecord, DownlinkDiagnostic}
  alias Cadence.MissionEvents.Entry
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Projections.MissionEvents
  alias Cadence.Projections.MissionEvents.Store.MissionEventRow
  alias Cadence.Reads.MissionEvents, as: MissionEventReads
  alias Cadence.Repo
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Telemetry.PacketDefinition

  @event_bus __MODULE__.EventBus

  setup do
    organization_id =
      "org-mission-events-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id =
      "mission-events-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "projects binding-set activations through the operational event envelope and rebuilds them",
       %{
         organization_id: organization_id,
         mission_id: mission_id
       } do
    activated_at = DateTime.from_unix!(1_700_060_050, :second)
    binding_set = telemetry_binding_set(mission_id, "runtime-activation-basis")

    assert {:ok, _persisted_binding_set} =
             Cadence.Governance.persist_binding_set(organization_id, binding_set)

    assert {:ok, activation} =
             record_binding_set_activation(
               organization_id,
               mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: activated_at,
               metadata: %{"change_request" => "CR-17"}
             )

    assert {:ok, 1} =
             activation
             |> MissionEvents.project()
             |> then(&MissionEvents.persist_entries(Repo, &1))

    [activation_event] =
      MissionEventReads.list_for_mission(
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
      Cadence.OperationalEvents.list_events(
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

    assert {:ok, _mission} = Cadence.Missions.fetch_mission(organization_id, mission_id)
    assert {:ok, 1} = MissionEvents.rebuild(mission_id)

    [rebuilt_event] =
      MissionEventReads.list_for_mission(
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
             MissionEventReads.list_for_mission(
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
             MissionEventReads.list_for_mission(
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
      MissionEventReads.list_for_mission(
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

  test "projects committed downlink combiner records into mission events", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    realized_contact_id = "transport-contact"
    beta_observed_at = DateTime.from_unix!(1_700_060_510, :second)
    alpha_observed_at = DateTime.from_unix!(1_700_060_515, :second)

    records = [
      CombinedDownlinkRecord.new(%{
        merged_record_id: "merged-beta",
        mission_id: mission_id,
        realized_contact_id: realized_contact_id,
        observation_key: "frame-001",
        source_endpoint_ref: "source-endpoint-alpha",
        selected_path_id: "downlink-path-beta",
        selected_observation_id: "observation-beta",
        payload: %{frame: 1, source: "beta"},
        selected_reason: :accepted,
        observed_at: beta_observed_at
      }),
      DownlinkDiagnostic.new(%{
        diagnostic_id: "diagnostic-beta",
        mission_id: mission_id,
        realized_contact_id: realized_contact_id,
        observation_key: "frame-001",
        path_id: "downlink-path-beta",
        selected_path_id: "downlink-path-beta",
        observation_id: "observation-beta",
        diagnostic_kind: :accepted,
        recorded_at: beta_observed_at
      }),
      CombinedDownlinkRecord.new(%{
        merged_record_id: "merged-alpha",
        mission_id: mission_id,
        realized_contact_id: realized_contact_id,
        observation_key: "frame-001",
        source_endpoint_ref: "source-endpoint-alpha",
        selected_path_id: "downlink-path-alpha",
        selected_observation_id: "observation-alpha",
        payload: %{frame: 1, source: "alpha"},
        selected_reason: :selected_path_preferred,
        observed_at: alpha_observed_at
      }),
      DownlinkDiagnostic.new(%{
        diagnostic_id: "diagnostic-alpha",
        mission_id: mission_id,
        realized_contact_id: realized_contact_id,
        observation_key: "frame-001",
        path_id: "downlink-path-alpha",
        selected_path_id: "downlink-path-alpha",
        observation_id: "observation-alpha",
        competing_observation_id: "observation-beta",
        diagnostic_kind: :selected_path_preferred,
        recorded_at: alpha_observed_at
      })
    ]

    assert {:ok, 4} =
             records
             |> MissionEvents.project_many()
             |> then(&MissionEvents.persist_entries(Repo, &1))

    transport_events =
      MissionEventReads.list_for_mission(organization_id, mission_id,
        category: :transport,
        limit: 10
      )

    assert Enum.map(transport_events, & &1.kind) == [
             :downlink_selection_changed,
             :downlink_record_combined,
             :downlink_observation_accepted,
             :downlink_record_combined
           ]

    [selection_event | _rest] = transport_events
    assert selection_event.realized_contact_id == realized_contact_id
    assert selection_event.path_id == "downlink-path-alpha"
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

  defp record_binding_set_activation(
         organization_id,
         mission_id,
         binding_set_id,
         version,
         opts
       ) do
    with {:ok, binding_set} <-
           Cadence.Governance.fetch_binding_set(
             organization_id,
             mission_id,
             binding_set_id,
             version
           ) do
      Cadence.Activations.record_binding_set_activation(
        organization_id,
        mission_id,
        binding_set_id,
        version,
        opts
        |> Keyword.put(
          :binding_set_content_sha256,
          MissionRuntimeSpec.content_sha256(binding_set)
        )
        |> Keyword.put_new(:event_bus, @event_bus)
      )
    end
  end
end
