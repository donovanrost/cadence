defmodule Cadence.GovernanceTest do
  use Cadence.DataCase, async: true

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  @organization_id "org-alpha"

  test "persists and rehydrates a mission-scoped governed binding set" do
    persist_mission_scope(@organization_id, "mission-alpha")

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: @organization_id,
        mission_id: "mission-alpha",
        display_name: "SC-001"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-001",
        organization_id: @organization_id,
        mission_id: "mission-alpha",
        spacecraft_id: "sc-001",
        source_ref: "provider/path-a"
      })

    assert {:ok, _persisted_source_endpoint} =
             Cadence.persist_source_endpoint(@organization_id, source_endpoint)

    packet_definition =
      PacketDefinition.new(%{
        organization_id: @organization_id,
        mission_id: "mission-alpha",
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        version: 2,
        fields: [
          %{
            field_id: "temp",
            name: "temperature_raw",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            field_id: "heater",
            name: "heater_enabled",
            offset_bits: 16,
            size_bits: 1,
            data_type: :bool
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        organization_id: @organization_id,
        mission_id: "mission-alpha",
        binding_set_id: "default-telemetry",
        version: 4,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "hk-rule",
            handler_key: :definition_bound_telemetry,
            selector: %{
              scope: %{target_scope: :source_endpoint, source_endpoint_ref: "endpoint-sc-001"},
              match: %{packet_kind: :space_packet, apid: 42}
            },
            priority: 10,
            fanout_mode: :exclusive,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(@organization_id, binding_set)

    assert {:ok, fetched_binding_set} =
             Cadence.fetch_binding_set(@organization_id, "mission-alpha", "default-telemetry", 4)

    assert fetched_binding_set.binding_set_id == binding_set.binding_set_id
    assert fetched_binding_set.organization_id == @organization_id
    assert fetched_binding_set.mission_id == "mission-alpha"
    assert fetched_binding_set.version == 4

    [rule] = fetched_binding_set.rules
    assert rule.binding_rule_id == "hk-rule"
    assert rule.handler_key == :definition_bound_telemetry
    assert rule.selector.scope.target_scope == :source_endpoint
    assert rule.selector.scope.source_endpoint_ref == "endpoint-sc-001"
    assert rule.selector.match.packet_kind == :space_packet
    assert rule.selector.match.apid == 42
    assert rule.capability_config.config_type == :governed_packet_definition

    assert rule.capability_config.document == %{
             "mission_id" => "mission-alpha",
             "packet_definition_id" => "hk-packet",
             "version" => 2
           }

    packet_definition = rule.handler_configuration
    assert packet_definition.organization_id == @organization_id
    assert packet_definition.mission_id == "mission-alpha"
    assert packet_definition.packet_definition_id == "hk-packet"
    assert packet_definition.version == 2
    assert Enum.map(packet_definition.fields, & &1.name) == ["temperature_raw", "heater_enabled"]

    assert {:ok, latest_binding_set} =
             Cadence.fetch_latest_binding_set(
               @organization_id,
               "mission-alpha",
               "default-telemetry"
             )

    assert latest_binding_set.version == 4
  end

  test "persists and rehydrates a binding rule with a first-class capability config reference" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "temp",
            name: "temperature_raw",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    seed_binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "seed-packet-definition",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "seed-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^seed_binding_set} = Cadence.persist_binding_set(seed_binding_set)

    referenced_binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "capability-config-reference",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "referenced-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            capability_config: CapabilityConfig.reference_packet_definition(packet_definition)
          })
        ]
      })

    assert {:ok, ^referenced_binding_set} = Cadence.persist_binding_set(referenced_binding_set)

    assert {:ok, fetched_binding_set} =
             Cadence.fetch_binding_set("mission-alpha", "capability-config-reference", 1)

    [rule] = fetched_binding_set.rules
    assert rule.capability_config.config_type == :governed_packet_definition
    assert rule.handler_configuration.packet_definition_id == "hk-packet"
    assert rule.handler_configuration.version == 1
  end

  test "persists and rehydrates explicit governed capability instances" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "status-packet",
        packet_name: "STATUS",
        apid: 77,
        version: 1,
        fields: [
          %{
            field_id: "counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "explicit-capability-instances",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "status-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "status-rule",
            capability_instance_id: "status-instance",
            packet_kind: :space_packet,
            apid: 77
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)

    assert {:ok, fetched_binding_set} =
             Cadence.fetch_binding_set("mission-alpha", "explicit-capability-instances", 1)

    assert length(fetched_binding_set.capability_instances) == 1

    [capability_instance] = fetched_binding_set.capability_instances
    [rule] = fetched_binding_set.rules

    assert capability_instance.capability_instance_id == "status-instance"
    assert capability_instance.family_key == :definition_bound_telemetry
    assert capability_instance.capability_config.config_type == :governed_packet_definition
    assert rule.capability_instance_id == "status-instance"
    assert rule.handler_key == :definition_bound_telemetry
    assert rule.handler_configuration.packet_definition_id == "status-packet"
  end

  test "persists and rehydrates inline capability config documents for managed applications" do
    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "inline-managed-application",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: "packet-counter-instance",
            family_key: :packet_counter,
            target_scope: :mission,
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
            packet_kind: :space_packet,
            apid: 42,
            fanout_mode: :multi
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.persist_binding_set(binding_set)

    assert {:ok, fetched_binding_set} =
             Cadence.fetch_binding_set("mission-alpha", "inline-managed-application", 1)

    [capability_instance] = fetched_binding_set.capability_instances
    [rule] = fetched_binding_set.rules

    assert capability_instance.family_key == :packet_counter
    assert capability_instance.capability_config.config_type == :inline

    assert capability_instance.runtime_configuration == %{
             "metric_name" => "packet_window",
             "flush_interval_ms" => 25
           }

    assert rule.handler_key == :packet_counter

    assert rule.handler_configuration == %{
             "metric_name" => "packet_window",
             "flush_interval_ms" => 25
           }
  end

  test "rejects an unknown first-party capability family in a governed binding set" do
    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "invalid-family",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "invalid-rule",
            handler_key: :unknown_capability_family,
            packet_kind: :space_packet,
            apid: 42
          })
        ]
      })

    assert {:error, {:unknown_capability_family, :unknown_capability_family}} =
             Cadence.persist_binding_set(binding_set)
  end

  test "rejects a governed binding set whose input stage is incompatible with the capability family" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "temp",
            name: "temperature_raw",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "invalid-stage",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "invalid-stage-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :encapsulation_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:error,
            {:unsupported_capability_input_stage, :definition_bound_telemetry,
             :encapsulation_packet}} = Cadence.persist_binding_set(binding_set)
  end

  test "rejects a governed binding rule scoped to an unknown source endpoint" do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: "mission-alpha",
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "temp",
            name: "temperature_raw",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: "mission-alpha",
        binding_set_id: "invalid-endpoint-scope",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "invalid-endpoint-rule",
            handler_key: :definition_bound_telemetry,
            source_endpoint_ref: "missing-endpoint",
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:error,
            {:source_endpoint_not_found, "mission-alpha", "missing-endpoint",
             "invalid-endpoint-rule_instance"}} = Cadence.persist_binding_set(binding_set)
  end
end
