defmodule Cadence.Procedures.Dag.ExecutorTest do
  use ExUnit.Case, async: true

  alias Cadence.Procedures.Dag.Executor

  # A simple test executor that just returns success and tracks calls
  defp simple_executor(results \\ %{}) do
    test_pid = self()

    fn step_name, step_def, context ->
      send(test_pid, {:step_executed, step_name, step_def, context})

      case Map.get(results, step_name, :ok) do
        :ok -> {:ok, %{step: step_name}}
        :skip -> {:skip, "Skipped by test"}
        {:error, reason} -> {:error, reason}
        result -> result
      end
    end
  end

  # Executor that tracks execution order with timing
  defp tracking_executor(delays \\ %{}) do
    test_pid = self()

    fn step_name, _step_def, _context ->
      # Apply any configured delay
      delay = Map.get(delays, step_name, 0)
      if delay > 0, do: Process.sleep(delay)

      send(test_pid, {:step_completed, step_name, System.monotonic_time(:millisecond)})
      {:ok, %{step: step_name}}
    end
  end

  describe "execute/4 basic execution" do
    test "executes single step" do
      steps = %{
        "only_step" => %{"type" => "log", "message" => "Hello"}
      }

      {:ok, result} = Executor.execute(steps, simple_executor(), %{})

      assert result.status == :completed
      assert "only_step" in result.completed_steps
      assert_received {:step_executed, "only_step", _, _}
    end

    test "executes steps in dependency order" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      {:ok, result} = Executor.execute(steps, tracking_executor(), %{})

      assert result.status == :completed
      assert length(result.completed_steps) == 3

      # Verify execution order via messages (times can be equal for fast execution, so use <=)
      assert_received {:step_completed, "step_a", time_a}
      assert_received {:step_completed, "step_b", time_b}
      assert_received {:step_completed, "step_c", time_c}

      assert time_a <= time_b
      assert time_b <= time_c
    end

    test "executes parallel branches concurrently" do
      steps = %{
        "init" => %{"type" => "log", "message" => "init"},
        "branch_a" => %{"type" => "wait", "duration" => 50, "depends_on" => ["init"]},
        "branch_b" => %{"type" => "wait", "duration" => 50, "depends_on" => ["init"]},
        "join" => %{"type" => "log", "message" => "join", "depends_on" => ["branch_a", "branch_b"]}
      }

      # Both branches have same delay, so should run in parallel
      delays = %{"branch_a" => 50, "branch_b" => 50}

      start_time = System.monotonic_time(:millisecond)
      {:ok, result} = Executor.execute(steps, tracking_executor(delays), %{})
      total_time = System.monotonic_time(:millisecond) - start_time

      assert result.status == :completed
      assert length(result.completed_steps) == 4

      # If parallel, total time should be ~100ms (init + parallel branches + join)
      # If sequential, would be ~150ms (init + branch_a + branch_b + join)
      # Give some margin for test execution overhead
      assert total_time < 180
    end

    test "passes context to step executor" do
      steps = %{
        "step_a" => %{"type" => "log"}
      }

      context = %{mission_id: "m1", target_id: "t1", params: %{"foo" => "bar"}}

      {:ok, _result} = Executor.execute(steps, simple_executor(), context)

      assert_received {:step_executed, "step_a", _, received_context}
      assert received_context.mission_id == "m1"
      assert received_context.target_id == "t1"
      assert received_context.params == %{"foo" => "bar"}
    end
  end

  describe "execute/4 failure handling" do
    test "abort mode stops execution on failure" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      results = %{"step_b" => {:error, "Test failure"}}

      # When on_step_failure is :abort, the executor aborts immediately
      {:error, :aborted} =
        Executor.execute(steps, simple_executor(results), %{}, on_step_failure: :abort)

      # step_a should have been executed, step_b failed, step_c never started
      assert_received {:step_executed, "step_a", _, _}
      assert_received {:step_executed, "step_b", _, _}
      refute_received {:step_executed, "step_c", _, _}
    end

    test "continue mode allows independent branches to complete" do
      steps = %{
        "init" => %{"type" => "log"},
        "branch_a" => %{"type" => "log", "depends_on" => ["init"]},
        "branch_b" => %{"type" => "log", "depends_on" => ["init"]},
        "after_a" => %{"type" => "log", "depends_on" => ["branch_a"]},
        "after_b" => %{"type" => "log", "depends_on" => ["branch_b"]}
      }

      # branch_a fails, but branch_b should continue
      results = %{"branch_a" => {:error, "Test failure"}}

      {:ok, result} =
        Executor.execute(steps, simple_executor(results), %{}, on_step_failure: :continue)

      assert result.status == :completed_with_failures
      assert "init" in result.completed_steps
      assert "branch_a" in result.failed_steps
      assert "after_a" in result.blocked_steps
      assert "branch_b" in result.completed_steps
      assert "after_b" in result.completed_steps
    end

    test "step-level on_fail overrides default" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"], "on_fail" => "continue"},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      results = %{"step_b" => {:error, "Test failure"}}

      # Step-level on_fail: continue prevents abort signal, but DAG-level default is :abort
      # so the final result is still {:error, {:steps_failed, ...}}
      {:error, {:steps_failed, result}} =
        Executor.execute(steps, simple_executor(results), %{}, on_step_failure: :abort)

      # But the key difference from pure abort is that step_c was blocked (not cancelled mid-run)
      assert "step_a" in result.completed_steps
      assert "step_b" in result.failed_steps
      assert "step_c" in result.blocked_steps

      # Unlike pure abort mode, step_c was allowed to be blocked rather than aborted entirely
      assert_received {:step_executed, "step_a", _, _}
      assert_received {:step_executed, "step_b", _, _}
      refute_received {:step_executed, "step_c", _, _}
    end

    test "blocks dependent steps when dependency fails" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_d" => %{"type" => "log", "depends_on" => ["step_c"]}
      }

      results = %{"step_b" => {:error, "Test failure"}}

      {:ok, result} =
        Executor.execute(steps, simple_executor(results), %{}, on_step_failure: :continue)

      assert "step_a" in result.completed_steps
      assert "step_b" in result.failed_steps
      assert "step_c" in result.blocked_steps
      assert "step_d" in result.blocked_steps
    end
  end

  describe "execute/4 skipping" do
    test "handles skipped steps" do
      steps = %{
        "step_a" => %{"type" => "log", "message" => "a"},
        "step_b" => %{"type" => "check", "condition" => "true", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "message" => "c", "depends_on" => ["step_b"]}
      }

      results = %{"step_b" => :skip}

      {:ok, result} = Executor.execute(steps, simple_executor(results), %{})

      assert result.status == :completed
      assert "step_a" in result.completed_steps
      assert "step_b" in result.skipped_steps
      assert "step_c" in result.completed_steps
    end

    test "skipped dependencies allow dependents to run" do
      steps = %{
        "optional_check" => %{"type" => "check", "condition" => "false"},
        "main_work" => %{"type" => "log", "message" => "work", "depends_on" => ["optional_check"]}
      }

      results = %{"optional_check" => :skip}

      {:ok, result} = Executor.execute(steps, simple_executor(results), %{})

      assert "optional_check" in result.skipped_steps
      assert "main_work" in result.completed_steps
    end
  end

  describe "execute/4 validation" do
    test "rejects invalid DAG with cycle" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["step_b"]},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      {:error, {:validation_failed, reasons}} =
        Executor.execute(steps, simple_executor(), %{})

      assert Enum.any?(reasons, &String.contains?(&1, "Cycle"))
    end

    test "rejects invalid dependencies" do
      steps = %{
        "step_a" => %{"type" => "log", "depends_on" => ["nonexistent"]}
      }

      {:error, {:validation_failed, reasons}} =
        Executor.execute(steps, simple_executor(), %{})

      assert Enum.any?(reasons, &String.contains?(&1, "non-existent"))
    end
  end

  describe "execute/4 resume support" do
    test "skips pre-completed steps on resume" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]},
        "step_c" => %{"type" => "log", "depends_on" => ["step_b"]}
      }

      # Pretend step_a was already completed
      {:ok, result} =
        Executor.execute(steps, simple_executor(), %{}, completed_steps: ["step_a"])

      assert result.status == :completed
      assert "step_a" in result.completed_steps
      assert "step_b" in result.completed_steps
      assert "step_c" in result.completed_steps

      # step_a should not have been re-executed
      refute_received {:step_executed, "step_a", _, _}
      assert_received {:step_executed, "step_b", _, _}
      assert_received {:step_executed, "step_c", _, _}
    end
  end

  describe "execute/4 status callbacks" do
    test "calls status callback for step state changes" do
      steps = %{
        "step_a" => %{"type" => "log"},
        "step_b" => %{"type" => "log", "depends_on" => ["step_a"]}
      }

      test_pid = self()

      on_status_change = fn step_name, status, data ->
        send(test_pid, {:status_change, step_name, status, data})
      end

      {:ok, _result} =
        Executor.execute(steps, simple_executor(), %{}, on_status_change: on_status_change)

      # Should receive running and completed for each step
      assert_received {:status_change, "step_a", :running, _}
      assert_received {:status_change, "step_a", :completed, _}
      assert_received {:status_change, "step_b", :running, _}
      assert_received {:status_change, "step_b", :completed, _}
    end
  end

  describe "execute/4 concurrency limits" do
    test "limits concurrent execution with max_concurrency" do
      # Create 4 independent steps that would run in parallel without limits
      steps = %{
        "parallel_1" => %{"type" => "wait", "duration" => 100},
        "parallel_2" => %{"type" => "wait", "duration" => 100},
        "parallel_3" => %{"type" => "wait", "duration" => 100},
        "parallel_4" => %{"type" => "wait", "duration" => 100}
      }

      test_pid = self()
      concurrent_count = :counters.new(1, [:atomics])

      executor = fn step_name, _step_def, _context ->
        # Increment concurrent count
        :counters.add(concurrent_count, 1, 1)
        current = :counters.get(concurrent_count, 1)
        send(test_pid, {:concurrency, step_name, current})

        # Small delay to overlap execution
        Process.sleep(20)

        # Decrement concurrent count
        :counters.sub(concurrent_count, 1, 1)
        {:ok, %{step: step_name}}
      end

      {:ok, result} = Executor.execute(steps, executor, %{}, max_concurrency: 2)

      assert result.status == :completed
      assert length(result.completed_steps) == 4

      # Collect all concurrency readings
      readings =
        Enum.map(1..4, fn _ ->
          receive do
            {:concurrency, _step, count} -> count
          after
            1000 -> flunk("Timeout waiting for concurrency message")
          end
        end)

      # With max_concurrency: 2, we should never have more than 2 concurrent
      assert Enum.max(readings) <= 2
    end

    test "unlimited concurrency is default" do
      # With 3 independent steps and unlimited concurrency, all should start together
      steps = %{
        "parallel_1" => %{"type" => "wait", "duration" => 100},
        "parallel_2" => %{"type" => "wait", "duration" => 100},
        "parallel_3" => %{"type" => "wait", "duration" => 100}
      }

      test_pid = self()
      concurrent_count = :counters.new(1, [:atomics])

      executor = fn step_name, _step_def, _context ->
        :counters.add(concurrent_count, 1, 1)
        current = :counters.get(concurrent_count, 1)
        send(test_pid, {:concurrency, step_name, current})

        Process.sleep(30)

        :counters.sub(concurrent_count, 1, 1)
        {:ok, %{step: step_name}}
      end

      {:ok, result} = Executor.execute(steps, executor, %{})

      assert result.status == :completed

      # Should see all 3 running at once at some point
      readings =
        Enum.map(1..3, fn _ ->
          receive do
            {:concurrency, _step, count} -> count
          after
            1000 -> flunk("Timeout waiting for concurrency message")
          end
        end)

      # With unlimited, we should see 3 concurrent at the peak
      assert Enum.max(readings) == 3
    end

    test "max_concurrency: 1 serializes execution" do
      steps = %{
        "step_1" => %{"type" => "wait", "duration" => 100},
        "step_2" => %{"type" => "wait", "duration" => 100},
        "step_3" => %{"type" => "wait", "duration" => 100}
      }

      test_pid = self()
      concurrent_count = :counters.new(1, [:atomics])

      executor = fn step_name, _step_def, _context ->
        :counters.add(concurrent_count, 1, 1)
        current = :counters.get(concurrent_count, 1)
        send(test_pid, {:concurrency, step_name, current})

        Process.sleep(10)

        :counters.sub(concurrent_count, 1, 1)
        {:ok, %{step: step_name}}
      end

      {:ok, result} = Executor.execute(steps, executor, %{}, max_concurrency: 1)

      assert result.status == :completed

      readings =
        Enum.map(1..3, fn _ ->
          receive do
            {:concurrency, _step, count} -> count
          after
            1000 -> flunk("Timeout")
          end
        end)

      # With max_concurrency: 1, we should never see more than 1 concurrent
      assert Enum.max(readings) == 1
    end
  end

  describe "execute/4 timeouts" do
    test "times out steps that exceed step timeout" do
      steps = %{
        "slow_step" => %{"type" => "wait", "duration" => 100},
        "dependent" => %{"type" => "log", "message" => "done", "depends_on" => ["slow_step"]}
      }

      # Executor that sleeps longer than the timeout
      slow_executor = fn step_name, _step_def, _context ->
        if step_name == "slow_step" do
          Process.sleep(500)
          {:ok, %{step: step_name}}
        else
          {:ok, %{step: step_name}}
        end
      end

      # Step timeout of 100ms, global timeout of 10s
      {:error, {:steps_failed, result}} =
        Executor.execute(steps, slow_executor, %{}, step_timeout: 100, global_timeout: 10_000)

      assert "slow_step" in result.timed_out_steps
      assert "dependent" in result.blocked_steps
    end

    test "per-step timeout overrides default" do
      steps = %{
        # This step has a custom timeout of 1 second
        "patient_step" => %{"type" => "wait", "duration" => 100, "timeout" => 1000},
        "dependent" => %{"type" => "log", "message" => "done", "depends_on" => ["patient_step"]}
      }

      # Executor that sleeps 200ms - longer than default but shorter than step timeout
      slow_executor = fn step_name, _step_def, _context ->
        if step_name == "patient_step" do
          Process.sleep(200)
          {:ok, %{step: step_name}}
        else
          {:ok, %{step: step_name}}
        end
      end

      # Default step timeout of 100ms, but patient_step has 1000ms
      {:ok, result} =
        Executor.execute(steps, slow_executor, %{}, step_timeout: 100, global_timeout: 10_000)

      assert result.status == :completed
      assert "patient_step" in result.completed_steps
      assert "dependent" in result.completed_steps
    end

    test "global timeout stops entire execution" do
      steps = %{
        "step_1" => %{"type" => "wait", "duration" => 100},
        "step_2" => %{"type" => "wait", "duration" => 100, "depends_on" => ["step_1"]},
        "step_3" => %{"type" => "wait", "duration" => 100, "depends_on" => ["step_2"]}
      }

      # Each step sleeps 100ms
      slow_executor = fn _step_name, _step_def, _context ->
        Process.sleep(100)
        {:ok, %{}}
      end

      # Global timeout of 150ms - should complete step_1 but timeout during step_2
      {:error, {:global_timeout, result}} =
        Executor.execute(steps, slow_executor, %{}, global_timeout: 150, step_timeout: 10_000)

      # step_1 should have completed
      assert "step_1" in result.completed_steps
      # step_3 was never started
      refute "step_3" in result.completed_steps
    end
  end
end
