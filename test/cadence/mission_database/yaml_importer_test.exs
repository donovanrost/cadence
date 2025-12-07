defmodule Cadence.MissionDatabase.YamlImporterTest do
  use Cadence.DataCase

  alias Cadence.MissionDatabase.YamlImporter

  alias Cadence.MissionDatabase.{
    DataType,
    Algorithm,
    Unit,
    Container,
    ContainerEntry,
    Parameter,
    MetaCommand,
    Argument
  }

  import Cadence.MissionDatabaseFixtures

  describe "import_string/3" do
    setup do
      database = database_fixture()
      {:ok, database: database}
    end

    test "imports a simple telemetry packet", %{database: database} do
      yaml = """
      version: "1.0.0"
      description: "Test database"

      packets:
        - name: HEALTH
          apid: 100
          description: "Health telemetry"
          items:
            - name: cpu_temp
              bit_offset: 0
              bit_size: 32
              data_type: float
              endianness: big
              units: "°C"
              description: "CPU temperature"
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      assert definition_set.version == "1.0.0"
      assert definition_set.description == "Test database"
      assert definition_set.source_format == :yaml

      # Check container was created
      container = Repo.get_by(Container, definition_set_id: definition_set.id, name: "HEALTH")
      assert container.apid == 100
      assert container.description == "Health telemetry"
      assert container.byte_order == :big_endian

      # Check parameter was created
      parameter =
        Repo.get_by(Parameter, definition_set_id: definition_set.id, name: "HEALTH.cpu_temp")

      assert parameter.description == "CPU temperature"
      assert parameter.parameter_source == :telemetry

      # Check data type was created
      data_type = Repo.get(DataType, parameter.data_type_id)
      assert data_type.base_type == :float

      # Check container entry was created
      entry = Repo.get_by(ContainerEntry, container_id: container.id, parameter_id: parameter.id)
      assert entry.bit_offset == 0
      assert entry.entry_type == :parameter_ref

      # Check unit was created
      unit = Repo.get(Unit, data_type.unit_id)
      assert unit.symbol == "°C"
    end

    test "imports packet with polynomial conversion", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: SENSORS
          apid: 101
          items:
            - name: temp_raw
              bit_offset: 0
              bit_size: 16
              data_type: uint
              conversion:
                type: polynomial
                coefficients: [-40.0, 0.01, 0.000001]
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      # Check algorithm was created
      algorithm =
        Repo.get_by(Algorithm,
          definition_set_id: definition_set.id,
          name: "SENSORS_temp_raw_Type_cal"
        )

      assert algorithm.algorithm_type == :polynomial
      assert algorithm.polynomial_coefficients == [-40.0, 0.01, 0.000001]

      # Check data type references the algorithm
      data_type =
        Repo.get_by(DataType, definition_set_id: definition_set.id, name: "SENSORS_temp_raw_Type")

      assert data_type.default_calibrator_id == algorithm.id
    end

    test "imports packet with state table conversion", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: STATUS
          apid: 102
          items:
            - name: mode
              bit_offset: 0
              bit_size: 8
              data_type: uint
              conversion:
                type: state_table
                states:
                  0: "OFF"
                  1: "STANDBY"
                  2: "ACTIVE"
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      algorithm =
        Repo.get_by(Algorithm,
          definition_set_id: definition_set.id,
          name: "STATUS_mode_Type_states"
        )

      assert algorithm.algorithm_type == :state_table
      assert algorithm.state_table == %{"0" => "OFF", "1" => "STANDBY", "2" => "ACTIVE"}
    end

    test "imports packet with limits", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: THERMAL
          apid: 103
          items:
            - name: temp
              bit_offset: 0
              bit_size: 32
              data_type: float
              limits:
                red_low: -40.0
                yellow_low: -20.0
                yellow_high: 70.0
                red_high: 85.0
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      data_type =
        Repo.get_by(DataType, definition_set_id: definition_set.id, name: "THERMAL_temp_Type")

      assert data_type.default_alarm != nil
      assert data_type.default_alarm.watch_range.min_inclusive == -20.0
      assert data_type.default_alarm.watch_range.max_inclusive == 70.0
      assert data_type.default_alarm.warning_range.min_inclusive == -40.0
      assert data_type.default_alarm.warning_range.max_inclusive == 85.0
    end

    test "imports a simple command", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - name: REBOOT
          opcode: 0x01
          description: "Reboot the system"
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      command = Repo.get_by(MetaCommand, definition_set_id: definition_set.id, name: "REBOOT")
      assert command.opcode == 1
      assert command.description == "Reboot the system"
      assert command.is_hazardous == false
    end

    test "imports a hazardous command", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - name: SAFE_MODE
          opcode: 0x02
          description: "Enter safe mode"
          is_hazardous: true
          hazard_description: "Will disable normal operations"
          requires_confirmation: true
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      command = Repo.get_by(MetaCommand, definition_set_id: definition_set.id, name: "SAFE_MODE")
      assert command.is_hazardous == true
      assert command.hazard_description == "Will disable normal operations"
      assert command.requires_confirmation == true
    end

    test "imports command with parameters", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - name: SET_TEMP
          opcode: 0x10
          description: "Set target temperature"
          parameters:
            - name: target_temp
              data_type: float
              required: true
              bit_offset: 0
              bit_length: 32
              min_value: -40.0
              max_value: 85.0
              units: "°C"
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      command = Repo.get_by(MetaCommand, definition_set_id: definition_set.id, name: "SET_TEMP")
      argument = Repo.get_by(Argument, meta_command_id: command.id, name: "target_temp")

      assert argument.data_type_ref == "float"
      assert argument.required == true
      assert argument.bit_offset == 0
      assert argument.bit_length == 32
      assert argument.min_value == -40.0
      assert argument.max_value == 85.0
    end

    test "imports command with valid_values", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - name: SET_MODE
          opcode: 0x20
          parameters:
            - name: mode
              data_type: uint
              valid_values: [0, 1, 2, 3]
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      command = Repo.get_by(MetaCommand, definition_set_id: definition_set.id, name: "SET_MODE")
      argument = Repo.get_by(Argument, meta_command_id: command.id, name: "mode")

      assert argument.valid_values == ["0", "1", "2", "3"]
    end

    test "imports both packets and commands", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: status
              bit_offset: 0
              bit_size: 8
              data_type: uint

      commands:
        - name: REBOOT
          opcode: 0x01
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      assert Repo.get_by(Container, definition_set_id: definition_set.id, name: "HEALTH")
      assert Repo.get_by(MetaCommand, definition_set_id: definition_set.id, name: "REBOOT")
    end

    test "handles version override", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: status
              bit_offset: 0
              bit_size: 8
              data_type: uint
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml, version: "2.0.0")

      assert definition_set.version == "2.0.0"
    end

    test "computes source hash", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: status
              bit_offset: 0
              bit_size: 8
              data_type: uint
      """

      {:ok, definition_set} = YamlImporter.import_string(database, yaml)

      expected_hash = :crypto.hash(:sha256, yaml) |> Base.encode16(case: :lower)
      assert definition_set.source_hash == expected_hash
    end
  end

  describe "validation errors" do
    setup do
      database = database_fixture()
      {:ok, database: database}
    end

    test "rejects YAML without packets or commands", %{database: database} do
      yaml = """
      version: "1.0.0"
      """

      assert {:error, {:validation_error, _}} = YamlImporter.import_string(database, yaml)
    end

    test "rejects packet without name", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - apid: 100
          items:
            - name: status
              bit_offset: 0
              bit_size: 8
              data_type: uint
      """

      assert {:error, {:validation_error, "Packet missing 'name'"}} =
               YamlImporter.import_string(database, yaml)
    end

    test "rejects packet without items", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: HEALTH
          apid: 100
      """

      assert {:error, {:validation_error, msg}} = YamlImporter.import_string(database, yaml)
      assert msg =~ "missing 'items' list"
    end

    test "rejects item missing required fields", %{database: database} do
      yaml = """
      version: "1.0.0"

      packets:
        - name: HEALTH
          apid: 100
          items:
            - name: status
              bit_offset: 0
      """

      assert {:error, {:validation_error, msg}} = YamlImporter.import_string(database, yaml)
      assert msg =~ "missing required fields"
    end

    test "rejects hazardous command without description", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - name: DANGEROUS
          opcode: 0x01
          is_hazardous: true
      """

      assert {:error, {:validation_error, msg}} = YamlImporter.import_string(database, yaml)
      assert msg =~ "missing 'hazard_description'"
    end

    test "rejects command without name", %{database: database} do
      yaml = """
      version: "1.0.0"

      commands:
        - opcode: 0x01
      """

      assert {:error, {:validation_error, "Command missing 'name'"}} =
               YamlImporter.import_string(database, yaml)
    end
  end

  describe "import_file/3" do
    setup do
      database = database_fixture()
      {:ok, database: database}
    end

    test "imports from file path", %{database: database} do
      # Use the existing spacecraft_telemetry.yaml file
      file_path = Path.join([File.cwd!(), "priv/databases/spacecraft_telemetry.yaml"])

      if File.exists?(file_path) do
        {:ok, definition_set} = YamlImporter.import_file(database, file_path)

        assert definition_set.version == "1.0.0"
        assert definition_set.source_filename == "spacecraft_telemetry.yaml"
        assert definition_set.source_format == :yaml

        # Check that containers were created
        containers =
          Repo.all(Container) |> Enum.filter(&(&1.definition_set_id == definition_set.id))

        assert length(containers) > 0

        # Check HEALTH packet exists
        assert Repo.get_by(Container, definition_set_id: definition_set.id, name: "HEALTH")
      end
    end

    test "returns error for missing file", %{database: database} do
      assert {:error, :enoent} = YamlImporter.import_file(database, "/nonexistent/path.yaml")
    end
  end
end
