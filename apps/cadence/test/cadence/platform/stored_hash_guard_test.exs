defmodule Cadence.Platform.StoredHashGuardTest do
  @moduledoc """
  DECISIONS #108 and #166 guard: stored hashes that are recomputed and compared. The three
  high-risk bases now project named struct fields into versioned canonical JSON. Changing an
  included field or its default changes stored values, so every identity decision is reviewed.

  - SHAPES and CANARIES: each struct reachable from these hashes has its key set pinned here.
    A new field must be put into the versioned basis or explicitly excluded. Included changes
    require a basis version bump and reseed plan; no frozen legacy basis exists in dev.
  - GOLDEN: fixed fixtures pinned to their hashes, for the hashes a pure fixture reaches:
    BindingSet.content_sha256 (whose value the mission runtime basis hashes in turn) and
    Declaration.fingerprint (checked against an authored override's stored expected_fingerprint).
    The application-inputs basis and the review token built on it hash the
    Applications.* structs pinned below.
  - DEFAULTS are pinned with the keys: a stored row decoded without a key takes its default, so a
    changed default moves stored hashes exactly like a new field (api-ops).

  NEVER just re-pin a golden: find what moved it and review the stored-value migration first.
  """
  use Cadence.UnitCase, async: true

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance,
    Selector,
    SelectorMatch,
    SelectorScope
  }

  alias Cadence.Applications.{
    ApplicationBinding,
    PacketBinding,
    PacketBindingConfiguration,
    PacketBindingResource
  }

  alias Cadence.Catalog.MissionModel.{Declaration, Provenance, Reference}
  alias Cadence.Telemetry.{FieldDefinition, PacketDefinition}
  alias Cadence.TestSupport.ContentBasisCanary

  @shapes %{
    BindingSet => [
      :binding_set_id,
      :capability_instances,
      :mission_id,
      :organization_id,
      :rules,
      :version
    ],
    BindingRule => [
      :binding_rule_id,
      :capability_config,
      :capability_instance_id,
      :fanout_mode,
      :handler_configuration,
      :handler_key,
      :priority,
      :selector
    ],
    CapabilityInstance => [
      :capability_config,
      :capability_instance_id,
      :family_key,
      :lifecycle_state,
      :runtime_configuration,
      :source_endpoint_ref,
      :target_scope
    ],
    CapabilityConfig => [:config_type, :document],
    Selector => [:match, :scope],
    SelectorScope => [:source_endpoint_ref, :target_scope],
    SelectorMatch => [:apid, :packet_kind],
    PacketDefinition => [
      :apid,
      :fields,
      :mission_id,
      :organization_id,
      :packet_definition_id,
      :packet_name,
      :version
    ],
    FieldDefinition => [
      :byte_order,
      :data_type,
      :engineering_unit,
      :field_id,
      :name,
      :offset_bits,
      :parameter_id,
      :qualified_name,
      :size_bits
    ],
    ApplicationBinding => [
      :application_binding_id,
      :application_key,
      :applied_at,
      :applied_binding_set_id,
      :applied_binding_set_version,
      :catalog_revision_id,
      :configuration_version,
      :enabled,
      :handled_apids,
      :metadata,
      :mission_id,
      :organization_id,
      :source_endpoint_id,
      :spacecraft_id,
      :updated_at
    ],
    PacketBindingConfiguration => [
      :application_installation_id,
      :application_key,
      :application_version,
      :applied_at,
      :applied_binding_set_id,
      :applied_binding_set_version,
      :bindings,
      :capability_family_key,
      :configuration_version,
      :enabled,
      :input_id,
      :input_version,
      :inserted_at,
      :metadata,
      :mission_id,
      :organization_id,
      :packet_binding_configuration_id,
      :spacecraft_id,
      :updated_at
    ],
    PacketBinding => [
      :apid,
      :catalog_revision_id,
      :metadata,
      :mission_model_revision_id,
      :packet_binding_id,
      :packet_id,
      :packet_model_content_sha256,
      :packet_name,
      :resources,
      :selector,
      :source_endpoint_ref
    ],
    PacketBindingResource => [
      :data_type,
      :metadata,
      :offset_bits,
      :packet_binding_resource_id,
      :path,
      :resource_id,
      :resource_kind,
      :role,
      :size_bits
    ],
    Declaration => [
      :aliases,
      :definition,
      :expected_fingerprint,
      :extensions,
      :kind,
      :name,
      :operation,
      :provenance,
      :qualified_name,
      :references,
      :semantic_id,
      :space_system_path
    ],
    Reference => [
      :expected_kind,
      :provenance,
      :required,
      :resolved_id,
      :resolved_qualified_name,
      :role,
      :source_ref
    ],
    Provenance => [
      :artifact_id,
      :importer_key,
      :importer_version,
      :metadata,
      :source_location,
      :source_path,
      :transformations
    ]
  }

  # Every default that isn't nil (the rest default to nil).
  @defaults %{
    BindingSet => %{capability_instances: [], rules: []},
    BindingRule => %{fanout_mode: :exclusive, priority: 100},
    CapabilityInstance => %{lifecycle_state: :active},
    CapabilityConfig => %{document: %{}},
    Selector => %{},
    SelectorScope => %{},
    SelectorMatch => %{},
    PacketDefinition => %{fields: []},
    FieldDefinition => %{byte_order: :big_endian},
    ApplicationBinding => %{enabled: true, handled_apids: [], metadata: %{}},
    PacketBindingConfiguration => %{bindings: [], enabled: true, metadata: %{}},
    PacketBinding => %{metadata: %{}, resources: [], selector: %{}},
    PacketBindingResource => %{metadata: %{}},
    Declaration => %{
      aliases: [],
      definition: %{},
      extensions: %{},
      operation: :add,
      references: []
    },
    Reference => %{required: true},
    Provenance => %{metadata: %{}, source_path: [], transformations: []}
  }

  @rule "it feeds a stored hash (DECISIONS #108/#166). Decide whether a changed field enters " <>
          "the identity, bump its basis version if it does, and plan a dev/stack reset."

  # The #166 named v1 basis replaces the earlier whole-struct values in dev.
  @golden_binding_set "binding_set:v1:a92fd1bb439bf1b44ea1f47b91339d6202e173edddd43b8df2aab51d0d9c0970"
  @golden_declaration "override_fingerprint:v1:d8872b667e94c9cf3e706dc012f4ab8462f95990eb25341a61ea7a2ea7941312"

  describe "structs reachable from stored hashes (#108)" do
    for {module, keys} <- @shapes do
      defaults = Map.fetch!(@defaults, module)

      test "#{inspect(module)} keeps its pinned shape and defaults" do
        expected =
          unquote(keys) |> Map.new(&{&1, nil}) |> Map.merge(unquote(Macro.escape(defaults)))

        assert Map.from_struct(unquote(module).__struct__()) == expected,
               "#{inspect(unquote(module))} changed its fields or defaults; " <> @rule
      end
    end
  end

  test "every projected struct field is included or explicitly excluded" do
    exclusions = %{
      FieldDefinition => [:parameter_id, :qualified_name],
      Declaration => [:expected_fingerprint, :name, :operation, :provenance, :space_system_path],
      ApplicationBinding => [
        :applied_at,
        :applied_binding_set_id,
        :applied_binding_set_version,
        :updated_at
      ],
      PacketBindingConfiguration => [
        :applied_at,
        :applied_binding_set_id,
        :applied_binding_set_version,
        :inserted_at,
        :updated_at
      ]
    }

    for {name, owner} <- [
          {"binding_set", BindingSet},
          {"override_fingerprint", Declaration},
          {"configuration_inputs", Cadence.Applications.SpacecraftConfiguration.ApplicationInputs}
        ],
        {module, included} <- owner.basis_struct_fields() do
      ContentBasisCanary.assert_struct_fields!(module, name, 1,
        included: included,
        excluded: Map.get(exclusions, module, [])
      )
    end
  end

  describe "golden hashes (#108)" do
    test "BindingSet.content_sha256 of a fixed binding set" do
      assert BindingSet.content_sha256(binding_set()) == @golden_binding_set, golden_message()
    end

    test "a field's parameter_id and qualified_name don't move it (#73)" do
      named =
        update_in(binding_set().capability_instances, fn [instance] ->
          [
            update_in(instance.runtime_configuration.fields, fn fields ->
              Enum.map(fields, &%{&1 | parameter_id: "param-1", qualified_name: "/BUS/HK/mode"})
            end)
          ]
        end)

      assert BindingSet.content_sha256(named) == @golden_binding_set, golden_message()
    end

    test "Declaration.fingerprint of a fixed declaration" do
      assert Declaration.fingerprint(declaration()) == @golden_declaration, golden_message()
    end
  end

  defp golden_message do
    "A golden stored-hash value moved. Review the named fields and their canonical JSON " <>
      "encoding before updating the pin: " <> @rule
  end

  defp binding_set do
    packet = %PacketDefinition{
      packet_definition_id: "packet-golden",
      organization_id: "org-golden",
      mission_id: "mission-golden",
      packet_name: "HEALTH",
      apid: 42,
      version: 2,
      fields: [
        %FieldDefinition{
          field_id: "field-mode",
          name: "mode",
          offset_bits: 0,
          size_bits: 8,
          data_type: :uint,
          engineering_unit: nil,
          byte_order: :big_endian
        },
        %FieldDefinition{
          field_id: "field-volts",
          name: "volts",
          offset_bits: 8,
          size_bits: 16,
          data_type: :int,
          engineering_unit: "V",
          byte_order: :little_endian
        }
      ]
    }

    config = %CapabilityConfig{config_type: :telemetry_decom, document: %{"packet" => "HEALTH"}}

    %BindingSet{
      binding_set_id: "binding-set-golden",
      organization_id: "org-golden",
      mission_id: "mission-golden",
      version: 9,
      capability_instances: [
        %CapabilityInstance{
          capability_instance_id: "instance-golden",
          family_key: "telemetry_decom",
          target_scope: "spacecraft:sc-golden",
          source_endpoint_ref: "endpoint-golden",
          capability_config: config,
          runtime_configuration: packet,
          lifecycle_state: :active
        }
      ],
      rules: [
        %BindingRule{
          binding_rule_id: "rule-golden",
          capability_instance_id: "instance-golden",
          handler_key: :telemetry_decom,
          selector: %Selector{
            scope: %SelectorScope{
              target_scope: "spacecraft:sc-golden",
              source_endpoint_ref: "endpoint-golden"
            },
            match: %SelectorMatch{packet_kind: :telemetry, apid: 42}
          },
          capability_config: config,
          handler_configuration: packet,
          priority: 100,
          fanout_mode: :exclusive
        }
      ]
    }
  end

  defp declaration do
    %Declaration{
      semantic_id: "semantic:parameter:golden",
      kind: :parameter,
      name: "mode",
      qualified_name: "/BUS/HK/mode",
      space_system_path: "/BUS/HK",
      aliases: ["MODE"],
      definition: %{"type" => "uint8"},
      extensions: %{"x" => 1},
      references: [
        %Reference{
          expected_kind: :parameter_type,
          source_ref: "uint8_t",
          role: :type,
          required: true,
          provenance: %Provenance{
            artifact_id: "artifact-golden",
            importer_key: "cadence_yaml",
            importer_version: "1",
            source_path: ["packets", 0, "items", 0],
            metadata: %{}
          }
        }
      ]
    }
  end
end
