defmodule Cadence.Procedures.V2.ExecutionStrategyTest do
  use Cadence.DataCase, async: true

  alias Cadence.Procedures.V2.ExecutionStrategy
  alias Cadence.Procedures.V2.Strategies.{Assisted, Automatic, Manual}

  # Helper to create a mock step execution
  defp mock_step_exec(opts \\ []) do
    blocks = Keyword.get(opts, :blocks, [])
    signoff_roles = Keyword.get(opts, :signoff_roles, [])
    signoff_logic = Keyword.get(opts, :signoff_logic, :all)
    signoffs = Keyword.get(opts, :signoffs, [])
    block_executions = Keyword.get(opts, :block_executions, [])

    %{
      id: Ecto.UUID.generate(),
      step: %{
        id: Ecto.UUID.generate(),
        blocks: blocks,
        signoff_roles: signoff_roles,
        signoff_logic: signoff_logic
      },
      signoffs: signoffs,
      block_executions: block_executions
    }
  end

  defp mock_block(type, opts \\ []) do
    %{
      id: Ecto.UUID.generate(),
      block_type: type,
      content: Keyword.get(opts, :content, %{})
    }
  end

  describe "for_mode/1" do
    test "returns Manual strategy for :manual mode" do
      assert ExecutionStrategy.for_mode(:manual) == Manual
    end

    test "returns Assisted strategy for :assisted mode" do
      assert ExecutionStrategy.for_mode(:assisted) == Assisted
    end

    test "returns Automatic strategy for :automatic mode" do
      assert ExecutionStrategy.for_mode(:automatic) == Automatic
    end

    test "defaults to Manual for unknown modes" do
      assert ExecutionStrategy.for_mode(:unknown) == Manual
      assert ExecutionStrategy.for_mode(nil) == Manual
    end
  end

  describe "Manual strategy" do
    test "on_step_activated just acknowledges" do
      step_exec = mock_step_exec()
      assert Manual.on_step_activated(step_exec, %{}) == {:ok, %{}}
    end

    test "should_auto_run_block? returns false for all block types" do
      assert Manual.should_auto_run_block?(mock_block(:command)) == false
      assert Manual.should_auto_run_block?(mock_block(:wait_for)) == false
      assert Manual.should_auto_run_block?(mock_block(:script)) == false
      assert Manual.should_auto_run_block?(mock_block(:text_input)) == false
    end

    test "should_require_confirmation? returns true for all blocks" do
      assert Manual.should_require_confirmation?(mock_block(:command)) == true

      assert Manual.should_require_confirmation?(
               mock_block(:command, content: %{"require_confirmation" => false})
             ) == true
    end

    test "on_step_ready_to_complete always waits" do
      step_exec = mock_step_exec()
      assert Manual.on_step_ready_to_complete(step_exec, %{}) == {:wait, %{}}
    end

    test "get_default_value returns :no_default" do
      assert Manual.get_default_value(mock_block(:text_input, content: %{"default" => "test"})) ==
               :no_default
    end

    test "should_enforce_signoffs? returns true" do
      step_exec = mock_step_exec(signoff_roles: ["operator"])
      assert Manual.should_enforce_signoffs?(step_exec) == true
    end
  end

  describe "Assisted strategy" do
    test "on_step_activated runs automation for automated blocks" do
      command_block = mock_block(:command)
      wait_block = mock_block(:wait_for)
      input_block = mock_block(:text_input)

      step_exec = mock_step_exec(blocks: [command_block, wait_block, input_block])

      {:run_automation, blocks, _state} = Assisted.on_step_activated(step_exec, %{})

      # Should only include automated blocks, not input blocks
      block_types = Enum.map(blocks, & &1.block_type)
      assert :command in block_types
      assert :wait_for in block_types
      refute :text_input in block_types
    end

    test "on_step_activated just acknowledges if no automated blocks" do
      input_block = mock_block(:text_input)
      step_exec = mock_step_exec(blocks: [input_block])

      assert Assisted.on_step_activated(step_exec, %{}) == {:ok, %{}}
    end

    test "should_auto_run_block? returns true for automated block types" do
      assert Assisted.should_auto_run_block?(mock_block(:command)) == true
      assert Assisted.should_auto_run_block?(mock_block(:wait_for)) == true
      assert Assisted.should_auto_run_block?(mock_block(:script)) == true
      assert Assisted.should_auto_run_block?(mock_block(:telemetry_check)) == true
    end

    test "should_auto_run_block? returns false for input blocks" do
      assert Assisted.should_auto_run_block?(mock_block(:text_input)) == false
      assert Assisted.should_auto_run_block?(mock_block(:number_input)) == false
    end

    test "should_auto_run_block? returns false for blocks requiring confirmation" do
      block = mock_block(:command, content: %{"require_confirmation" => true})
      assert Assisted.should_auto_run_block?(block) == false
    end

    test "should_require_confirmation? respects block setting" do
      assert Assisted.should_require_confirmation?(mock_block(:command)) == false

      assert Assisted.should_require_confirmation?(
               mock_block(:command, content: %{"require_confirmation" => true})
             ) == true
    end

    test "get_default_value returns :no_default" do
      assert Assisted.get_default_value(mock_block(:text_input, content: %{"default" => "test"})) ==
               :no_default
    end

    test "should_enforce_signoffs? returns true when step has signoff roles" do
      step_exec = mock_step_exec(signoff_roles: ["operator"])
      assert Assisted.should_enforce_signoffs?(step_exec) == true
    end

    test "should_enforce_signoffs? returns false when step has no signoff roles" do
      step_exec = mock_step_exec(signoff_roles: [])
      assert Assisted.should_enforce_signoffs?(step_exec) == false
    end
  end

  describe "Automatic strategy" do
    test "on_step_activated runs all blocks" do
      command_block = mock_block(:command)
      input_block = mock_block(:text_input)

      step_exec = mock_step_exec(blocks: [command_block, input_block])

      {:run_automation, blocks, _state} = Automatic.on_step_activated(step_exec, %{})

      assert length(blocks) == 2
    end

    test "on_step_activated completes immediately if no blocks" do
      step_exec = mock_step_exec(blocks: [])
      assert Automatic.on_step_activated(step_exec, %{}) == {:complete, %{}}
    end

    test "on_automation_complete always completes" do
      step_exec = mock_step_exec()
      assert Automatic.on_automation_complete(step_exec, %{}, %{}) == {:complete, %{}}
    end

    test "should_auto_run_block? returns true for all supported block types" do
      assert Automatic.should_auto_run_block?(mock_block(:command)) == true
      assert Automatic.should_auto_run_block?(mock_block(:text_input)) == true
      assert Automatic.should_auto_run_block?(mock_block(:script)) == true
    end

    test "should_require_confirmation? always returns false" do
      assert Automatic.should_require_confirmation?(mock_block(:command)) == false

      assert Automatic.should_require_confirmation?(
               mock_block(:command, content: %{"require_confirmation" => true})
             ) == false
    end

    test "get_default_value returns default from block content" do
      block = mock_block(:text_input, content: %{"default" => "test value"})
      assert Automatic.get_default_value(block) == {:ok, "test value"}
    end

    test "get_default_value returns default_value from block content" do
      block = mock_block(:number_input, content: %{"default_value" => 42})
      assert Automatic.get_default_value(block) == {:ok, 42}
    end

    test "get_default_value returns false for checkbox without default" do
      block = mock_block(:checkbox)
      assert Automatic.get_default_value(block) == {:ok, false}
    end

    test "get_default_value returns first option for select" do
      block =
        mock_block(:select, content: %{"options" => [%{"value" => "opt1"}, %{"value" => "opt2"}]})

      assert Automatic.get_default_value(block) == {:ok, "opt1"}
    end

    test "get_default_value returns :no_default when no default available" do
      block = mock_block(:text_input, content: %{})
      assert Automatic.get_default_value(block) == :no_default
    end

    test "should_enforce_signoffs? always returns false" do
      step_exec = mock_step_exec(signoff_roles: ["operator", "lead"])
      assert Automatic.should_enforce_signoffs?(step_exec) == false
    end
  end
end
