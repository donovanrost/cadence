defmodule Cadence.Commands.VerificationRunnerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Commands.VerificationRunner
  alias Cadence.Harness.Time
  alias Cadence.MissionDatabase.CommandVerifier

  setup_virtual_time()

  test "delivers stage timeout after virtual time advances" do
    command_log_id = random_id()
    mission_id = random_id()
    target_id = random_id()

    verifier = %CommandVerifier{
      stage: :received,
      telemetry_item_ref: "HEALTH.CMD_ACCEPT_COUNT",
      comparison: :equal,
      expected_value: "1",
      timeout_ms: 1_000
    }

    {:ok, runner} = VerificationRunner.new(command_log_id, mission_id, target_id, [verifier])
    {:ok, runner} = VerificationRunner.start_current_stage(runner)
    _runner = VerificationRunner.start_timeout(runner, self())

    refute_receive {:verification_stage_timeout, ^command_log_id, :received}

    :ok = Time.advance(1_000)

    assert_receive {:verification_stage_timeout, ^command_log_id, :received}
  end

  test "cancels stage timeout before virtual time advances" do
    command_log_id = random_id()
    mission_id = random_id()
    target_id = random_id()

    verifier = %CommandVerifier{
      stage: :received,
      telemetry_item_ref: "HEALTH.CMD_ACCEPT_COUNT",
      comparison: :equal,
      expected_value: "1",
      timeout_ms: 1_000
    }

    {:ok, runner} = VerificationRunner.new(command_log_id, mission_id, target_id, [verifier])
    {:ok, runner} = VerificationRunner.start_current_stage(runner)
    runner = VerificationRunner.start_timeout(runner, self())
    runner = VerificationRunner.cancel_timeout(runner)

    assert runner.timeout_ref == nil

    :ok = Time.advance(1_000)

    refute_receive {:verification_stage_timeout, ^command_log_id, :received}
  end

  test "retries stage timeout on successive virtual time advances" do
    command_log_id = random_id()
    mission_id = random_id()
    target_id = random_id()

    verifier = %CommandVerifier{
      stage: :received,
      telemetry_item_ref: "HEALTH.CMD_ACCEPT_COUNT",
      comparison: :equal,
      expected_value: "1",
      timeout_ms: 1_000,
      on_timeout_action: "retry"
    }

    {:ok, runner} = VerificationRunner.new(command_log_id, mission_id, target_id, [verifier])
    {:ok, runner} = VerificationRunner.start_current_stage(runner)
    runner = VerificationRunner.start_timeout(runner, self())

    :ok = Time.advance(1_000)

    assert_receive {:verification_stage_timeout, ^command_log_id, :received}

    {:retry, runner} = VerificationRunner.handle_timeout(runner)
    assert runner.timeout_ref == nil

    _runner = VerificationRunner.start_timeout(runner, self())

    :ok = Time.advance(1_000)

    assert_receive {:verification_stage_timeout, ^command_log_id, :received}
  end
end
