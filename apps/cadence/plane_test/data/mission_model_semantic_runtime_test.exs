defmodule Cadence.Runtime.MissionModelSemanticRuntimeTest do
  use ExUnit.Case, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}

  alias Cadence.Catalog.MissionModel.{
    Compiler,
    Declaration,
    Expression,
    Layer,
    Reference
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime.{MissionRuntimeSpec, ReplaySession}
  alias Cadence.Telemetry.PacketDefinition

  setup do
    if is_nil(Process.whereis(Cadence.Runtime.CapabilityRegistry)) do
      start_supervised!({Cadence.Runtime.CapabilityRegistry, []})
    end

    :ok
  end

  test "executes the same compiled model in isolated replay with stable identities" do
    mission_id = "semantic-replay"
    {raw_type, raw_parameter} = typed_parameter("/vehicle/pobc/parameters/raw_counter", 16)
    derived_parameter = parameter("/vehicle/pobc/parameters/doubled_counter")

    container =
      telemetry_container(
        "/vehicle/pobc/containers/pobc_hk",
        42,
        raw_parameter,
        16
      )

    algorithm =
      Declaration.new(%{
        kind: :algorithm,
        qualified_name: "/vehicle/pobc/algorithms/double_counter",
        references: [
          Reference.new(%{
            expected_kind: :parameter,
            source_ref: raw_parameter.qualified_name,
            role: :input
          })
        ],
        definition: %{
          implementation: %{kind: :expression},
          outputs: [
            %{
              parameter_id: derived_parameter.semantic_id,
              qualified_name: derived_parameter.qualified_name,
              expression:
                Expression.new(%{
                  node: {:*, {:parameter, raw_parameter.semantic_id}, {:literal, 2}},
                  result_type: :number
                })
            }
          ]
        }
      })

    monitoring =
      Declaration.new(%{
        kind: :monitoring_policy,
        qualified_name: "/vehicle/pobc/monitoring/doubled_counter",
        references: [
          Reference.new(%{
            expected_kind: :parameter,
            source_ref: derived_parameter.qualified_name,
            role: :parameter
          })
        ],
        definition: %{
          default_rules: [
            %{kind: :comparison, operator: :>, value: 10, severity: :critical}
          ]
        }
      })

    layer =
      Layer.new(%{
        mission_id: mission_id,
        name: "semantic replay model",
        declarations:
          Enum.map(
            ["/", "/vehicle", "/vehicle/pobc"],
            &%{kind: :space_system, qualified_name: &1}
          ) ++ [raw_type, raw_parameter, container, derived_parameter, algorithm, monitoring]
      })

    assert {:ok, compilation} = Compiler.compile([layer])
    assert Enum.all?(compilation.plans, fn {_target, plan} -> plan.status == :ready end)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: container.semantic_id,
        packet_name: "POBC_HK",
        apid: 42,
        fields: [
          %{
            field_id: "raw_counter",
            name: "raw_counter",
            parameter_id: raw_parameter.semantic_id,
            qualified_name: raw_parameter.qualified_name,
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "semantic-runtime-binding",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "pobc-hk-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    revision = compilation.revision

    assert {:ok, runtime_spec} =
             MissionRuntimeSpec.new(%{
               activation_id: "semantic-runtime-activation",
               mission_id: mission_id,
               generation: 1,
               binding_set_id: binding_set.binding_set_id,
               binding_set_version: binding_set.version,
               binding_set: binding_set,
               mission_model_revision_id: revision.revision_id,
               mission_model_content_sha256: revision.content_sha256,
               runtime_plans: compilation.plans,
               activated_at: ~U[2026-08-11 12:00:00Z]
             })

    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-semantic-replay",
        mission_id: mission_id,
        source_ref: "replay/pobc",
        source_time: ~U[2026-08-11 12:00:01Z],
        receipt_time: ~U[2026-08-11 12:00:02Z],
        raw: build_space_packet(42, 7, <<0, 6>>)
      })

    assert {:ok, first} = ReplaySession.process([evidence], runtime_spec)
    assert {:ok, second} = ReplaySession.process([evidence], runtime_spec)

    [first_result] = first.processing_results
    [second_result] = second.processing_results

    assert Enum.map(first_result.outputs, &{&1.semantic_id, &1.engineering_value}) == [
             {raw_parameter.semantic_id, 6},
             {derived_parameter.semantic_id, 12}
           ]

    assert [%{evaluated_state: :critical, effective_state: :critical}] =
             first_result.semantic_result.monitoring_results

    assert first_result.packet_records == second_result.packet_records
    assert first_result.outputs == second_result.outputs
    assert first_result.semantic_result == second_result.semantic_result
  end

  test "pins base telemetry samples to the active Mission Model even without semantic work" do
    mission_id = "semantic-basis-only"
    {counter_type, counter_parameter} = typed_parameter("/vehicle/parameters/counter", 8)
    container = telemetry_container("/vehicle/containers/legacy_hk", 7, counter_parameter, 8)

    layer =
      Layer.new(%{
        mission_id: mission_id,
        name: "semantic basis only",
        declarations: [
          %{kind: :space_system, qualified_name: "/"},
          %{kind: :space_system, qualified_name: "/vehicle"},
          counter_type,
          counter_parameter,
          container
        ]
      })

    assert {:ok, compilation} = Compiler.compile([layer])
    assert Enum.all?(compilation.plans, fn {_target, plan} -> plan.status == :ready end)

    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: container.semantic_id,
        packet_name: "LEGACY_HK",
        apid: 7,
        fields: [%{field_id: "counter", name: "counter", size_bits: 8}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "semantic-basis-binding",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "legacy-hk-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 7,
            handler_configuration: packet_definition
          })
        ]
      })

    revision = compilation.revision

    assert {:ok, runtime_spec} =
             MissionRuntimeSpec.new(%{
               activation_id: "semantic-basis-activation",
               mission_id: mission_id,
               generation: 1,
               binding_set_id: binding_set.binding_set_id,
               binding_set_version: binding_set.version,
               binding_set: binding_set,
               mission_model_revision_id: revision.revision_id,
               mission_model_content_sha256: revision.content_sha256,
               runtime_plans: compilation.plans,
               activated_at: ~U[2026-08-12 12:00:00Z]
             })

    evidence =
      RawEvidence.new(%{
        evidence_id: "evidence-semantic-basis",
        mission_id: mission_id,
        source_ref: "replay/legacy",
        source_time: ~U[2026-08-12 12:00:01Z],
        receipt_time: ~U[2026-08-12 12:00:02Z],
        raw: build_space_packet(7, 1, <<9>>)
      })

    assert {:ok, replay} = ReplaySession.process([evidence], runtime_spec)
    assert [%{outputs: [sample]}] = replay.processing_results

    assert sample.engineering_value == 9
    assert sample.mission_model_revision_id == revision.revision_id
    assert sample.runtime_plan_id == compilation.plans.telemetry.plan_id

    assert sample.provenance.mission_model_revision_id == revision.revision_id
    assert sample.provenance.runtime_plan_id == compilation.plans.telemetry.plan_id
  end

  defp parameter(qualified_name) do
    Declaration.new(%{kind: :parameter, qualified_name: qualified_name})
  end

  defp typed_parameter(qualified_name, size_bits) do
    type =
      Declaration.new(%{
        kind: :parameter_type,
        qualified_name: qualified_name <> "_type",
        definition: %{
          base_type: :integer,
          encoding: %{size_bits: size_bits, signed: false, byte_order: :big_endian}
        }
      })

    parameter =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: qualified_name,
        references: [
          Reference.new(%{
            expected_kind: :parameter_type,
            source_ref: type.qualified_name,
            role: :type
          })
        ]
      })

    {type, parameter}
  end

  defp telemetry_container(qualified_name, apid, parameter, size_bits) do
    Declaration.new(%{
      kind: :container,
      qualified_name: qualified_name,
      definition: %{
        apid: apid,
        entries: [
          %{parameter_ref: parameter.qualified_name, bit_offset: 0, size_bits: size_bits}
        ]
      },
      references: [
        Reference.new(%{
          expected_kind: :parameter,
          source_ref: parameter.qualified_name,
          role: :entry
        })
      ]
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
end
