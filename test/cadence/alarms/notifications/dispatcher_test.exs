defmodule Cadence.Alarms.Notifications.DispatcherTest do
  @moduledoc """
  Tests for the notification Dispatcher module.

  Tests cover:
  - Channel parsing (type:name format)
  - Dispatch to configured channels
  - Edge cases (nil rule, empty channels)

  Note: Most dispatch tests focus on successful completion (returns :ok)
  rather than log output since Logger is configured at :warning level in tests.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cadence.Alarms.Notifications.Dispatcher

  import Cadence.AlarmsBuilders

  # ============================================================================
  # parse_channel/1
  # ============================================================================

  describe "parse_channel/1" do
    test "parses valid type:name format" do
      assert {:ok, "webhook", "ops"} = Dispatcher.parse_channel("webhook:ops")
      assert {:ok, "email", "oncall"} = Dispatcher.parse_channel("email:oncall")
      assert {:ok, "slack", "alerts"} = Dispatcher.parse_channel("slack:alerts")
      assert {:ok, "pagerduty", "critical"} = Dispatcher.parse_channel("pagerduty:critical")
      assert {:ok, "teams", "general"} = Dispatcher.parse_channel("teams:general")
    end

    test "returns error for missing colon" do
      assert {:error, :invalid_format} = Dispatcher.parse_channel("webhook")
      assert {:error, :invalid_format} = Dispatcher.parse_channel("ops")
      assert {:error, :invalid_format} = Dispatcher.parse_channel("invalid")
    end

    test "returns error for empty type" do
      assert {:error, :invalid_format} = Dispatcher.parse_channel(":ops")
    end

    test "returns error for empty name" do
      assert {:error, :invalid_format} = Dispatcher.parse_channel("webhook:")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = Dispatcher.parse_channel("")
    end

    test "handles colons in name" do
      # The parts: 2 option means only split on first colon
      # So "webhook:https://example.com/api" should work
      assert {:ok, "webhook", "https://example.com/api"} =
               Dispatcher.parse_channel("webhook:https://example.com/api")
    end

    test "handles spaces in name" do
      assert {:ok, "email", "on call team"} = Dispatcher.parse_channel("email:on call team")
    end

    test "preserves case" do
      assert {:ok, "WebHook", "OPS"} = Dispatcher.parse_channel("WebHook:OPS")
    end
  end

  # ============================================================================
  # dispatch/3
  # ============================================================================

  describe "dispatch/3" do
    test "returns :ok for configured channels" do
      alarm = build_alarm(message: "CPU temperature exceeded threshold")
      rule = build_alarm_rule(notification_channels: ["webhook:ops", "slack:alerts"])

      assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
    end

    test "handles nil rule gracefully" do
      alarm = build_alarm()

      assert :ok = Dispatcher.dispatch(alarm, :triggered, nil)
    end

    test "handles rule with nil notification_channels" do
      alarm = build_alarm()
      rule = build_alarm_rule(notification_channels: nil)

      assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
    end

    test "handles empty notification_channels" do
      alarm = build_alarm()
      rule = build_alarm_rule(notification_channels: [])

      assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
    end

    test "logs warning for invalid channel format" do
      alarm = build_alarm()
      rule = build_alarm_rule(notification_channels: ["invalid_no_colon"])

      # Warning level logs ARE captured since Logger is at :warning level
      log =
        capture_log(fn ->
          assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
        end)

      assert log =~ "Invalid notification channel format: invalid_no_colon"
    end

    test "processes all channels even if some are invalid" do
      alarm = build_alarm()
      rule = build_alarm_rule(notification_channels: ["webhook:ops", "invalid", "slack:alerts"])

      # Verify it completes successfully and logs warning for invalid
      log =
        capture_log(fn ->
          assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
        end)

      assert log =~ "Invalid notification channel format: invalid"
    end

    test "dispatches for all event types without error" do
      alarm = build_alarm()
      rule = build_alarm_rule(notification_channels: ["webhook:ops"])

      event_types = [:triggered, :escalated, :acknowledged, :cleared, :shelved, :unshelved]

      for event_type <- event_types do
        assert :ok = Dispatcher.dispatch(alarm, event_type, rule)
      end
    end

    test "handles multiple channels" do
      alarm = build_alarm()

      rule =
        build_alarm_rule(
          notification_channels: [
            "webhook:ops",
            "email:oncall",
            "slack:alerts",
            "pagerduty:critical"
          ]
        )

      assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
    end

    test "handles channel with complex names" do
      alarm = build_alarm()

      rule =
        build_alarm_rule(
          notification_channels: [
            "webhook:https://api.example.com/notify",
            "email:team-lead@example.com"
          ]
        )

      assert :ok = Dispatcher.dispatch(alarm, :triggered, rule)
    end
  end

  # ============================================================================
  # supported_types/0
  # ============================================================================

  describe "supported_types/0" do
    test "returns list of supported notifier types" do
      types = Dispatcher.supported_types()

      assert is_list(types)
      assert "webhook" in types
      assert "email" in types
      assert "slack" in types
      assert "pagerduty" in types
      assert "teams" in types
    end

    test "returns at least 5 types" do
      types = Dispatcher.supported_types()
      assert length(types) >= 5
    end
  end
end
