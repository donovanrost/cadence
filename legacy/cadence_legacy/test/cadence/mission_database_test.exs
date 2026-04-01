defmodule Cadence.MissionDatabaseTest do
  use Cadence.DataCase, async: true

  import Cadence.MissionDatabaseFixtures
  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures

  alias Cadence.MissionDatabase.Database

  alias Cadence.MissionDatabase.{
    Algorithm,
    Argument,
    CommandContainer,
    CommandContainerEntry,
    CommandVerifier,
    Container,
    ContainerEntry,
    ContextAlarm,
    ContextCalibrator,
    DataType,
    DefinitionSet,
    DerivedItem,
    MetaCommand,
    Parameter,
    Stream,
    TransmissionConstraint,
    Unit
  }

  # ============================================================================
  # DefinitionSet Tests
  # ============================================================================

  describe "DefinitionSet" do
    test "creates a valid definition set" do
      ds = definition_set_fixture()
      assert ds.id
      assert ds.version
      assert ds.source_format == :yaml
      refute ds.published_at
    end

    test "requires organization_id, database_id, version, and source_format" do
      changeset = DefinitionSet.changeset(%DefinitionSet{}, %{})

      assert %{
               organization_id: ["can't be blank"],
               database_id: ["can't be blank"],
               version: ["can't be blank"],
               source_format: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "enforces unique version per database" do
      ds = definition_set_fixture()

      assert {:error, changeset} =
               %DefinitionSet{}
               |> DefinitionSet.changeset(%{
                 organization_id: ds.organization_id,
                 database_id: ds.database_id,
                 version: ds.version,
                 source_format: :yaml
               })
               |> Repo.insert()

      # Unique constraint error appears on database_id (composite key)
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :version) or Map.has_key?(errors, :database_id)
    end

    test "publishes a definition set" do
      ds = definition_set_fixture()
      refute ds.published_at

      {:ok, published} = DefinitionSet.publish(ds)
      assert published.published_at
      refute published.superseded_at
    end

    test "allows publishing multiple versions in a database" do
      ds1 = published_definition_set_fixture()
      # Get the database to create another definition set in same database
      database = Repo.get!(Database, ds1.database_id)
      ds2 = definition_set_fixture(database: database)

      {:ok, published2} = DefinitionSet.publish(ds2)

      # Both versions can be published simultaneously
      ds1_reloaded = Repo.get!(DefinitionSet, ds1.id)
      assert ds1_reloaded.published_at
      assert published2.published_at
      # Neither is superseded yet
      refute ds1_reloaded.superseded_at
      refute published2.superseded_at
    end

    test "deprecate marks a version as superseded" do
      ds1 = published_definition_set_fixture()

      {:ok, deprecated} = DefinitionSet.deprecate(ds1)

      assert deprecated.superseded_at
      refute DefinitionSet.active?(deprecated)
    end

    test "get_latest_published returns the currently active version" do
      ds = published_definition_set_fixture()
      active = DefinitionSet.get_latest_published(ds.database_id)
      assert active.id == ds.id
    end

    test "get_latest_published returns nil when no published version" do
      ds = definition_set_fixture()
      assert is_nil(DefinitionSet.get_latest_published(ds.database_id))
    end

    test "active?/1 correctly identifies active vs superseded" do
      ds1 = published_definition_set_fixture()
      assert DefinitionSet.active?(ds1)

      # Deprecate it
      {:ok, deprecated} = DefinitionSet.deprecate(ds1)

      refute DefinitionSet.active?(deprecated)
      # Reloaded from DB should also show as not active
      ds1_reloaded = Repo.get!(DefinitionSet, ds1.id)
      refute DefinitionSet.active?(ds1_reloaded)
    end
  end

  # ============================================================================
  # Unit Tests
  # ============================================================================

  describe "Unit" do
    test "creates a valid unit" do
      unit = unit_fixture(symbol: "degC", si_conversion_factor: 1.0, si_conversion_offset: 273.15)
      assert unit.symbol == "degC"
      assert unit.si_conversion_factor == 1.0
      assert unit.si_conversion_offset == 273.15
    end

    test "requires name and definition_set_id" do
      changeset = Unit.changeset(%Unit{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.definition_set_id
      assert "can't be blank" in errors.name
    end

    test "enforces unique name per definition_set" do
      unit = unit_fixture()

      assert {:error, changeset} =
               %Unit{}
               |> Unit.changeset(%{
                 organization_id: unit.organization_id,
                 mission_id: unit.mission_id,
                 definition_set_id: unit.definition_set_id,
                 name: unit.name,
                 symbol: "x"
               })
               |> Repo.insert()

      # The unique constraint is on [definition_set_id, name]
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name) or Map.has_key?(errors, :definition_set_id)
    end
  end

  # ============================================================================
  # Algorithm (Calibrator) Tests
  # ============================================================================

  describe "Algorithm" do
    test "creates a polynomial calibrator" do
      algo = polynomial_calibrator_fixture()
      assert algo.algorithm_type == :polynomial
      assert algo.polynomial_coefficients == [0.0, 0.01, 0.0001]
    end

    test "creates a state_table calibrator" do
      algo = state_table_calibrator_fixture()
      assert algo.algorithm_type == :state_table
      assert algo.state_table[0] == "OFF"
      assert algo.state_table[1] == "ON"
    end

    test "creates a spline calibrator" do
      algo = spline_calibrator_fixture()
      assert algo.algorithm_type == :spline
      assert length(algo.spline_points) == 4
    end

    test "requires name and algorithm_type" do
      changeset = Algorithm.changeset(%Algorithm{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.algorithm_type
    end

    test "validates algorithm_type is in allowed list" do
      ds = definition_set_fixture()

      changeset =
        Algorithm.changeset(%Algorithm{}, %{
          organization_id: ds.organization_id,
          definition_set_id: ds.id,
          name: "test",
          algorithm_type: :invalid_type
        })

      assert "is invalid" in errors_on(changeset).algorithm_type
    end
  end

  # ============================================================================
  # DataType Tests
  # ============================================================================

  describe "DataType" do
    test "creates an integer data type" do
      dt = data_type_fixture()
      assert dt.base_type == :integer
      assert dt.encoding.size_in_bits == 16
    end

    test "creates a float data type" do
      dt = float_data_type_fixture()
      assert dt.base_type == :float
      assert dt.encoding.size_in_bits == 32
    end

    test "creates an enumerated data type" do
      dt = enumerated_data_type_fixture()
      assert dt.base_type == :enumerated
      assert length(dt.enumerations) == 3
    end

    test "creates a string data type" do
      dt = string_data_type_fixture()
      assert dt.base_type == :string
      assert dt.encoding.charset == "UTF-8"
    end

    test "supports alarm_definition embedded schema" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)

      {:ok, dt} =
        %DataType{}
        |> DataType.changeset(%{
          organization_id: ds.organization_id,
          mission_id: database.mission_id,
          definition_set_id: ds.id,
          name: "temp_with_alarms",
          base_type: :float,
          encoding: %{encoding_type: :float, size_in_bits: 32},
          default_alarm: %{
            watch_range: %{min_inclusive: 10.0, max_inclusive: 40.0},
            warning_range: %{min_inclusive: 5.0, max_inclusive: 45.0},
            critical_range: %{min_inclusive: 0.0, max_inclusive: 50.0}
          }
        })
        |> Repo.insert()

      assert dt.default_alarm.watch_range.min_inclusive == 10.0
      assert dt.default_alarm.critical_range.max_inclusive == 50.0
    end

    test "requires name, base_type, and definition_set_id" do
      changeset = DataType.changeset(%DataType{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.base_type
      assert "can't be blank" in errors.definition_set_id
    end
  end

  # ============================================================================
  # ContextCalibrator Tests
  # ============================================================================

  describe "ContextCalibrator" do
    test "creates a context-dependent calibrator" do
      ds = definition_set_fixture()
      dt = data_type_fixture(definition_set: ds)
      algo = algorithm_fixture(definition_set: ds)

      {:ok, cc} =
        %ContextCalibrator{}
        |> ContextCalibrator.changeset(%{
          data_type_id: dt.id,
          algorithm_id: algo.id,
          match_criteria: %{
            parameter_ref: "MODE.STATUS",
            comparison: :equal,
            value: "SAFE"
          },
          display_order: 0
        })
        |> Repo.insert()

      assert cc.match_criteria.parameter_ref == "MODE.STATUS"
      assert cc.match_criteria.comparison == :equal
    end

    test "requires data_type_id, algorithm_id, and match_criteria" do
      changeset = ContextCalibrator.changeset(%ContextCalibrator{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.data_type_id
      assert "can't be blank" in errors.algorithm_id
      assert "can't be blank" in errors.match_criteria
    end
  end

  # ============================================================================
  # ContextAlarm Tests
  # ============================================================================

  describe "ContextAlarm" do
    test "creates a context-dependent alarm" do
      ca = context_alarm_fixture()
      assert ca.match_criteria.parameter_ref == "MODE.STATUS"
      assert ca.alarm_definition.watch_range.min_inclusive == 10.0
    end

    test "requires data_type_id, match_criteria, and alarm_definition" do
      changeset = ContextAlarm.changeset(%ContextAlarm{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.data_type_id
      assert "can't be blank" in errors.match_criteria
      assert "can't be blank" in errors.alarm_definition
    end
  end

  # ============================================================================
  # Stream Tests
  # ============================================================================

  describe "Stream" do
    test "creates a valid stream" do
      stream = stream_fixture()
      assert stream.stream_type == :telemetry
      assert stream.framing_protocol == :fixed_length
      assert stream.sync_pattern == <<0x1A, 0xCF, 0xFC, 0x1D>>
    end

    test "supports various stream and framing types" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)

      for stream_type <- [:telemetry, :command, :bidirectional] do
        {:ok, stream} =
          %Stream{}
          |> Stream.changeset(%{
            organization_id: ds.organization_id,
            mission_id: database.mission_id,
            definition_set_id: ds.id,
            name: "stream-#{stream_type}-#{System.unique_integer([:positive])}",
            stream_type: stream_type,
            framing_protocol: :ccsds_packet
          })
          |> Repo.insert()

        assert stream.stream_type == stream_type
      end
    end

    test "requires name and stream_type" do
      changeset = Stream.changeset(%Stream{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.stream_type
    end
  end

  # ============================================================================
  # Container Tests
  # ============================================================================

  describe "Container" do
    test "creates a valid container" do
      container = container_fixture()
      assert container.name
      assert container.byte_order == :big_endian
    end

    test "supports container inheritance via base_container_ref" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)
      base = container_fixture(definition_set: ds, name: "BASE_PKT")

      {:ok, derived} =
        %Container{}
        |> Container.changeset(%{
          organization_id: ds.organization_id,
          mission_id: database.mission_id,
          definition_set_id: ds.id,
          name: "DERIVED_PKT",
          base_container_ref: base.name
        })
        |> Repo.insert()

      assert derived.base_container_ref == "BASE_PKT"
    end

    test "supports restriction_criteria for packet identification" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)

      {:ok, container} =
        %Container{}
        |> Container.changeset(%{
          organization_id: ds.organization_id,
          mission_id: database.mission_id,
          definition_set_id: ds.id,
          name: "HEALTH_PKT",
          restriction_criteria: %{
            parameter_ref: "CCSDS.APID",
            comparison: :equal,
            value: "100"
          }
        })
        |> Repo.insert()

      assert container.restriction_criteria.parameter_ref == "CCSDS.APID"
      assert container.restriction_criteria.value == "100"
    end

    test "supports APID field for CCSDS" do
      container = container_fixture(apid: 100)
      assert container.apid == 100
    end

    test "requires name and definition_set_id" do
      changeset = Container.changeset(%Container{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.definition_set_id
    end
  end

  # ============================================================================
  # Parameter Tests
  # ============================================================================

  describe "Parameter" do
    test "creates a valid parameter" do
      param = parameter_fixture()
      assert param.name
    end

    test "can reference a shared data_type" do
      ds = definition_set_fixture()
      dt = data_type_fixture(definition_set: ds)
      param = parameter_fixture(definition_set: ds, data_type: dt)

      assert param.data_type_id == dt.id
    end

    test "supports system_parameter flag" do
      param = parameter_fixture(system_parameter: true)
      assert param.system_parameter == true
    end

    test "requires name and definition_set_id" do
      changeset = Parameter.changeset(%Parameter{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.definition_set_id
    end
  end

  # ============================================================================
  # ContainerEntry Tests
  # ============================================================================

  describe "ContainerEntry" do
    test "creates a parameter_ref entry" do
      entry = container_entry_fixture()
      assert entry.entry_type == :parameter_ref
      assert entry.parameter_id
    end

    test "creates a fixed_value entry" do
      container = container_fixture()

      {:ok, entry} =
        %ContainerEntry{}
        |> ContainerEntry.changeset(%{
          container_id: container.id,
          entry_type: :fixed_value,
          fixed_value: <<0xDE, 0xAD>>,
          fixed_value_size_bits: 16,
          bit_offset: 0
        })
        |> Repo.insert()

      assert entry.entry_type == :fixed_value
      assert entry.fixed_value == <<0xDE, 0xAD>>
    end

    test "validates entry_type specific fields" do
      container = container_fixture()

      # fixed_value requires fixed_value and fixed_value_size_bits
      changeset =
        ContainerEntry.changeset(%ContainerEntry{}, %{
          container_id: container.id,
          entry_type: :fixed_value,
          bit_offset: 0
        })

      errors = errors_on(changeset)
      assert "required for fixed_value entry type" in errors.fixed_value
    end

    test "requires container_id and entry_type" do
      changeset = ContainerEntry.changeset(%ContainerEntry{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.container_id
      assert "can't be blank" in errors.entry_type
    end
  end

  # ============================================================================
  # MetaCommand Tests
  # ============================================================================

  describe "MetaCommand" do
    test "creates a valid command" do
      cmd = meta_command_fixture()
      assert cmd.name
      assert cmd.opcode
    end

    test "supports hazardous flag and description" do
      cmd = hazardous_command_fixture()
      assert cmd.is_hazardous == true
      assert cmd.hazard_description =~ "reset"
      assert cmd.significance == :critical
    end

    test "supports command inheritance via base_command_ref" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)
      base = meta_command_fixture(definition_set: ds, name: "BASE_CMD")

      {:ok, derived} =
        %MetaCommand{}
        |> MetaCommand.changeset(%{
          organization_id: ds.organization_id,
          mission_id: database.mission_id,
          definition_set_id: ds.id,
          name: "DERIVED_CMD",
          base_command_ref: base.name
        })
        |> Repo.insert()

      assert derived.base_command_ref == "BASE_CMD"
    end

    test "supports command interlocks" do
      ds = definition_set_fixture()
      database = Repo.get!(Database, ds.database_id)

      {:ok, cmd} =
        %MetaCommand{}
        |> MetaCommand.changeset(%{
          organization_id: ds.organization_id,
          mission_id: database.mission_id,
          definition_set_id: ds.id,
          name: "INTERLOCK_CMD",
          interlock: %{
            previous_command_ref: "INIT_SEQ",
            verification_stage: :accepted
          }
        })
        |> Repo.insert()

      assert cmd.interlock.previous_command_ref == "INIT_SEQ"
    end

    test "requires name and definition_set_id" do
      changeset = MetaCommand.changeset(%MetaCommand{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.definition_set_id
    end
  end

  # ============================================================================
  # Argument Tests
  # ============================================================================

  describe "Argument" do
    test "creates a valid argument" do
      arg = argument_fixture()
      assert arg.name
      assert arg.display_order == 0
    end

    test "supports default values" do
      arg = argument_fixture(default_value: "100")
      assert arg.default_value == "100"
    end

    test "supports range validation" do
      arg = argument_fixture(min_value: 0, max_value: 255)
      assert arg.min_value == 0.0
      assert arg.max_value == 255.0
    end

    test "requires meta_command_id and name" do
      changeset = Argument.changeset(%Argument{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.meta_command_id
      assert "can't be blank" in errors.name
    end
  end

  # ============================================================================
  # TransmissionConstraint Tests
  # ============================================================================

  describe "TransmissionConstraint" do
    test "creates a valid transmission constraint" do
      tc = transmission_constraint_fixture()
      assert tc.timeout_ms == 5000
      assert tc.match_criteria.parameter_ref == "HEALTH.MODE"
    end

    test "supports suspendable flag and on_failure action" do
      cmd = meta_command_fixture()

      {:ok, tc} =
        %TransmissionConstraint{}
        |> TransmissionConstraint.changeset(%{
          meta_command_id: cmd.id,
          name: "power_check",
          suspendable: true,
          on_failure: :warn,
          timeout_ms: 10_000,
          match_criteria: %{
            parameter_ref: "POWER.STATUS",
            comparison: :not_equal,
            value: "OFF"
          }
        })
        |> Repo.insert()

      assert tc.suspendable == true
      assert tc.on_failure == :warn
      assert tc.match_criteria.comparison == :not_equal
    end

    test "requires meta_command_id and match_criteria" do
      changeset = TransmissionConstraint.changeset(%TransmissionConstraint{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.meta_command_id
      assert "can't be blank" in errors.match_criteria
    end
  end

  # ============================================================================
  # CommandVerifier Tests
  # ============================================================================

  describe "CommandVerifier" do
    test "creates a valid verifier with telemetry_item_ref" do
      v = command_verifier_fixture()
      assert v.stage == :complete
      assert v.telemetry_item_ref == "CMD_STATUS.ACK_COUNT"
      assert v.comparison == :changed
    end

    test "supports verification stages" do
      cmd = meta_command_fixture()

      # Test a few valid stages from the schema
      for stage <- [:received, :accepted, :complete, :failed] do
        {:ok, v} =
          %CommandVerifier{}
          |> CommandVerifier.changeset(%{
            meta_command_id: cmd.id,
            stage: stage,
            telemetry_item_ref: "CMD_STATUS.COUNT",
            comparison: :changed,
            timeout_ms: 5000
          })
          |> Repo.insert()

        assert v.stage == stage
      end
    end

    test "supports match_criteria for complex conditions" do
      cmd = meta_command_fixture()

      {:ok, v} =
        %CommandVerifier{}
        |> CommandVerifier.changeset(%{
          meta_command_id: cmd.id,
          stage: :accepted,
          timeout_ms: 5000,
          match_criteria: %{
            parameter_ref: "CMD_ACK.STATUS",
            comparison: :equal,
            value: "SUCCESS"
          }
        })
        |> Repo.insert()

      assert v.match_criteria.parameter_ref == "CMD_ACK.STATUS"
      assert v.match_criteria.value == "SUCCESS"
    end

    test "requires meta_command_id and stage" do
      changeset = CommandVerifier.changeset(%CommandVerifier{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.meta_command_id
      assert "can't be blank" in errors.stage
    end

    test "requires either match_criteria or telemetry_item_ref" do
      cmd = meta_command_fixture()

      changeset =
        CommandVerifier.changeset(%CommandVerifier{}, %{
          meta_command_id: cmd.id,
          stage: :complete,
          timeout_ms: 5000
        })

      assert "must specify either match_criteria or telemetry_item_ref" in errors_on(changeset).match_criteria
    end
  end

  # ============================================================================
  # CommandContainer Tests
  # ============================================================================

  describe "CommandContainer" do
    test "creates a valid command container" do
      cc = command_container_fixture()
      assert cc.byte_order == :big_endian
      assert cc.size_in_bits == 64
    end

    test "supports header and trailer fields" do
      cmd = meta_command_fixture()

      {:ok, cc} =
        %CommandContainer{}
        |> CommandContainer.changeset(%{
          meta_command_id: cmd.id,
          name: "CMD_PKT",
          header: <<0x1A, 0xCF>>,
          trailer: <<0xFC, 0x1D>>,
          byte_order: :big_endian
        })
        |> Repo.insert()

      assert cc.header == <<0x1A, 0xCF>>
      assert cc.trailer == <<0xFC, 0x1D>>
    end

    test "validates size_in_bits <= max_size_in_bits" do
      cmd = meta_command_fixture()

      changeset =
        CommandContainer.changeset(%CommandContainer{}, %{
          meta_command_id: cmd.id,
          size_in_bits: 100,
          max_size_in_bits: 64
        })

      assert "cannot be greater than max_size_in_bits" in errors_on(changeset).size_in_bits
    end
  end

  # ============================================================================
  # CommandContainerEntry Tests
  # ============================================================================

  describe "CommandContainerEntry" do
    test "creates an argument_ref entry" do
      cc = command_container_fixture()
      arg = argument_fixture(meta_command: %{id: cc.meta_command_id})

      {:ok, entry} =
        %CommandContainerEntry{}
        |> CommandContainerEntry.changeset(%{
          command_container_id: cc.id,
          entry_type: :argument_ref,
          argument_id: arg.id,
          bit_offset: 16
        })
        |> Repo.insert()

      assert entry.entry_type == :argument_ref
      assert entry.argument_id == arg.id
    end

    test "creates a fixed_value entry" do
      cc = command_container_fixture()

      {:ok, entry} =
        %CommandContainerEntry{}
        |> CommandContainerEntry.changeset(%{
          command_container_id: cc.id,
          entry_type: :fixed_value,
          fixed_value: <<0x45>>,
          fixed_value_size_bits: 8,
          bit_offset: 0
        })
        |> Repo.insert()

      assert entry.entry_type == :fixed_value
      assert entry.fixed_value == <<0x45>>
    end

    test "creates a parameter_ref entry" do
      cc = command_container_fixture()

      {:ok, entry} =
        %CommandContainerEntry{}
        |> CommandContainerEntry.changeset(%{
          command_container_id: cc.id,
          entry_type: :parameter_ref,
          parameter_ref: "CONFIG.CURRENT_VALUE",
          bit_offset: 32
        })
        |> Repo.insert()

      assert entry.entry_type == :parameter_ref
      assert entry.parameter_ref == "CONFIG.CURRENT_VALUE"
    end

    test "validates entry_type specific requirements" do
      cc = command_container_fixture()

      # argument_ref requires argument_id
      changeset =
        CommandContainerEntry.changeset(%CommandContainerEntry{}, %{
          command_container_id: cc.id,
          entry_type: :argument_ref
        })

      assert "required for argument_ref entry type" in errors_on(changeset).argument_id
    end
  end

  # ============================================================================
  # DerivedItem Tests
  # ============================================================================

  describe "DerivedItem" do
    test "creates a valid derived item" do
      di = derived_item_fixture()
      assert di.name
      assert di.expression == "POWER.VOLTAGE * POWER.CURRENT"
      assert "POWER.VOLTAGE" in di.source_items
    end

    test "auto-extracts source_items from expression" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, di} =
        %DerivedItem{}
        |> DerivedItem.changeset(%{
          organization_id: org.id,
          mission_id: mission.id,
          name: "AUTO_EXTRACT",
          expression: "HEALTH.TEMP * 1.8 + 32"
        })
        |> Repo.insert()

      assert "HEALTH.TEMP" in di.source_items
    end

    test "supports rolling average expression" do
      di =
        derived_item_fixture(
          name: "TEMP_AVG",
          expression: "rolling_avg(HEALTH.TEMP, 10)",
          source_items: ["HEALTH.TEMP"]
        )

      assert di.expression =~ "rolling_avg"
    end

    test "supports conditional expressions" do
      di =
        derived_item_fixture(
          name: "STATUS",
          expression: "if POWER.VOLTAGE > 28 then 1 else 0",
          data_type: "int"
        )

      assert di.data_type == "int"
    end

    test "validates data_type is in allowed list" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      changeset =
        DerivedItem.changeset(%DerivedItem{}, %{
          organization_id: org.id,
          mission_id: mission.id,
          name: "BAD_TYPE",
          expression: "1 + 1",
          data_type: "invalid_type"
        })

      assert "is invalid" in errors_on(changeset).data_type
    end

    test "enforces unique name per mission" do
      di = derived_item_fixture()

      assert {:error, changeset} =
               %DerivedItem{}
               |> DerivedItem.changeset(%{
                 organization_id: di.organization_id,
                 mission_id: di.mission_id,
                 name: di.name,
                 expression: "1 + 1"
               })
               |> Repo.insert()

      # Unique constraint error
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :name) or Map.has_key?(errors, :mission_id)
    end

    test "requires organization_id, mission_id, name, and expression" do
      changeset = DerivedItem.changeset(%DerivedItem{}, %{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.organization_id
      assert "can't be blank" in errors.mission_id
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.expression
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "Full Definition Set with Associations" do
    test "loads complete definition set with all associations" do
      # Create a complete definition set with related entities
      ds = definition_set_fixture()

      # Add units
      unit = unit_fixture(definition_set: ds, name: "celsius", symbol: "C")

      # Add algorithms
      algo =
        algorithm_fixture(
          definition_set: ds,
          name: "temp_cal",
          algorithm_type: :polynomial,
          coefficients: [0.0, 0.1]
        )

      # Add data types with calibrator reference
      dt =
        data_type_fixture(
          definition_set: ds,
          name: "TEMP_TYPE",
          default_calibrator_id: algo.id,
          unit_id: unit.id
        )

      # Add streams
      _stream = stream_fixture(definition_set: ds, name: "TLM_STREAM")

      # Add containers and parameters
      container = container_fixture(definition_set: ds, name: "HEALTH_PKT")
      param = parameter_fixture(definition_set: ds, data_type: dt, name: "TEMP")
      _entry = container_entry_fixture(container: container, parameter: param)

      # Add commands
      cmd = meta_command_fixture(definition_set: ds, name: "SET_TEMP")
      _arg = argument_fixture(meta_command: cmd, data_type: dt, name: "target_temp")
      _constraint = transmission_constraint_fixture(meta_command: cmd)
      _verifier = command_verifier_fixture(meta_command: cmd)

      # Load complete
      {:ok, loaded} = DefinitionSet.load_complete(ds.id)

      assert length(loaded.units) == 1
      assert length(loaded.algorithms) == 1
      assert length(loaded.data_types) == 1
      assert length(loaded.streams) == 1
      assert length(loaded.containers) == 1
      assert length(loaded.parameters) == 1
      assert length(loaded.meta_commands) == 1

      # Check nested associations loaded
      [loaded_dt] = loaded.data_types
      assert loaded_dt.default_calibrator
      assert loaded_dt.unit

      [loaded_cmd] = loaded.meta_commands
      assert length(loaded_cmd.arguments) == 1
      assert length(loaded_cmd.transmission_constraints) == 1
      assert length(loaded_cmd.verifiers) == 1
    end
  end
end
