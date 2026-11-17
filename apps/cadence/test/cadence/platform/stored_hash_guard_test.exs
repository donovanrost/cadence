defmodule Cadence.Platform.StoredHashGuardTest do
  @moduledoc """
  DECISIONS #108 guard: stored hashes that are recomputed and compared, and that today hash
  struct terms. A struct is a map, so adding, removing or renaming a field (or changing a
  default) in any struct these hashes reach changes every stored value, and stored generations
  stop verifying (the 11-17 calibration restart).

  - SHAPES: each struct reachable from a HIGH hash has its key set pinned here. A change fails
    this test on purpose. Keep the hash stable in the same commit (leave the field out, or out
    while at its default, as #73 does), add a legacy-value test, and only then update the list
    here. Otherwise get a director-approved plan for the stored values.
  - GOLDEN: fixed fixtures pinned to their hashes, for the hashes a pure fixture reaches:
    BindingSet.content_sha256 (whose value the mission runtime basis hashes in turn) and
    Declaration.fingerprint (checked against an authored override's stored expected_fingerprint).
    The application-inputs basis and the review token built on it hash the
    Applications.* structs pinned below.
  - DEFAULTS are pinned with the keys: a stored row decoded without a key takes its default, so a
    changed default moves stored hashes exactly like a new field (api-ops).

  The hashes are `:erlang.term_to_binary(term, [:deterministic])` over whole struct terms, so the
  goldens also move on a struct MODULE rename or move (the `__struct__` atom is hashed), on a
  field's value changing type (an atom becoming a string), and on an Erlang/OTP or Elixir upgrade
  that changes the external term format. Every one of those stops every stored generation from
  verifying. NEVER just re-pin a golden: find what moved it, keep stored values verifying (or get
  a director-approved plan for them) BEFORE that change lands, and only then update the pin.
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
    Reference => %{required: true},
    Provenance => %{metadata: %{}, source_path: [], transformations: []}
  }

  @rule "it feeds a stored hash (DECISIONS #108). Keep stored values verifying in the same commit " <>
          "(leave the field out, or out at its default, with a legacy-value test) or get a " <>
          "director-approved plan; only then update the pin."

  # Pinned 11-17 on the tree that verifies Earendil's stored generation 9.
  @golden_binding_set "35734e0ee261b3e9bf041ca5744f66b36bdb6685115262b056547bd24aede372"
  @golden_declaration "af8853f96fcb709a7e1adadabe3f6eed881327be77142c5c4ce1429241af0976"

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
    "A golden stored-hash value moved: a struct reached by it changed (fields, defaults, module " <>
      "name or a value's type), or the Erlang/OTP or Elixir term encoding changed. Don't just " <>
      "re-pin: " <> @rule
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
