defmodule Cadence.ContactsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Contacts.{
    Path,
    PathTemplate,
    ProviderProfile,
    RealizedContact,
    ScheduledContact,
    TransportBinding,
    TransportProfile
  }

  alias Cadence.OperationalEvents

  setup do
    organization_id =
      "org-contacts-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id = "mission-contacts-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "persists a scheduled contact and realizes it into an active runtime", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    starts_at = DateTime.from_unix!(1_700_040_000, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id(mission_id, "scheduled-contact-alpha"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 900, :second),
        provider_contact_ref: "provider-contact-001",
        paths: contact_paths(),
        metadata: %{operator_label: "alpha-pass"}
      })

    assert {:ok, persisted_scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert persisted_scheduled_contact.lifecycle_state == :scheduled

    assert {:ok, scheduled_event} =
             OperationalEvents.fetch_event(
               "operational_event:scheduled_contact_interval:#{scheduled_contact.scheduled_contact_id}"
             )

    assert scheduled_event.category == :contact
    assert scheduled_event.kind == :scheduled_contact_interval
    assert scheduled_event.causality.source_record_kind == :scheduled_contact
    assert scheduled_event.causality.source_record_id == scheduled_contact.scheduled_contact_id
    assert contact_event_value(scheduled_event, :status) == "scheduled"
    assert same_datetime?(contact_event_value(scheduled_event, :starts_at), starts_at)

    assert same_datetime?(
             contact_event_value(scheduled_event, :ends_at),
             scheduled_contact.ends_at
           )

    assert {:ok, fetched_scheduled_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id
             )

    assert fetched_scheduled_contact.provider_contact_ref == "provider-contact-001"

    assert [listed_scheduled_contact] =
             Cadence.Contacts.list_scheduled_contacts(organization_id, mission_id)

    assert listed_scheduled_contact.scheduled_contact_id == scheduled_contact.scheduled_contact_id

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :replay,
               initial_time: starts_at
             )

    assert realized_contact.realized_contact_id == "#{scheduled_contact.scheduled_contact_id}_run"
    assert realized_contact.scheduled_contact_id == scheduled_contact.scheduled_contact_id
    assert realized_contact.lifecycle_state == :active
    assert realized_contact.clock_mode == :replay

    assert {:ok, realized_scheduled_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id
             )

    assert realized_scheduled_contact.lifecycle_state == :realized
    assert realized_scheduled_contact.realized_contact_id == realized_contact.realized_contact_id

    assert {:ok, realized_scheduled_event} =
             OperationalEvents.fetch_event(
               "operational_event:scheduled_contact_interval:#{scheduled_contact.scheduled_contact_id}"
             )

    assert contact_event_value(realized_scheduled_event, :status) == "realized"

    assert contact_event_value(realized_scheduled_event, :realized_contact_id) ==
             realized_contact.realized_contact_id

    assert {:ok, fetched_realized_contact} =
             Cadence.Contacts.fetch_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert fetched_realized_contact.lifecycle_state == :active
    assert fetched_realized_contact.scheduled_contact_id == scheduled_contact.scheduled_contact_id

    assert {:ok, realized_event} =
             OperationalEvents.fetch_event(
               "operational_event:realized_contact_interval:#{realized_contact.realized_contact_id}"
             )

    assert realized_event.category == :contact
    assert realized_event.kind == :realized_contact_interval
    assert realized_event.causality.source_record_kind == :realized_contact
    assert realized_event.causality.source_record_id == realized_contact.realized_contact_id
    assert contact_event_value(realized_event, :status) == "active"

    assert contact_event_value(realized_event, :scheduled_contact_id) ==
             scheduled_contact.scheduled_contact_id

    assert [listed_realized_contact] =
             Cadence.Contacts.list_realized_contacts(organization_id, mission_id)

    assert listed_realized_contact.realized_contact_id == realized_contact.realized_contact_id

    assert {:ok, snapshot} =
             Cadence.realized_contact_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert snapshot.path_count == 2
    assert snapshot.clock_mode == :replay
    assert snapshot.downlink_combiner.selected_downlink_path_id == "downlink-path-alpha"
  end

  test "starts and stops a persisted realized contact by id", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: contact_id(mission_id, "manual-realized-contact"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths(),
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_040_500, :second),
        lifecycle_state: :defined,
        realized_at: DateTime.from_unix!(1_700_040_400, :second),
        metadata: %{created_by: "test"}
      })

    assert {:ok, persisted_realized_contact} =
             Cadence.Contacts.persist_realized_contact(organization_id, realized_contact)

    assert persisted_realized_contact.lifecycle_state == :defined

    assert {:ok, _pid} =
             Cadence.Contacts.start_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert {:ok, active_realized_contact} =
             Cadence.Contacts.fetch_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert active_realized_contact.lifecycle_state == :active
    assert active_realized_contact.metadata["started_at"]

    assert :ok =
             Cadence.Contacts.stop_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert {:ok, stopped_realized_contact} =
             Cadence.Contacts.fetch_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert stopped_realized_contact.lifecycle_state == :stopped
    assert stopped_realized_contact.metadata["stopped_at"]
  end

  test "realizes scheduled contacts from reusable path templates", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, %ProviderProfile{} = provider_profile} =
             Cadence.persist_provider_profile(
               organization_id,
               ProviderProfile.new(%{
                 provider_profile_id: "tcp-downlink-profile",
                 mission_id: mission_id,
                 adapter_key: :tcp_socket,
                 configuration: %{
                   "mode" => "listen",
                   "port" => 0,
                   "ingress_protocol_family" => "tm",
                   "frame_size" => 1115
                 }
               })
             )

    assert {:ok, %TransportProfile{} = transport_profile} =
             Cadence.persist_transport_profile(
               organization_id,
               TransportProfile.new(%{
                 transport_profile_id: "uplink-gateway-profile",
                 mission_id: mission_id,
                 family_key: :uplink_gateway,
                 target_scope: :path,
                 configuration: %{"transport_profile" => "tc"}
               })
             )

    assert {:ok, %PathTemplate{}} =
             Cadence.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "uplink-template-alpha",
                 mission_id: mission_id,
                 path_id: "uplink-path-alpha",
                 direction: :uplink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-alpha",
                 transport_profile_ids: [transport_profile.transport_profile_id]
               })
             )

    assert {:ok, %PathTemplate{}} =
             Cadence.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "downlink-template-alpha",
                 mission_id: mission_id,
                 path_id: "downlink-path-alpha",
                 direction: :downlink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-alpha",
                 provider_profile_ids: [provider_profile.provider_profile_id]
               })
             )

    starts_at = DateTime.from_unix!(1_700_040_250, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id(mission_id, "templated-contact-alpha"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        path_template_ids: ["uplink-template-alpha", "downlink-template-alpha"],
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 600, :second)
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :replay,
               initial_time: starts_at
             )

    assert [uplink_path, downlink_path] = realized_contact.paths
    assert uplink_path.path_id == "uplink-path-alpha"

    assert Enum.map(uplink_path.transport_bindings, & &1.transport_binding_id) == [
             "uplink-gateway-profile"
           ]

    assert downlink_path.path_id == "downlink-path-alpha"

    assert Enum.map(downlink_path.provider_bindings, & &1.provider_binding_id) == [
             "tcp-downlink-profile"
           ]

    assert realized_contact.metadata["path_template_ids"] == [
             "uplink-template-alpha",
             "downlink-template-alpha"
           ]

    assert {:ok, path_snapshot} =
             Cadence.path_runtime_snapshot(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               "downlink-path-alpha"
             )

    assert path_snapshot.provider_runtime_count == 1
    assert [%{provider_binding_id: "tcp-downlink-profile"}] = path_snapshot.provider_runtimes

    assert :ok =
             Cadence.Contacts.stop_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )
  end

  test "scheduled contacts pin template and profile versions at creation time", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert {:ok, %ProviderProfile{} = provider_profile_v1} =
             Cadence.persist_provider_profile(
               organization_id,
               ProviderProfile.new(%{
                 provider_profile_id: "tcp-downlink-versioned",
                 mission_id: mission_id,
                 adapter_key: :tcp_socket,
                 configuration: %{
                   "mode" => "listen",
                   "port" => 0,
                   "ingress_protocol_family" => "tm",
                   "frame_size" => 1115
                 }
               })
             )

    assert {:ok, %TransportProfile{} = transport_profile_v1} =
             Cadence.persist_transport_profile(
               organization_id,
               TransportProfile.new(%{
                 transport_profile_id: "uplink-gateway-versioned",
                 mission_id: mission_id,
                 family_key: :uplink_gateway,
                 target_scope: :path,
                 configuration: %{"transport_profile" => "tc"}
               })
             )

    assert {:ok, %PathTemplate{}} =
             Cadence.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "uplink-template-versioned",
                 mission_id: mission_id,
                 path_id: "uplink-path-versioned",
                 direction: :uplink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-alpha",
                 transport_profile_ids: [transport_profile_v1.transport_profile_id]
               })
             )

    assert {:ok, %PathTemplate{} = _path_template_v1} =
             Cadence.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "downlink-template-versioned",
                 mission_id: mission_id,
                 path_id: "downlink-path-versioned",
                 direction: :downlink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-alpha",
                 provider_profile_ids: [provider_profile_v1.provider_profile_id]
               })
             )

    starts_at = DateTime.from_unix!(1_700_042_500, :second)

    assert {:ok, %ScheduledContact{} = persisted_scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               organization_id,
               ScheduledContact.new(%{
                 scheduled_contact_id: contact_id(mission_id, "templated-contact-versioned"),
                 mission_id: mission_id,
                 source_endpoint_refs: ["source-endpoint-alpha"],
                 path_template_ids: ["uplink-template-versioned", "downlink-template-versioned"],
                 starts_at: starts_at,
                 ends_at: DateTime.add(starts_at, 600, :second)
               })
             )

    assert persisted_scheduled_contact.path_template_refs == [
             %{"path_template_id" => "uplink-template-versioned", "version" => 1},
             %{"path_template_id" => "downlink-template-versioned", "version" => 1}
           ]

    assert {:ok, %ProviderProfile{} = provider_profile_v2} =
             Cadence.version_provider_profile(
               organization_id,
               mission_id,
               "tcp-downlink-versioned",
               %{
                 configuration: %{
                   "mode" => "listen",
                   "port" => 4100,
                   "ingress_protocol_family" => "tm",
                   "frame_size" => 256
                 }
               }
             )

    assert provider_profile_v2.version == 2

    assert {:ok, %PathTemplate{} = path_template_v2} =
             Cadence.version_path_template(
               organization_id,
               mission_id,
               "downlink-template-versioned",
               %{provider_profile_ids: ["tcp-downlink-versioned"]}
             )

    assert path_template_v2.version == 2

    assert path_template_v2.provider_profile_refs == [
             %{"provider_profile_id" => "tcp-downlink-versioned", "version" => 2}
           ]

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               persisted_scheduled_contact.scheduled_contact_id,
               clock_mode: :replay,
               initial_time: starts_at
             )

    assert realized_contact.metadata["path_template_refs"] == [
             %{"path_template_id" => "uplink-template-versioned", "version" => 1},
             %{"path_template_id" => "downlink-template-versioned", "version" => 1}
           ]

    downlink_path = Enum.find(realized_contact.paths, &(&1.direction == :downlink))
    assert downlink_path
    assert downlink_path.metadata["path_template_version"] == 1
    assert [provider_binding] = downlink_path.provider_bindings
    assert provider_binding.configuration["port"] == 0
    assert provider_binding.metadata["provider_profile_version"] == 1

    assert :ok =
             Cadence.Contacts.stop_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )
  end

  test "canceling a scheduled contact before realization marks it canceled", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id(mission_id, "cancel-before-run"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: DateTime.from_unix!(1_700_041_000, :second),
        ends_at: DateTime.from_unix!(1_700_041_900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, canceled_scheduled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    assert canceled_scheduled_contact.lifecycle_state == :canceled
    assert canceled_scheduled_contact.metadata["canceled_at"]
    assert canceled_scheduled_contact.metadata["reason"] == "weather"

    [contact_action] =
      Cadence.list_contact_actions(
        organization_id,
        mission_id,
        scheduled_contact_id: scheduled_contact.scheduled_contact_id
      )

    assert contact_action.action_kind == :scheduled_contact_canceled
    assert contact_action.reason == "weather"
    assert contact_action.scheduled_contact_id == scheduled_contact.scheduled_contact_id
    assert is_nil(contact_action.realized_contact_id)

    assert [operational_event] =
             OperationalEvents.list_events(organization_id, mission_id,
               source_record_kind: :contact_action,
               source_record_id: contact_action.contact_action_id
             )

    assert operational_event.event_id ==
             "operational_event:contact_action:#{contact_action.contact_action_id}"

    assert operational_event.category == :contact
    assert operational_event.kind == :scheduled_contact_canceled

    assert operational_event.subject == %{
             kind: :contact,
             id: scheduled_contact.scheduled_contact_id
           }

    assert operational_event.causality.source_record_kind == :contact_action
    assert operational_event.causality.source_record_id == contact_action.contact_action_id
    assert contact_event_value(operational_event, :reason) == "weather"

    assert contact_event_value(operational_event, :scheduled_contact_id) ==
             scheduled_contact.scheduled_contact_id

    assert {:error, :scheduled_contact_canceled} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               []
             )
  end

  test "ending a linked realized contact early cancels the scheduled contact", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    starts_at = DateTime.from_unix!(1_700_042_000, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id(mission_id, "linked-contact-alpha"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :replay,
               initial_time: starts_at
             )

    assert {:ok, stopped_realized_contact} =
             Cadence.Contacts.end_realized_contact_early(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id,
               reason: "operator stop"
             )

    assert stopped_realized_contact.lifecycle_state == :stopped
    assert stopped_realized_contact.metadata["stopped_at"]
    assert stopped_realized_contact.metadata["reason"] == "operator stop"

    assert {:ok, canceled_scheduled_contact} =
             Cadence.Contacts.fetch_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id
             )

    assert canceled_scheduled_contact.lifecycle_state == :canceled
    assert canceled_scheduled_contact.metadata["canceled_at"]
    assert canceled_scheduled_contact.metadata["reason"] == "operator stop"

    [contact_action] =
      Cadence.list_contact_actions(
        organization_id,
        mission_id,
        realized_contact_id: realized_contact.realized_contact_id
      )

    assert contact_action.action_kind == :realized_contact_ended_early
    assert contact_action.reason == "operator stop"
    assert contact_action.scheduled_contact_id == scheduled_contact.scheduled_contact_id
    assert contact_action.realized_contact_id == realized_contact.realized_contact_id

    assert [operational_event] =
             OperationalEvents.list_events(organization_id, mission_id,
               source_record_kind: :contact_action,
               source_record_id: contact_action.contact_action_id
             )

    assert operational_event.event_id ==
             "operational_event:contact_action:#{contact_action.contact_action_id}"

    assert operational_event.category == :contact
    assert operational_event.kind == :realized_contact_ended_early

    assert operational_event.subject == %{
             kind: :contact,
             id: realized_contact.realized_contact_id
           }

    assert operational_event.causality.source_record_kind == :contact_action
    assert operational_event.causality.source_record_id == contact_action.contact_action_id
    assert contact_event_value(operational_event, :reason) == "operator stop"

    assert contact_event_value(operational_event, :scheduled_contact_id) ==
             scheduled_contact.scheduled_contact_id

    assert contact_event_value(operational_event, :realized_contact_id) ==
             realized_contact.realized_contact_id
  end

  test "canceling a realized scheduled contact stops the linked runtime", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    starts_at = DateTime.from_unix!(1_700_043_000, :second)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id(mission_id, "cancel-during-run"),
        mission_id: mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 900, :second),
        paths: contact_paths()
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, realized_contact} =
             Cadence.Contacts.realize_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               clock_mode: :replay,
               initial_time: starts_at
             )

    assert {:ok, canceled_scheduled_contact} =
             Cadence.Contacts.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "provider abort"
             )

    assert canceled_scheduled_contact.lifecycle_state == :canceled
    assert canceled_scheduled_contact.metadata["canceled_during_execution?"]
    assert canceled_scheduled_contact.metadata["reason"] == "provider abort"

    assert {:ok, stopped_realized_contact} =
             Cadence.Contacts.fetch_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    assert stopped_realized_contact.lifecycle_state == :stopped
    assert stopped_realized_contact.metadata["stopped_from_schedule_cancellation"]
    assert stopped_realized_contact.metadata["reason"] == "provider abort"

    [contact_action] =
      Cadence.list_contact_actions(
        organization_id,
        mission_id,
        scheduled_contact_id: scheduled_contact.scheduled_contact_id
      )

    assert contact_action.action_kind == :scheduled_contact_canceled
    assert contact_action.reason == "provider abort"
    assert contact_action.realized_contact_id == realized_contact.realized_contact_id
  end

  defp contact_paths do
    [
      Path.new(%{
        path_id: "uplink-path-alpha",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: "source-endpoint-alpha",
        transport_bindings: [
          TransportBinding.new(%{
            transport_binding_id: "uplink-heartbeat",
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
            transport_binding_id: "downlink-heartbeat",
            family_key: :heartbeat_monitor,
            configuration: %{"heartbeat_interval_ms" => 25}
          })
        ]
      })
    ]
  end

  defp contact_event_value(event, key) when is_atom(key) do
    Map.get(event.current, key) || Map.get(event.current, Atom.to_string(key))
  end

  defp contact_id(mission_id, suffix), do: "#{mission_id}-#{suffix}"

  defp same_datetime?(value, %DateTime{} = expected) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.compare(datetime, expected) == :eq
      _other -> false
    end
  end

  defp same_datetime?(%DateTime{} = value, %DateTime{} = expected) do
    DateTime.compare(value, expected) == :eq
  end

  defp same_datetime?(_value, %DateTime{}), do: false
end
