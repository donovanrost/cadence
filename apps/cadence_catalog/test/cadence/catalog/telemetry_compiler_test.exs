defmodule Cadence.Catalog.TelemetryCompilerTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Telemetry.{
    Compiler,
    Compiler.Result,
    Compiler.SelectorInput,
    Snapshot
  }

  test "compiles supported canonical telemetry packets into runtime packet definitions and selector inputs" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-alpha",
        organization_id: "org-alpha",
        mission_id: "mission-alpha",
        artifact_id: "artifact-alpha",
        import_run_id: "import-run-alpha",
        importer_key: "xtce",
        snapshot_name: "Mission Alpha TM",
        types: [
          %{
            type_id: "type-counter",
            snapshot_id: "snapshot-alpha",
            name: "CounterType",
            base_type: :integer,
            encoding: %{encoding_type: :integer, size_bits: 16, signed: false}
          },
          %{
            type_id: "type-enabled",
            snapshot_id: "snapshot-alpha",
            name: "EnabledType",
            base_type: :boolean,
            encoding: %{encoding_type: :boolean, size_bits: 1}
          },
          %{
            type_id: "type-temperature",
            snapshot_id: "snapshot-alpha",
            name: "TemperatureType",
            base_type: :float,
            encoding: %{encoding_type: :float, size_bits: 32, byte_order: :big_endian}
          }
        ],
        points: [
          %{
            point_id: "point-counter",
            snapshot_id: "snapshot-alpha",
            name: "counter",
            type_ref: "type-counter"
          },
          %{
            point_id: "point-enabled",
            snapshot_id: "snapshot-alpha",
            name: "enabled",
            type_ref: "type-enabled"
          },
          %{
            point_id: "point-temperature",
            snapshot_id: "snapshot-alpha",
            name: "temperature_c",
            type_ref: "type-temperature"
          }
        ],
        packets: [
          %{
            packet_id: "packet-hk",
            snapshot_id: "snapshot-alpha",
            name: "HK",
            apid: 42,
            entries: [
              %{
                packet_entry_id: "entry-counter",
                entry_kind: :point_ref,
                point_ref: "point-counter",
                bit_offset: 0
              },
              %{
                packet_entry_id: "entry-enabled",
                entry_kind: :point_ref,
                point_ref: "point-enabled",
                bit_offset: 16
              },
              %{
                packet_entry_id: "entry-temperature",
                entry_kind: :point_ref,
                point_ref: "point-temperature",
                bit_offset: 32
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [packet_definition],
             selector_inputs: [selector_input],
             diagnostics: []
           } =
             Compiler.compile(
               snapshot,
               packet_definition_version: 7,
               target_scope: :source_endpoint,
               source_endpoint_ref: "endpoint-sc-001"
             )

    assert packet_definition.packet_definition_id == "packet-hk"
    assert packet_definition.organization_id == "org-alpha"
    assert packet_definition.mission_id == "mission-alpha"
    assert packet_definition.packet_name == "HK"
    assert packet_definition.apid == 42
    assert packet_definition.version == 7

    assert Enum.map(
             packet_definition.fields,
             &{&1.name, &1.offset_bits, &1.size_bits, &1.data_type, &1.byte_order}
           ) == [
             {"counter", 0, 16, :uint, :big_endian},
             {"enabled", 16, 1, :bool, :big_endian},
             {"temperature_c", 32, 32, :float, :big_endian}
           ]

    assert %SelectorInput{} = selector_input
    assert selector_input.packet_id == "packet-hk"
    assert selector_input.packet_definition_id == "packet-hk"
    assert selector_input.capability_instance_id == "packet-hk_telemetry"
    assert selector_input.capability_family_key == :definition_bound_telemetry
    assert selector_input.selector.scope.target_scope == :source_endpoint
    assert selector_input.selector.scope.source_endpoint_ref == "endpoint-sc-001"
    assert selector_input.selector.match.packet_kind == :space_packet
    assert selector_input.selector.match.apid == 42
    assert selector_input.capability_config.config_type == :governed_packet_definition
    assert selector_input.capability_config.document["packet_definition_id"] == "packet-hk"
    assert selector_input.capability_config.document["version"] == 7
  end

  test "emits diagnostics and skips packets that current runtime cannot compile" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-beta",
        mission_id: "mission-alpha",
        artifact_id: "artifact-beta",
        import_run_id: "import-run-beta",
        importer_key: "xtce",
        snapshot_name: "Mission Alpha TM Unsupported",
        types: [
          %{
            type_id: "type-string",
            snapshot_id: "snapshot-beta",
            name: "StringType",
            base_type: :string,
            encoding: %{encoding_type: :string, size_bits: 32}
          }
        ],
        points: [
          %{
            point_id: "point-string",
            snapshot_id: "snapshot-beta",
            name: "string_value",
            type_ref: "type-string"
          }
        ],
        packets: [
          %{
            packet_id: "packet-no-apid",
            snapshot_id: "snapshot-beta",
            name: "NO_APID",
            entries: [
              %{
                packet_entry_id: "entry-string",
                entry_kind: :point_ref,
                point_ref: "point-string",
                bit_offset: 0
              }
            ]
          },
          %{
            packet_id: "packet-nested",
            snapshot_id: "snapshot-beta",
            name: "NESTED",
            apid: 88,
            entries: [
              %{
                packet_entry_id: "entry-nested",
                entry_kind: :nested_packet_ref,
                nested_packet_ref: "other-packet",
                bit_offset: 0
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [],
             selector_inputs: [],
             diagnostics: diagnostics
           } = Compiler.compile(snapshot)

    diagnostic_codes = Enum.map(diagnostics, & &1.code)

    assert "telemetry_compiler.apid_required" in diagnostic_codes
    assert "telemetry_compiler.type_unsupported" in diagnostic_codes
    assert "telemetry_compiler.nested_packet_unsupported" in diagnostic_codes
  end

  test "compiles byte-aligned little-endian integer and float fields into runtime packet definitions" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-gamma",
        mission_id: "mission-alpha",
        artifact_id: "artifact-gamma",
        import_run_id: "import-run-gamma",
        importer_key: "cadence_yaml_telemetry",
        snapshot_name: "Mission Alpha TM Little Endian",
        types: [
          %{
            type_id: "type-counter-16",
            snapshot_id: "snapshot-gamma",
            name: "Counter16Type",
            base_type: :integer,
            encoding: %{encoding_type: :integer, size_bits: 16, byte_order: :little_endian}
          },
          %{
            type_id: "type-counter-32",
            snapshot_id: "snapshot-gamma",
            name: "Counter32Type",
            base_type: :integer,
            encoding: %{encoding_type: :integer, size_bits: 32, byte_order: :little_endian}
          },
          %{
            type_id: "type-temperature-32",
            snapshot_id: "snapshot-gamma",
            name: "Temperature32Type",
            base_type: :float,
            encoding: %{encoding_type: :float, size_bits: 32, byte_order: :little_endian}
          },
          %{
            type_id: "type-temperature-64",
            snapshot_id: "snapshot-gamma",
            name: "Temperature64Type",
            base_type: :float,
            encoding: %{encoding_type: :float, size_bits: 64, byte_order: :little_endian}
          }
        ],
        points: [
          %{
            point_id: "point-counter-16",
            snapshot_id: "snapshot-gamma",
            name: "counter_16",
            type_ref: "type-counter-16"
          },
          %{
            point_id: "point-counter-32",
            snapshot_id: "snapshot-gamma",
            name: "counter_32",
            type_ref: "type-counter-32"
          },
          %{
            point_id: "point-temperature-32",
            snapshot_id: "snapshot-gamma",
            name: "temperature_c",
            type_ref: "type-temperature-32"
          },
          %{
            point_id: "point-temperature-64",
            snapshot_id: "snapshot-gamma",
            name: "temperature_k",
            type_ref: "type-temperature-64"
          }
        ],
        packets: [
          %{
            packet_id: "packet-thermal",
            snapshot_id: "snapshot-gamma",
            name: "THERMAL",
            apid: 91,
            entries: [
              %{
                packet_entry_id: "entry-counter-16",
                entry_kind: :point_ref,
                point_ref: "point-counter-16",
                bit_offset: 0
              },
              %{
                packet_entry_id: "entry-counter-32",
                entry_kind: :point_ref,
                point_ref: "point-counter-32",
                bit_offset: 16
              },
              %{
                packet_entry_id: "entry-temperature-32",
                entry_kind: :point_ref,
                point_ref: "point-temperature-32",
                bit_offset: 48
              },
              %{
                packet_entry_id: "entry-temperature-64",
                entry_kind: :point_ref,
                point_ref: "point-temperature-64",
                bit_offset: 80
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [packet_definition],
             selector_inputs: [_selector_input],
             diagnostics: []
           } = Compiler.compile(snapshot)

    assert Enum.map(
             packet_definition.fields,
             &{&1.name, &1.offset_bits, &1.size_bits, &1.data_type, &1.byte_order}
           ) == [
             {"counter_16", 0, 16, :uint, :little_endian},
             {"counter_32", 16, 32, :uint, :little_endian},
             {"temperature_c", 48, 32, :float, :little_endian},
             {"temperature_k", 80, 64, :float, :little_endian}
           ]
  end

  test "emits narrowed diagnostics for little-endian fields outside the executable runtime subset" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-delta",
        mission_id: "mission-alpha",
        artifact_id: "artifact-delta",
        import_run_id: "import-run-delta",
        importer_key: "cadence_yaml_telemetry",
        snapshot_name: "Mission Alpha TM Unsupported Little Endian Layouts",
        types: [
          %{
            type_id: "type-counter",
            snapshot_id: "snapshot-delta",
            name: "CounterType",
            base_type: :integer,
            encoding: %{encoding_type: :integer, size_bits: 12, byte_order: :little_endian}
          },
          %{
            type_id: "type-temperature",
            snapshot_id: "snapshot-delta",
            name: "TemperatureType",
            base_type: :float,
            encoding: %{encoding_type: :float, size_bits: 32, byte_order: :little_endian}
          }
        ],
        points: [
          %{
            point_id: "point-counter",
            snapshot_id: "snapshot-delta",
            name: "counter",
            type_ref: "type-counter"
          },
          %{
            point_id: "point-temperature",
            snapshot_id: "snapshot-delta",
            name: "temperature_c",
            type_ref: "type-temperature"
          }
        ],
        packets: [
          %{
            packet_id: "packet-hk",
            snapshot_id: "snapshot-delta",
            name: "HK",
            apid: 42,
            entries: [
              %{
                packet_entry_id: "entry-counter",
                entry_kind: :point_ref,
                point_ref: "point-counter",
                bit_offset: 0
              }
            ]
          },
          %{
            packet_id: "packet-thermal",
            snapshot_id: "snapshot-delta",
            name: "THERMAL",
            apid: 43,
            entries: [
              %{
                packet_entry_id: "entry-temperature",
                entry_kind: :point_ref,
                point_ref: "point-temperature",
                bit_offset: 4
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [],
             selector_inputs: [],
             diagnostics: diagnostics
           } = Compiler.compile(snapshot)

    diagnostic_codes = Enum.map(diagnostics, & &1.code)

    assert "telemetry_compiler.integer_little_endian_non_byte_aligned_unsupported" in diagnostic_codes

    assert "telemetry_compiler.float_little_endian_non_byte_aligned_unsupported" in diagnostic_codes
  end

  test "emits diagnostics and skips multi-bit booleans that current runtime cannot compile" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-epsilon",
        mission_id: "mission-alpha",
        artifact_id: "artifact-epsilon",
        import_run_id: "import-run-epsilon",
        importer_key: "cadence_yaml_telemetry",
        snapshot_name: "Mission Alpha TM Wide Boolean",
        types: [
          %{
            type_id: "type-enabled",
            snapshot_id: "snapshot-epsilon",
            name: "EnabledType",
            base_type: :boolean,
            encoding: %{encoding_type: :boolean, size_bits: 8}
          }
        ],
        points: [
          %{
            point_id: "point-enabled",
            snapshot_id: "snapshot-epsilon",
            name: "enabled",
            type_ref: "type-enabled"
          }
        ],
        packets: [
          %{
            packet_id: "packet-hk",
            snapshot_id: "snapshot-epsilon",
            name: "HK",
            apid: 42,
            entries: [
              %{
                packet_entry_id: "entry-enabled",
                entry_kind: :point_ref,
                point_ref: "point-enabled",
                bit_offset: 0
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [],
             selector_inputs: [],
             diagnostics: diagnostics
           } = Compiler.compile(snapshot)

    assert "telemetry_compiler.bool_size_unsupported" in Enum.map(diagnostics, & &1.code)
  end

  test "marks binary packet content as preserved for custom application binding" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-zeta",
        mission_id: "mission-alpha",
        artifact_id: "artifact-zeta",
        import_run_id: "import-run-zeta",
        importer_key: "cadence_yaml_telemetry",
        snapshot_name: "Mission Alpha TM Binary Payload",
        types: [
          %{
            type_id: "type-data-block",
            snapshot_id: "snapshot-zeta",
            name: "DataBlockType",
            base_type: :binary,
            encoding: %{encoding_type: :binary, size_bits: 32_672}
          }
        ],
        points: [
          %{
            point_id: "point-data-block",
            snapshot_id: "snapshot-zeta",
            name: "data_block",
            type_ref: "type-data-block"
          }
        ],
        packets: [
          %{
            packet_id: "packet-science",
            snapshot_id: "snapshot-zeta",
            name: "SCIENCE_FRAME",
            apid: 42,
            entries: [
              %{
                packet_entry_id: "entry-data-block",
                entry_kind: :point_ref,
                point_ref: "point-data-block",
                bit_offset: 96
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [packet_definition],
             selector_inputs: [selector_input],
             diagnostics: [diagnostic]
           } = Compiler.compile(snapshot)

    assert packet_definition.packet_name == "SCIENCE_FRAME"

    assert [%{name: "data_block", data_type: :binary, size_bits: 32_672}] =
             packet_definition.fields

    assert selector_input.selector.match.apid == 42

    assert diagnostic.severity == :warning
    assert diagnostic.code == "telemetry_compiler.available_for_custom_application_binding"
    assert diagnostic.metadata["base_type"] == "binary"
    assert diagnostic.metadata["diagnostic_stage"] == "built_in_telemetry_binding"

    assert diagnostic.metadata["consumption_status"] ==
             "available_for_custom_application_binding"
  end

  test "keeps scalar telemetry and binary resources in the same packet definition" do
    snapshot =
      Snapshot.new(%{
        snapshot_id: "snapshot-camera",
        mission_id: "mission-alpha",
        artifact_id: "artifact-camera",
        import_run_id: "import-run-camera",
        importer_key: "cadence_yaml_telemetry",
        snapshot_name: "Mixed Camera Packet",
        types: [
          %{
            type_id: "type-temperature",
            snapshot_id: "snapshot-camera",
            name: "TemperatureType",
            base_type: :float,
            encoding: %{encoding_type: :ieee754, size_bits: 32}
          },
          %{
            type_id: "type-camera-bytes",
            snapshot_id: "snapshot-camera",
            name: "CameraBytesType",
            base_type: :binary,
            encoding: %{encoding_type: :binary, size_bits: 8_192}
          }
        ],
        points: [
          %{
            point_id: "point-temperature",
            snapshot_id: "snapshot-camera",
            name: "temperature_c",
            type_ref: "type-temperature"
          },
          %{
            point_id: "point-camera-bytes",
            snapshot_id: "snapshot-camera",
            name: "camera_bytes",
            type_ref: "type-camera-bytes"
          }
        ],
        packets: [
          %{
            packet_id: "packet-camera",
            snapshot_id: "snapshot-camera",
            name: "CAMERA",
            apid: 81,
            entries: [
              %{
                packet_entry_id: "entry-temperature",
                entry_kind: :point_ref,
                point_ref: "point-temperature",
                bit_offset: 0
              },
              %{
                packet_entry_id: "entry-camera-bytes",
                entry_kind: :point_ref,
                point_ref: "point-camera-bytes",
                bit_offset: 32
              }
            ]
          }
        ]
      })

    assert %Result{
             packet_definitions: [packet_definition],
             selector_inputs: [%{selector: %{match: %{apid: 81}}}],
             diagnostics: [diagnostic]
           } = Compiler.compile(snapshot)

    assert Enum.map(packet_definition.fields, &{&1.name, &1.data_type}) == [
             {"temperature_c", :float},
             {"camera_bytes", :binary}
           ]

    assert diagnostic.code == "telemetry_compiler.available_for_custom_application_binding"
  end
end
