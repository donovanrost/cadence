defmodule Cadence.Comms.RoutingRuleStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  alias Cadence.Comms.{RoutingRule, Transport}
  alias Cadence.Spacecraft

  setup do
    organization_id =
      "org-routing-" <> Integer.to_string(System.unique_integer([:positive]))

    mission_id = "mission-routing-" <> Integer.to_string(System.unique_integer([:positive]))

    persist_mission_scope(organization_id, mission_id)

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission_id,
        display_name: "Alpha",
        scid: 42
      })

    assert {:ok, spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)

    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      })

    assert {:ok, transport} =
             TransportStore.persist_transport(organization_id, transport)

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft: spacecraft,
      transport: transport
    }
  end

  test "creates current state, records events, and materializes runtime compatibility", %{
    organization_id: organization_id,
    mission_id: mission_id,
    spacecraft: spacecraft,
    transport: transport
  } do
    rule =
      RoutingRule.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Alpha live telemetry via Lab TCP",
        purpose_label: "Live telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    assert {:ok, persisted} =
             RoutingRuleStore.create_routing_rule(organization_id, rule)

    assert persisted.organization_id == organization_id
    assert persisted.enabled?
    assert persisted.direction == :inbound
    assert is_binary(persisted.materialized_link_assignment_id)

    assert {:ok, assignment} =
             Cadence.fetch_link_assignment(
               organization_id,
               mission_id,
               persisted.materialized_link_assignment_id
             )

    assert assignment.spacecraft_id == spacecraft.spacecraft_id
    assert assignment.direction == :downlink
    assert assignment.selection_role == :selected
    assert assignment.metadata["materialized_from_routing_rule_id"] == persisted.routing_rule_id

    assert [listed] =
             RoutingRuleStore.list_routing_rules(organization_id, mission_id)

    assert listed.routing_rule_id == persisted.routing_rule_id

    assert [created, materialized] =
             RoutingRuleStore.list_routing_rule_events(
               organization_id,
               mission_id,
               persisted.routing_rule_id
             )

    assert created.event_type == :created
    assert materialized.event_type == :materialized
  end

  test "updates, disables, enables, and archives while recording events", %{
    organization_id: organization_id,
    mission_id: mission_id,
    spacecraft: spacecraft,
    transport: transport
  } do
    rule =
      RoutingRule.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Alpha AI&T telemetry",
        purpose_label: "AI&T telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :candidate
      })

    assert {:ok, persisted} =
             RoutingRuleStore.create_routing_rule(organization_id, rule)

    assert {:ok, updated} =
             RoutingRuleStore.update_routing_rule(
               organization_id,
               mission_id,
               persisted.routing_rule_id,
               %{purpose_label: "Live telemetry", role: :primary}
             )

    assert updated.purpose_label == "Live telemetry"
    assert updated.role == :primary

    assert {:ok, disabled} =
             RoutingRuleStore.set_routing_rule_enabled(
               organization_id,
               mission_id,
               persisted.routing_rule_id,
               false
             )

    refute disabled.enabled?

    assert {:ok, enabled} =
             RoutingRuleStore.set_routing_rule_enabled(
               organization_id,
               mission_id,
               persisted.routing_rule_id,
               true
             )

    assert enabled.enabled?

    assert {:ok, archived} =
             RoutingRuleStore.archive_routing_rule(
               organization_id,
               mission_id,
               persisted.routing_rule_id,
               %{"reason" => "test"}
             )

    assert archived.lifecycle_state == :archived
    refute archived.enabled?

    assert {:error, :routing_rule_not_found} =
             RoutingRuleStore.fetch_routing_rule(
               organization_id,
               mission_id,
               persisted.routing_rule_id
             )

    event_types =
      RoutingRuleStore.list_routing_rule_events(
        organization_id,
        mission_id,
        persisted.routing_rule_id
      )
      |> Enum.map(& &1.event_type)

    assert :created in event_types
    assert :updated in event_types
    assert :disabled in event_types
    assert :enabled in event_types
    assert :archived in event_types
  end

  test "rejects missing transport references", %{
    organization_id: organization_id,
    mission_id: mission_id,
    spacecraft: spacecraft
  } do
    rule =
      RoutingRule.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Missing transport",
        purpose_label: "Live telemetry",
        direction: :inbound,
        transport_id: "transport_missing",
        transport_version: 1,
        role: :primary
      })

    assert {:error, :transport_not_found} =
             RoutingRuleStore.create_routing_rule(organization_id, rule)
  end
end
