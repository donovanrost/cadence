defmodule Cadence.CommandsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Commands
  alias Cadence.Commands.{CommandDefinition, CommandParameter, CommandLog}

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    # Create a database for the definition set
    database =
      %Cadence.MissionDatabase.Database{}
      |> Cadence.MissionDatabase.Database.changeset(%{
        mission_id: mission.id,
        name: "Test Database",
        slug: "test-db-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert!()

    # Create definition set for commands (uses mdb_definition_sets table)
    definition_set =
      %Cadence.MissionDatabase.DefinitionSet{}
      |> Cadence.MissionDatabase.DefinitionSet.changeset(%{
        organization_id: org.id,
        database_id: database.id,
        version: "1.0.0",
        source_format: :yaml
      })
      |> Repo.insert!()

    %{
      org: org,
      mission: mission,
      database: database,
      definition_set: definition_set
    }
  end

  # ============================================================================
  # Command Definition CRUD
  # ============================================================================

  describe "create_command/1" do
    test "creates a command with valid attrs", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SET_MODE",
        opcode: 0x10,
        description: "Sets the spacecraft operating mode"
      }

      assert {:ok, %CommandDefinition{} = cmd} = Commands.create_command(attrs)
      assert cmd.name == "SET_MODE"
      assert cmd.opcode == 0x10
      assert cmd.is_hazardous == false
      assert cmd.requires_confirmation == false
    end

    test "creates a hazardous command", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "SAFE_MODE",
        opcode: 0x01,
        is_hazardous: true,
        hazard_description: "Will disable normal operations",
        requires_confirmation: true
      }

      assert {:ok, %CommandDefinition{} = cmd} = Commands.create_command(attrs)
      assert cmd.is_hazardous == true
      assert cmd.hazard_description == "Will disable normal operations"
      assert cmd.requires_confirmation == true
    end

    test "creates a command with phase restrictions", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "DEPLOY_SOLAR_ARRAY",
        opcode: 0x20,
        allowed_phases: ["commissioning", "operations"]
      }

      assert {:ok, %CommandDefinition{} = cmd} = Commands.create_command(attrs)
      assert cmd.allowed_phases == ["commissioning", "operations"]
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Commands.create_command(%{name: "TEST"})
      assert "can't be blank" in errors_on(changeset).organization_id
    end
  end

  describe "get_command/1 and get_command!/1" do
    test "returns command by ID", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "GET_TEST")

      assert fetched = Commands.get_command(cmd.id)
      assert fetched.id == cmd.id
      assert fetched.name == "GET_TEST"
    end

    test "returns nil for non-existent ID" do
      assert Commands.get_command(Ecto.UUID.generate()) == nil
    end

    test "raises for non-existent ID with get_command!", %{} do
      assert_raise Ecto.NoResultsError, fn ->
        Commands.get_command!(Ecto.UUID.generate())
      end
    end

    test "preloads command_parameters", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "WITH_PARAMS")

      {:ok, _param} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "mode",
          data_type: "uint",
          bit_offset: 0,
          bit_length: 8
        })

      fetched = Commands.get_command(cmd.id)
      assert length(fetched.command_parameters) == 1
      assert hd(fetched.command_parameters).name == "mode"
    end
  end

  describe "get_command_by_name/2" do
    test "returns command by name", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "UNIQUE_CMD")

      assert fetched = Commands.get_command_by_name(definition_set.id, "UNIQUE_CMD")
      assert fetched.id == cmd.id
    end

    test "returns nil for non-existent name", %{definition_set: definition_set} do
      assert Commands.get_command_by_name(definition_set.id, "NONEXISTENT") == nil
    end
  end

  describe "get_command_by_opcode/2" do
    test "returns command by opcode", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "OPCODE_TEST", opcode: 0x42)

      assert fetched = Commands.get_command_by_opcode(definition_set.id, 0x42)
      assert fetched.id == cmd.id
    end

    test "returns nil for non-existent opcode", %{definition_set: definition_set} do
      assert Commands.get_command_by_opcode(definition_set.id, 0xFF) == nil
    end
  end

  describe "update_command/2" do
    test "updates command attributes", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "TO_UPDATE")

      assert {:ok, updated} =
               Commands.update_command(cmd, %{
                 description: "Updated description",
                 is_hazardous: true,
                 hazard_description: "Test hazard"
               })

      assert updated.description == "Updated description"
      assert updated.is_hazardous == true
      assert updated.hazard_description == "Test hazard"
    end

    test "returns error for invalid update", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "INVALID_UPDATE")

      # Try to set name to nil (required field)
      assert {:error, _changeset} = Commands.update_command(cmd, %{name: nil})
    end
  end

  describe "delete_command/1" do
    test "deletes command", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "TO_DELETE")

      assert {:ok, _} = Commands.delete_command(cmd)
      assert Commands.get_command(cmd.id) == nil
    end
  end

  describe "list_commands/1" do
    test "returns all commands for definition set", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd1} = create_test_command(org, mission, definition_set, "ALPHA_CMD")
      {:ok, cmd2} = create_test_command(org, mission, definition_set, "BETA_CMD")

      commands = Commands.list_commands(definition_set.id)

      assert length(commands) == 2
      names = Enum.map(commands, & &1.name)
      # Should be sorted alphabetically
      assert names == ["ALPHA_CMD", "BETA_CMD"]
    end
  end

  describe "list_hazardous_commands/1" do
    test "returns only hazardous commands", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, _safe} = create_test_command(org, mission, definition_set, "SAFE_CMD")

      {:ok, _hazardous} =
        create_test_command(org, mission, definition_set, "HAZARDOUS_CMD",
          is_hazardous: true,
          hazard_description: "Can cause damage"
        )

      commands = Commands.list_hazardous_commands(definition_set.id)

      assert length(commands) == 1
      assert hd(commands).name == "HAZARDOUS_CMD"
    end
  end

  describe "list_commands_for_phase/2" do
    test "returns commands allowed in phase", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, _any_phase} = create_test_command(org, mission, definition_set, "ANY_PHASE")

      {:ok, _ops_only} =
        create_test_command(org, mission, definition_set, "OPS_ONLY",
          allowed_phases: ["operational"]
        )

      {:ok, _commissioning_only} =
        create_test_command(org, mission, definition_set, "COMMISSIONING_ONLY",
          allowed_phases: ["commissioning"]
        )

      # In operational phase
      ops_commands = Commands.list_commands_for_phase(definition_set.id, "operational")
      ops_names = Enum.map(ops_commands, & &1.name)

      # Should include ANY_PHASE (no restrictions) and OPS_ONLY
      assert "ANY_PHASE" in ops_names
      assert "OPS_ONLY" in ops_names
      refute "COMMISSIONING_ONLY" in ops_names
    end
  end

  # ============================================================================
  # Command Parameter Operations
  # ============================================================================

  describe "create_parameter/1" do
    test "creates parameter with valid attrs", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "PARAM_CMD")

      attrs = %{
        command_definition_id: cmd.id,
        name: "temperature",
        data_type: "float",
        bit_offset: 0,
        bit_length: 32,
        required: true,
        min_value: -40.0,
        max_value: 85.0,
        units: "°C"
      }

      assert {:ok, %CommandParameter{} = param} = Commands.create_parameter(attrs)
      assert param.name == "temperature"
      assert param.data_type == "float"
      assert param.min_value == -40.0
      assert param.max_value == 85.0
    end

    test "creates enum parameter with valid_values", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "ENUM_CMD")

      attrs = %{
        command_definition_id: cmd.id,
        name: "mode",
        data_type: "enum",
        bit_offset: 0,
        bit_length: 8,
        valid_values: ["SAFE", "NORMAL", "SCIENCE"]
      }

      assert {:ok, %CommandParameter{} = param} = Commands.create_parameter(attrs)
      assert param.valid_values == ["SAFE", "NORMAL", "SCIENCE"]
    end
  end

  describe "update_parameter/2" do
    test "updates parameter", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "UPDATE_PARAM_CMD")
      {:ok, param} = create_test_parameter(cmd, "old_name")

      assert {:ok, updated} = Commands.update_parameter(param, %{name: "new_name"})
      assert updated.name == "new_name"
    end
  end

  describe "delete_parameter/1" do
    test "deletes parameter", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "DELETE_PARAM_CMD")
      {:ok, param} = create_test_parameter(cmd, "to_delete")

      assert {:ok, _} = Commands.delete_parameter(param)
      assert Commands.get_parameter(param.id) == nil
    end
  end

  describe "list_parameters/1" do
    test "returns parameters ordered by display_order", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "LIST_PARAMS_CMD")
      {:ok, _p1} = create_test_parameter(cmd, "third", display_order: 3)
      {:ok, _p2} = create_test_parameter(cmd, "first", display_order: 1)
      {:ok, _p3} = create_test_parameter(cmd, "second", display_order: 2)

      params = Commands.list_parameters(cmd.id)
      names = Enum.map(params, & &1.name)

      assert names == ["first", "second", "third"]
    end
  end

  # ============================================================================
  # Parameter Validation
  # ============================================================================

  describe "validate_parameters/2" do
    test "returns :ok when all validations pass", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "VALID_PARAMS_CMD")

      {:ok, _} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "value",
          data_type: "uint",
          bit_offset: 0,
          bit_length: 8,
          required: true
        })

      assert :ok = Commands.validate_parameters(cmd, %{"value" => 42})
    end

    test "returns error for missing required parameter", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "MISSING_PARAM_CMD")

      {:ok, _} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "required_value",
          data_type: "uint",
          bit_offset: 0,
          bit_length: 8,
          required: true
        })

      assert {:error, errors} = Commands.validate_parameters(cmd, %{})
      assert {"required_value", "is required"} in errors
    end

    test "returns error for unknown parameter", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "UNKNOWN_PARAM_CMD")

      assert {:error, errors} = Commands.validate_parameters(cmd, %{"unknown" => 123})
      assert {"unknown", "unknown parameter"} in errors
    end

    test "validates numeric range", %{org: org, mission: mission, definition_set: definition_set} do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "RANGE_CMD")

      {:ok, _} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "temp",
          data_type: "float",
          bit_offset: 0,
          bit_length: 32,
          required: true,
          min_value: 0.0,
          max_value: 100.0
        })

      # Within range
      assert :ok = Commands.validate_parameters(cmd, %{"temp" => 50.0})

      # Below range
      assert {:error, errors} = Commands.validate_parameters(cmd, %{"temp" => -10.0})
      assert Enum.any?(errors, fn {name, _} -> name == "temp" end)

      # Above range
      assert {:error, errors} = Commands.validate_parameters(cmd, %{"temp" => 150.0})
      assert Enum.any?(errors, fn {name, _} -> name == "temp" end)
    end

    test "accepts atom keys in params", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "ATOM_KEYS_CMD")

      {:ok, _} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "mode",
          data_type: "uint",
          bit_offset: 0,
          bit_length: 8,
          required: true
        })

      # Atom key should work
      assert :ok = Commands.validate_parameters(cmd, %{mode: 1})
    end

    test "allows optional parameters to be missing", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, cmd} = create_test_command(org, mission, definition_set, "OPTIONAL_CMD")

      {:ok, _} =
        Commands.create_parameter(%{
          command_definition_id: cmd.id,
          name: "optional_value",
          data_type: "uint",
          bit_offset: 0,
          bit_length: 8,
          required: false,
          default_value: "0"
        })

      # Should pass with empty params
      assert :ok = Commands.validate_parameters(cmd, %{})
    end
  end

  # ============================================================================
  # Bulk Operations
  # ============================================================================

  describe "create_command_with_parameters/2" do
    test "creates command and parameters in transaction", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      command_attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        definition_set_id: definition_set.id,
        name: "BULK_CMD",
        opcode: 0x50
      }

      params_attrs = [
        %{name: "param1", data_type: "uint", bit_offset: 0, bit_length: 8},
        %{name: "param2", data_type: "uint", bit_offset: 8, bit_length: 16}
      ]

      assert {:ok, cmd} = Commands.create_command_with_parameters(command_attrs, params_attrs)
      assert cmd.name == "BULK_CMD"
      assert length(cmd.command_parameters) == 2
    end
  end

  describe "count_commands/1" do
    test "counts commands in definition set", %{
      org: org,
      mission: mission,
      definition_set: definition_set
    } do
      {:ok, _} = create_test_command(org, mission, definition_set, "COUNT_1")
      {:ok, _} = create_test_command(org, mission, definition_set, "COUNT_2")
      {:ok, _} = create_test_command(org, mission, definition_set, "COUNT_3")

      assert Commands.count_commands(definition_set.id) == 3
    end
  end

  # ============================================================================
  # Command Log Operations
  # ============================================================================

  describe "list_command_logs/2" do
    test "returns empty list when no logs exist", %{mission: mission} do
      assert Commands.list_command_logs(mission.id) == []
    end

    test "respects limit option", %{mission: mission} do
      # Create some logs
      for i <- 1..5 do
        create_command_log(mission.id, "CMD_#{i}")
      end

      logs = Commands.list_command_logs(mission.id, limit: 3)
      assert length(logs) == 3
    end

    test "filters by status", %{mission: mission} do
      create_command_log(mission.id, "SENT_CMD", status: "sent")
      create_command_log(mission.id, "ERROR_CMD", status: "error")

      sent_logs = Commands.list_command_logs(mission.id, status: "sent")
      assert length(sent_logs) == 1
      assert hd(sent_logs).command_name == "SENT_CMD"
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_command(org, mission, definition_set, name, opts \\ []) do
    attrs = %{
      organization_id: org.id,
      mission_id: mission.id,
      definition_set_id: definition_set.id,
      name: name,
      opcode: Keyword.get(opts, :opcode, :rand.uniform(255)),
      is_hazardous: Keyword.get(opts, :is_hazardous, false),
      hazard_description: Keyword.get(opts, :hazard_description),
      allowed_phases: Keyword.get(opts, :allowed_phases, [])
    }

    Commands.create_command(attrs)
  end

  defp create_test_parameter(cmd, name, opts \\ []) do
    attrs = %{
      command_definition_id: cmd.id,
      name: name,
      data_type: Keyword.get(opts, :data_type, "uint"),
      bit_offset: Keyword.get(opts, :bit_offset, 0),
      bit_length: Keyword.get(opts, :bit_length, 8),
      display_order: Keyword.get(opts, :display_order, 0)
    }

    Commands.create_parameter(attrs)
  end

  defp create_command_log(mission_id, name, opts \\ []) do
    # Get organization_id from mission
    mission = Repo.get!(Cadence.Missions.Mission, mission_id)

    %CommandLog{}
    |> CommandLog.changeset(%{
      organization_id: mission.organization_id,
      mission_id: mission_id,
      command_name: name,
      status: Keyword.get(opts, :status, "sent"),
      sent_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end
end
