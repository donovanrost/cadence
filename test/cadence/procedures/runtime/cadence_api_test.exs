defmodule Cadence.Procedures.Runtime.CadenceApiTest do
  @moduledoc """
  Tests for CadenceApi - the Lua bridge for procedures.

  Tests focus on:
  - API installation into Luerl state
  - Function behavior and message passing
  - Condition evaluation for telemetry
  - Data conversion between Lua and Elixir
  """
  use ExUnit.Case, async: true

  alias Cadence.Procedures.Runtime.CadenceApi

  # Create a test context for API installation
  defp test_context(overrides \\ %{}) do
    Map.merge(
      %{
        mission_id: "test-mission",
        organization_id: "test-org",
        target_id: "test-target",
        execution_id: "test-execution",
        execution_pid: self(),
        params: %{"key1" => "value1", "key2" => 42}
      },
      overrides
    )
  end

  describe "install/2" do
    test "installs cadence namespace into Luerl state" do
      lua_state = :luerl.init()
      context = test_context()

      installed_state = CadenceApi.install(lua_state, context)

      # Should be able to access cadence.mission_id
      {:ok, [mission_id], _} = :luerl.do("return cadence.mission_id", installed_state)
      assert mission_id == "test-mission"
    end

    test "installs params from context" do
      lua_state = :luerl.init()
      context = test_context(%{params: %{"name" => "TestProc", "count" => 5}})

      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [name], _} = :luerl.do("return cadence.params.name", installed_state)
      {:ok, [count], _} = :luerl.do("return cadence.params.count", installed_state)

      assert name == "TestProc"
      assert count == 5.0  # Lua numbers are floats
    end

    test "installs target_id and execution_id" do
      lua_state = :luerl.init()
      context = test_context()

      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [target_id], _} = :luerl.do("return cadence.target_id", installed_state)
      {:ok, [exec_id], _} = :luerl.do("return cadence.execution_id", installed_state)

      assert target_id == "test-target"
      assert exec_id == "test-execution"
    end
  end

  describe "cadence.log" do
    test "sends log message to execution process" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, _, _} = :luerl.do("cadence.log('Hello from Lua!')", installed_state)

      assert_receive {:log, :info, "Hello from Lua!"}
    end

    test "supports log level as first argument" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, _, _} = :luerl.do("cadence.log('warn', 'Warning message')", installed_state)

      assert_receive {:log, :warn, "Warning message"}
    end
  end

  describe "cadence.wait" do
    test "sends waiting message to execution process" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Short wait to avoid slow tests
      spawn(fn ->
        :luerl.do("cadence.wait(50)", installed_state)
      end)

      assert_receive {:waiting, 50}, 200
    end
  end

  describe "cadence.checkpoint" do
    test "sends checkpoint message to execution process" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, _, _} = :luerl.do("cadence.checkpoint('step_1_complete')", installed_state)

      assert_receive {:checkpoint, "step_1_complete"}
    end
  end

  describe "cadence.abort" do
    test "sends abort_requested message to execution process" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, _, _} = :luerl.do("cadence.abort('User requested abort')", installed_state)

      assert_receive {:abort_requested, "User requested abort"}
    end

    test "uses default message when none provided" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, _, _} = :luerl.do("cadence.abort()", installed_state)

      assert_receive {:abort_requested, "Procedure aborted"}
    end
  end

  describe "cadence.telemetry.get" do
    # Note: These tests require the CVT ETS table which isn't available in unit tests
    # We verify the API is installed and callable

    @tag :skip
    test "returns nil when telemetry item not found" do
      # Skipped: Requires CurrentValueTable ETS table
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [result], _} =
        :luerl.do("return cadence.telemetry.get('NONEXISTENT.item')", installed_state)

      assert result == nil
    end

    test "telemetry.get function is installed" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Verify the function exists by checking its type
      {:ok, [result], _} = :luerl.do("return type(cadence.telemetry.get)", installed_state)
      assert result == "function"
    end
  end

  describe "cadence.telemetry.wait_for" do
    # Note: These tests require the CVT ETS table which isn't available in unit tests

    test "wait_for function is installed" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Verify the function exists by checking its type
      {:ok, [result], _} = :luerl.do("return type(cadence.telemetry.wait_for)", installed_state)
      assert result == "function"
    end

    @tag :skip
    test "sends waiting_for_telemetry message to execution process" do
      # Skipped: Requires CurrentValueTable ETS table
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Run in separate process so it doesn't block test
      spawn(fn ->
        :luerl.do("cadence.telemetry.wait_for('TEMP.value', '>', 50, 100)", installed_state)
      end)

      assert_receive {:waiting_for_telemetry, "TEMP.value", ">", 50.0}, 200
    end

    @tag :skip
    test "returns false when timeout occurs without condition met" do
      # Skipped: Requires CurrentValueTable ETS table
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [result], _} =
        :luerl.do("return cadence.telemetry.wait_for('TEMP.value', '==', 100, 50)", installed_state)

      assert result == false
    end
  end

  describe "cadence.command.send" do
    # Note: These tests require CommandDispatcher GenServer which isn't available in unit tests

    test "command.send function is installed" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [result], _} = :luerl.do("return type(cadence.command.send)", installed_state)
      assert result == "function"
    end

    test "command.send_and_verify function is installed" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [result], _} = :luerl.do("return type(cadence.command.send_and_verify)", installed_state)
      assert result == "function"
    end

    @tag :skip
    test "sends command_failed message when dispatch fails" do
      # Skipped: Requires CommandDispatcher GenServer
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [result], _} =
        :luerl.do("return cadence.command.send('NONEXISTENT_CMD', {})", installed_state)

      assert result == false
      assert_receive {:command_failed, "NONEXISTENT_CMD", _reason}
    end
  end

  describe "condition evaluation" do
    # The evaluate_condition function is internal - test via Lua type checks

    test "telemetry namespace is properly structured" do
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Verify telemetry is a table with expected functions
      {:ok, [result], _} = :luerl.do("return type(cadence.telemetry)", installed_state)
      assert result == "table"

      {:ok, [get_type], _} = :luerl.do("return type(cadence.telemetry.get)", installed_state)
      {:ok, [wait_type], _} = :luerl.do("return type(cadence.telemetry.wait_for)", installed_state)

      assert get_type == "function"
      assert wait_type == "function"
    end
  end

  describe "data conversion" do
    test "params table is accessible from Lua" do
      lua_state = :luerl.init()
      context = test_context(%{params: %{"voltage" => 3.3, "enabled" => true}})
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [voltage], _} = :luerl.do("return cadence.params.voltage", installed_state)
      {:ok, [enabled], _} = :luerl.do("return cadence.params.enabled", installed_state)

      assert voltage == 3.3
      assert enabled == true
    end

    test "handles nested params in context" do
      lua_state = :luerl.init()

      context =
        test_context(%{
          params: %{
            "sensor" => %{"id" => "S1", "threshold" => 100},
            "debug" => true
          }
        })

      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [sensor_id], _} = :luerl.do("return cadence.params.sensor.id", installed_state)
      {:ok, [threshold], _} = :luerl.do("return cadence.params.sensor.threshold", installed_state)
      {:ok, [debug], _} = :luerl.do("return cadence.params.debug", installed_state)

      assert sensor_id == "S1"
      assert threshold == 100.0
      assert debug == true
    end
  end

  describe "item name parsing" do
    @tag :skip
    test "cadence.telemetry.get handles dotted item names" do
      # Skipped: Requires CurrentValueTable ETS table
      lua_state = :luerl.init()
      context = test_context()
      installed_state = CadenceApi.install(lua_state, context)

      # Both formats should be callable (will return nil since no CVT)
      {:ok, [result1], _} =
        :luerl.do("return cadence.telemetry.get('PACKET.item')", installed_state)

      {:ok, [result2], _} = :luerl.do("return cadence.telemetry.get('item')", installed_state)

      assert result1 == nil
      assert result2 == nil
    end
  end

  describe "allow_hazardous_commands" do
    test "context flag is supported" do
      lua_state = :luerl.init()
      # Verify allow_hazardous_commands can be set in context
      context = test_context(%{allow_hazardous_commands: true})
      installed_state = CadenceApi.install(lua_state, context)

      # Command API should still be installed
      {:ok, [result], _} = :luerl.do("return type(cadence.command.send)", installed_state)
      assert result == "function"
    end

    @tag :skip
    test "context flag affects command execution" do
      # Skipped: Requires CommandDispatcher GenServer
      lua_state = :luerl.init()
      context = test_context(%{allow_hazardous_commands: true})
      installed_state = CadenceApi.install(lua_state, context)

      {:ok, [_result], _} =
        :luerl.do("return cadence.command.send('HAZARDOUS_CMD', {})", installed_state)

      assert_receive {:command_failed, "HAZARDOUS_CMD", _}
    end
  end
end
