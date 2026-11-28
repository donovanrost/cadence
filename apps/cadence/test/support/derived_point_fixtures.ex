defmodule Cadence.DerivedPointFixtures do
  @moduledoc """
  A mission whose active revision derives a parameter (#451 T4b), through the real compiler: a raw
  parameter in a telemetry container, and an algorithm whose output is a real `:parameter`
  declaration with a float type and a unit (`V`), as mission-model's `derived_parameter` emits one.
  The revision is persisted by `MissionModels.compile_layers/2` and made the mission's ACTIVE one
  by an activation of a binding set whose packet definition carries the raw field (no runtime is
  applied). For DataCase tests of the reads that ask the operator point catalog.
  """

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Catalog.MissionModel.{Declaration, Expression, Layer, Reference}
  alias Cadence.MissionModels
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Telemetry.PacketDefinition

  @raw "/vehicle/parameters/raw_counter"
  @derived "/vehicle/derived/bus_volts"

  @doc "The derived output's qualified name."
  @spec derived_name() :: binary()
  def derived_name, do: @derived

  @doc """
  Compiles, persists and activates the model in `mission_id` (already in scope). Returns the
  revision id, the derived parameter's semantic id and the system that owns its algorithm.
  """
  @spec activate!(binary(), binary(), keyword()) :: %{
          revision_id: binary(),
          derived_id: binary(),
          raw_id: binary(),
          space_system_id: binary()
        }
  def activate!(organization_id, mission_id, opts \\ []) do
    model = compile!(organization_id, mission_id, opts)
    activate_binding_set!(organization_id, mission_id, model.raw, model.revision_id)
    Map.delete(model, :raw)
  end

  @doc """
  Compiles and persists a revision that derives `opts[:derived_name]` (default the standard one),
  without activating it: the second composition's revision of a fleet test. Returns what
  `activate!/3` does, plus the raw `Declaration`.
  """
  @spec compile!(binary(), binary(), keyword()) :: map()
  def compile!(organization_id, mission_id, opts \\ []) do
    derived_name = Keyword.get(opts, :derived_name, @derived)
    {raw_type, raw} = typed_parameter(@raw)

    unit = %{kind: :unit, qualified_name: "/vehicle/units/volt", definition: %{symbol: "V"}}

    derived_type =
      Declaration.new(%{
        kind: :parameter_type,
        qualified_name: "/vehicle/types/volts",
        definition: %{base_type: :float}
      })

    derived =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: derived_name,
        references: [
          reference(:parameter_type, derived_type.qualified_name, :type),
          reference(:unit, unit.qualified_name, :unit)
        ]
      })

    layer =
      Layer.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        name: "derived points model",
        declarations:
          [
            %{kind: :space_system, qualified_name: "/"},
            %{kind: :space_system, qualified_name: "/vehicle"}
          ] ++
            [
              raw_type,
              raw,
              container(raw),
              unit,
              derived_type,
              derived,
              algorithm(raw, derived)
            ]
      })

    {:ok, result} = MissionModels.compile_layers([layer])

    %{
      revision_id: result.revision.revision_id,
      derived_id: derived.semantic_id,
      raw_id: raw.semantic_id,
      raw: raw,
      space_system_id: hd(result.plans.algorithm.plan["algorithms"])["space_system_id"]
    }
  end

  defp activate_binding_set!(organization_id, mission_id, raw, revision_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: mission_id <> "-hk",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            field_id: "raw_counter",
            name: "raw_counter",
            parameter_id: raw.semantic_id,
            qualified_name: raw.qualified_name,
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(organization_id, binding_set)

    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        mission_id,
        persisted.binding_set_id,
        persisted.version,
        binding_set_content_sha256: MissionRuntimeSpec.content_sha256(persisted),
        publish: false,
        metadata: %{"mission_model" => %{"revision_id" => revision_id}}
      )

    :ok
  end

  defp algorithm(raw, derived) do
    Declaration.new(%{
      kind: :algorithm,
      qualified_name: "/vehicle/algorithms/bus_volts",
      references: [reference(:parameter, raw.qualified_name, :input)],
      definition: %{
        implementation: %{kind: :expression},
        outputs: [
          %{
            parameter_id: derived.semantic_id,
            qualified_name: derived.qualified_name,
            expression:
              Expression.new(%{
                node: {:*, {:parameter, raw.semantic_id}, {:literal, 0.01}},
                result_type: :number
              })
          }
        ]
      }
    })
  end

  defp typed_parameter(qualified_name) do
    type =
      Declaration.new(%{
        kind: :parameter_type,
        qualified_name: qualified_name <> "_type",
        definition: %{
          base_type: :integer,
          encoding: %{size_bits: 16, signed: false, byte_order: :big_endian}
        }
      })

    parameter =
      Declaration.new(%{
        kind: :parameter,
        qualified_name: qualified_name,
        references: [reference(:parameter_type, type.qualified_name, :type)]
      })

    {type, parameter}
  end

  defp container(parameter) do
    Declaration.new(%{
      kind: :container,
      qualified_name: "/vehicle/containers/hk",
      definition: %{
        apid: 42,
        entries: [%{parameter_ref: parameter.qualified_name, bit_offset: 0, size_bits: 16}]
      },
      references: [reference(:parameter, parameter.qualified_name, :entry)]
    })
  end

  defp reference(kind, source_ref, role),
    do: Reference.new(%{expected_kind: kind, source_ref: source_ref, role: role})
end
