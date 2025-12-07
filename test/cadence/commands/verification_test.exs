defmodule Cadence.Commands.VerificationTest do
  use Cadence.DataCase, async: true

  alias Cadence.Commands.Verification

  describe "new/4" do
    test "creates verification with default mode :any_update" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      assert verification.command_log_id == "cmd-123"
      assert verification.mission_id == "mission-1"
      assert verification.target_id == "target-1"
      assert verification.item == "HEALTH.CMD_ACK"
      assert verification.mode == :any_update
      assert verification.timeout_ms == 5000
    end

    test "creates verification with :value_match mode when expected_value provided" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "THERMAL.MODE",
          expected_value: "HEATING"
        )

      assert verification.mode == :value_match
      assert verification.expected_value == "HEATING"
    end

    test "creates verification with custom timeout" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.STATUS",
          timeout_ms: 10_000
        )

      assert verification.timeout_ms == 10_000
    end
  end

  describe "check_update/2 with :any_update mode" do
    test "verifies on any value" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      assert {:verified, 42} = Verification.check_update(verification, 42)
      assert {:verified, "hello"} = Verification.check_update(verification, "hello")
      assert {:verified, true} = Verification.check_update(verification, true)
    end
  end

  describe "check_update/2 with :value_match mode" do
    test "verifies when value matches expected string" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "THERMAL.MODE",
          expected_value: "HEATING"
        )

      assert {:verified, "HEATING"} = Verification.check_update(verification, "HEATING")
    end

    test "returns :pending when value doesn't match" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "THERMAL.MODE",
          expected_value: "HEATING"
        )

      assert :pending = Verification.check_update(verification, "COOLING")
    end

    test "verifies when numeric value matches" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.STATE",
          expected_value: 1
        )

      assert {:verified, 1} = Verification.check_update(verification, 1)
      assert {:verified, 1.0} = Verification.check_update(verification, 1.0)
    end

    test "handles string-to-number comparison" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.STATE",
          expected_value: "ON"
        )

      # Should verify when string representation matches
      assert {:verified, "ON"} = Verification.check_update(verification, "ON")
    end
  end

  describe "check_update/2 with :count_increment mode" do
    test "verifies when count increases from initial" do
      verification = %Verification{
        command_log_id: "cmd-123",
        mission_id: "mission-1",
        target_id: "target-1",
        item: "HEALTH.CMD_COUNT",
        mode: :count_increment,
        initial_value: 10,
        timeout_ms: 5000,
        started_at: DateTime.utc_now()
      }

      assert {:verified, 11} = Verification.check_update(verification, 11)
      assert {:verified, 100} = Verification.check_update(verification, 100)
    end

    test "returns :pending when count hasn't increased" do
      verification = %Verification{
        command_log_id: "cmd-123",
        mission_id: "mission-1",
        target_id: "target-1",
        item: "HEALTH.CMD_COUNT",
        mode: :count_increment,
        initial_value: 10,
        timeout_ms: 5000,
        started_at: DateTime.utc_now()
      }

      assert :pending = Verification.check_update(verification, 10)
      assert :pending = Verification.check_update(verification, 5)
    end

    test "verifies on any value when no initial value" do
      verification = %Verification{
        command_log_id: "cmd-123",
        mission_id: "mission-1",
        target_id: "target-1",
        item: "HEALTH.CMD_COUNT",
        mode: :count_increment,
        initial_value: nil,
        timeout_ms: 5000,
        started_at: DateTime.utc_now()
      }

      assert {:verified, 1} = Verification.check_update(verification, 1)
    end
  end

  describe "check_update/2 with :range mode" do
    test "verifies when value is within range" do
      verification = %Verification{
        command_log_id: "cmd-123",
        mission_id: "mission-1",
        target_id: "target-1",
        item: "THERMAL.TEMP",
        mode: :range,
        expected_value: {20.0, 30.0},
        timeout_ms: 5000,
        started_at: DateTime.utc_now()
      }

      assert {:verified, 25.0} = Verification.check_update(verification, 25.0)
      assert {:verified, 20.0} = Verification.check_update(verification, 20.0)
      assert {:verified, 30.0} = Verification.check_update(verification, 30.0)
    end

    test "returns :pending when value is outside range" do
      verification = %Verification{
        command_log_id: "cmd-123",
        mission_id: "mission-1",
        target_id: "target-1",
        item: "THERMAL.TEMP",
        mode: :range,
        expected_value: {20.0, 30.0},
        timeout_ms: 5000,
        started_at: DateTime.utc_now()
      }

      assert :pending = Verification.check_update(verification, 19.9)
      assert :pending = Verification.check_update(verification, 30.1)
    end
  end

  describe "timed_out?/1" do
    test "returns false when within timeout" do
      verification = %Verification{
        started_at: DateTime.utc_now(),
        timeout_ms: 5000
      }

      refute Verification.timed_out?(verification)
    end

    test "returns true when past timeout" do
      # Started 10 seconds ago with 5 second timeout
      started_at = DateTime.add(DateTime.utc_now(), -10, :second)

      verification = %Verification{
        started_at: started_at,
        timeout_ms: 5000
      }

      assert Verification.timed_out?(verification)
    end
  end

  describe "parse_item/1" do
    test "parses packet.item format" do
      assert {"HEALTH", "CMD_ACK"} = Verification.parse_item("HEALTH.CMD_ACK")
    end

    test "parses packet.nested.item format" do
      assert {"THERMAL", "TEMP.SENSOR_1"} = Verification.parse_item("THERMAL.TEMP.SENSOR_1")
    end

    test "handles item without packet" do
      assert {"", "ITEM"} = Verification.parse_item("ITEM")
    end
  end

  describe "matches_update?/4" do
    test "returns true when update matches verification" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      assert Verification.matches_update?(verification, "target-1", "HEALTH", "CMD_ACK")
    end

    test "returns false when target doesn't match" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      refute Verification.matches_update?(verification, "target-2", "HEALTH", "CMD_ACK")
    end

    test "returns false when packet doesn't match" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      refute Verification.matches_update?(verification, "target-1", "THERMAL", "CMD_ACK")
    end

    test "returns false when item doesn't match" do
      verification =
        Verification.new(
          "cmd-123",
          "mission-1",
          "target-1",
          item: "HEALTH.CMD_ACK"
        )

      refute Verification.matches_update?(verification, "target-1", "HEALTH", "STATUS")
    end
  end
end
