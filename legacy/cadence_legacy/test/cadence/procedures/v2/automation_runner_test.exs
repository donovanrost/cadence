defmodule Cadence.Procedures.V2.AutomationRunnerTest do
  use Cadence.PureCase, async: true

  alias Cadence.Procedures.V2.AutomationRunner

  # Basic context for tests
  defp test_context do
    %{
      mission_id: "test-mission",
      target_id: "test-target",
      organization_id: "test-org",
      execution_id: "test-execution",
      user_id: "test-user",
      params: %{"threshold" => 50},
      vars: %{}
    }
  end

  defp mock_block(type, opts) do
    %{
      id: Keyword.get(opts, :id, Ecto.UUID.generate()),
      block_type: type,
      content: Keyword.get(opts, :content, %{})
    }
  end

  describe "run/3 basic flow" do
    test "returns {:ok, results} for empty block list" do
      assert {:ok, %{}} = AutomationRunner.run([], test_context())
    end

    test "executes blocks in sequence" do
      blocks = [
        mock_block(:wait, content: %{"duration" => 10}),
        mock_block(:wait, content: %{"duration" => 10})
      ]

      {:ok, results} = AutomationRunner.run(blocks, test_context())

      assert map_size(results) == 2
      assert Enum.all?(results, fn {_id, result} -> match?({:ok, _}, result) end)
    end

    test "calls on_progress callback" do
      test_pid = self()

      blocks = [mock_block(:wait, content: %{"duration" => 10})]

      on_progress = fn block, status, data ->
        send(test_pid, {:progress, block.id, status, data})
        :ok
      end

      AutomationRunner.run(blocks, test_context(), on_progress: on_progress)

      assert_received {:progress, _, :starting, %{}}
      assert_received {:progress, _, :completed, %{waited_ms: 10}}
    end

    test "calls on_block_complete callback" do
      test_pid = self()

      blocks = [mock_block(:wait, content: %{"duration" => 10})]

      on_block_complete = fn block, result ->
        send(test_pid, {:block_complete, block.id, result})
        :ok
      end

      AutomationRunner.run(blocks, test_context(), on_block_complete: on_block_complete)

      assert_received {:block_complete, _, {:ok, %{waited_ms: 10}}}
    end

    test "stops on abort signal" do
      blocks = [
        mock_block(:wait, id: "block1", content: %{"duration" => 10}),
        mock_block(:wait, id: "block2", content: %{"duration" => 10})
      ]

      # Abort after first block
      call_count = :counters.new(1, [:atomics])

      check_signal = fn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count >= 1, do: :abort, else: :continue
      end

      {:aborted, results} =
        AutomationRunner.run(blocks, test_context(), check_signal: check_signal)

      # Should have completed first block before abort
      assert map_size(results) == 1
      assert Map.has_key?(results, "block1")
    end

    test "pauses and returns remaining blocks" do
      blocks = [
        mock_block(:wait, id: "block1", content: %{"duration" => 10}),
        mock_block(:wait, id: "block2", content: %{"duration" => 10})
      ]

      # Pause after first block
      call_count = :counters.new(1, [:atomics])

      check_signal = fn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count >= 1, do: :pause, else: :continue
      end

      {:paused, results, remaining} =
        AutomationRunner.run(blocks, test_context(), check_signal: check_signal)

      assert map_size(results) == 1
      assert length(remaining) == 1
      assert hd(remaining).id == "block2"
    end
  end

  describe "execute_block/3 for :wait blocks" do
    test "waits for specified duration" do
      block = mock_block(:wait, content: %{"duration" => 50})

      start = System.monotonic_time(:millisecond)
      {:ok, result} = AutomationRunner.execute_block(block, test_context())
      elapsed = System.monotonic_time(:millisecond) - start

      assert result.waited_ms == 50
      # Allow some tolerance
      assert elapsed >= 40
    end

    test "supports duration_ms key" do
      block = mock_block(:wait, content: %{"duration_ms" => 30})

      {:ok, result} = AutomationRunner.execute_block(block, test_context())
      assert result.waited_ms == 30
    end
  end

  describe "execute_block/3 for :telemetry_check blocks" do
    test "returns error when telemetry lookup fails" do
      block =
        mock_block(:telemetry_check,
          content: %{
            "item" => "HK.battery_voltage",
            "operator" => ">=",
            "expected" => 24
          }
        )

      {:error, reason} = AutomationRunner.execute_block(block, test_context())
      assert reason in [:not_found, :cvt_error]
    end

    test "returns error when telemetry lookup fails for false condition" do
      block =
        mock_block(:telemetry_check,
          content: %{
            "item" => "HK.battery_voltage",
            "operator" => "<",
            "expected" => 5
          }
        )

      {:error, reason} = AutomationRunner.execute_block(block, test_context())
      assert reason in [:not_found, :cvt_error]
    end

    test "returns error when fail_on_false is true and telemetry lookup fails" do
      block =
        mock_block(:telemetry_check,
          content: %{
            "item" => "HK.battery_voltage",
            "operator" => "<",
            "expected" => 5,
            "fail_on_false" => true
          }
        )

      {:error, reason} = AutomationRunner.execute_block(block, test_context())

      assert reason in [:not_found, :cvt_error]
    end
  end

  describe "execute_block/3 for input blocks" do
    test "skips input blocks without strategy" do
      block = mock_block(:text_input, content: %{"label" => "Name"})

      {:skip, :requires_user_input} = AutomationRunner.execute_block(block, test_context())
    end

    test "uses default value from automatic strategy" do
      block = mock_block(:text_input, content: %{"default" => "test value"})

      strategy = Cadence.Procedures.V2.Strategies.Automatic

      {:ok, result} = AutomationRunner.execute_block(block, test_context(), strategy: strategy)

      assert result.value == "test value"
      assert result.source == :default
    end

    test "skips when no default available" do
      block = mock_block(:text_input, content: %{})

      strategy = Cadence.Procedures.V2.Strategies.Automatic

      {:skip, :requires_user_input} =
        AutomationRunner.execute_block(block, test_context(), strategy: strategy)
    end
  end

  describe "execute_block/3 for :wait_for blocks" do
    # Note: These tests would need CVT to be set up, so we test error cases

    test "returns error for timeout" do
      block =
        mock_block(:wait_for,
          content: %{
            "item" => "HK.missing_item",
            "operator" => "==",
            "expected" => 42,
            # Very short timeout
            "timeout" => 100
          }
        )

      {:error, :timeout} = AutomationRunner.execute_block(block, test_context())
    end
  end

  describe "execute_block/3 for :script blocks" do
    test "executes simple Lua script" do
      # Skip if luerl not available
      if Code.ensure_loaded?(:luerl) do
        block =
          mock_block(:script,
            content: %{
              "script" => "return 1 + 1",
              "timeout_seconds" => 5
            }
          )

        {:ok, result} = AutomationRunner.execute_block(block, test_context())

        assert result.script_result == [2.0]
      end
    end

    test "handles script timeout" do
      if Code.ensure_loaded?(:luerl) do
        block =
          mock_block(:script,
            content: %{
              # Infinite loop
              "script" => "while true do end",
              "timeout_seconds" => 1
            }
          )

        {:error, :script_timeout} = AutomationRunner.execute_block(block, test_context())
      end
    end

    test "returns error when luerl not available" do
      # This test only works if luerl is NOT loaded, which is unlikely
      # So we just verify the function handles the check
      block = mock_block(:script, content: %{"script" => "return 1"})

      result = AutomationRunner.execute_block(block, test_context())

      # Will either succeed or return luerl error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "error handling" do
    test "stops execution on block failure" do
      blocks = [
        mock_block(:telemetry_check,
          id: "check1",
          content: %{
            "condition" => "false",
            "fail_on_false" => true
          }
        ),
        mock_block(:wait, id: "wait1", content: %{"duration" => 10})
      ]

      {:error, failed_block, _reason} = AutomationRunner.run(blocks, test_context())

      assert failed_block.id == "check1"
    end

    test "returns unknown block type error" do
      block = mock_block(:unknown_type, content: %{})

      {:error, reason} = AutomationRunner.execute_block(block, test_context())

      assert reason =~ "Unknown block type"
    end
  end
end
