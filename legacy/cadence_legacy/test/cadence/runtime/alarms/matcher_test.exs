defmodule Cadence.Runtime.Alarms.MatcherTest do
  use ExUnit.Case, async: true

  alias Cadence.Alarms.AlarmRule
  alias Cadence.Runtime.Alarms.Matcher
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  describe "matches?/2" do
    test "matches when conditions are empty" do
      rule = %AlarmRule{conditions: %{}}
      event = build_event(new_state: :red)

      assert Matcher.matches?(rule, event)
    end

    test "matches limit_state condition" do
      rule = %AlarmRule{conditions: %{"limit_state" => ["red", "yellow"]}}

      assert Matcher.matches?(rule, build_event(new_state: :red))
      assert Matcher.matches?(rule, build_event(new_state: :yellow))
      refute Matcher.matches?(rule, build_event(new_state: :green))
      refute Matcher.matches?(rule, build_event(new_state: :blue))
    end

    test "matches limit_state as string" do
      rule = %AlarmRule{conditions: %{"limit_state" => ["red"]}}

      # Should match both atom and string representations
      assert Matcher.matches?(rule, build_event(new_state: :red))
    end

    test "matches item_name condition" do
      rule = %AlarmRule{
        conditions: %{
          "item_name" => ["HEALTH.cpu_temp", "HEALTH.battery_temp"]
        }
      }

      assert Matcher.matches?(rule, build_event(item_name: "HEALTH.cpu_temp"))
      assert Matcher.matches?(rule, build_event(item_name: "HEALTH.battery_temp"))
      refute Matcher.matches?(rule, build_event(item_name: "HEALTH.other"))
    end

    test "matches item_name_pattern condition" do
      rule = %AlarmRule{conditions: %{"item_name_pattern" => "POWER\\..*"}}

      assert Matcher.matches?(rule, build_event(item_name: "POWER.voltage"))
      assert Matcher.matches?(rule, build_event(item_name: "POWER.current"))
      refute Matcher.matches?(rule, build_event(item_name: "HEALTH.cpu_temp"))
    end

    test "matches target_id condition" do
      rule = %AlarmRule{conditions: %{"target_id" => ["SAT-1", "SAT-2"]}}

      assert Matcher.matches?(rule, build_event(target_id: "SAT-1"))
      assert Matcher.matches?(rule, build_event(target_id: "SAT-2"))
      refute Matcher.matches?(rule, build_event(target_id: "SAT-3"))
    end

    test "requires all conditions to match (AND logic)" do
      rule = %AlarmRule{
        conditions: %{
          "limit_state" => ["red"],
          "item_name_pattern" => "POWER\\..*"
        }
      }

      # Both conditions match
      assert Matcher.matches?(rule, build_event(new_state: :red, item_name: "POWER.voltage"))

      # Only limit_state matches
      refute Matcher.matches?(rule, build_event(new_state: :red, item_name: "HEALTH.temp"))

      # Only item_name_pattern matches
      refute Matcher.matches?(rule, build_event(new_state: :yellow, item_name: "POWER.voltage"))
    end

    test "ignores unknown condition keys" do
      rule = %AlarmRule{
        conditions: %{
          "limit_state" => ["red"],
          "unknown_key" => ["value"]
        }
      }

      # Unknown keys should not prevent matching
      assert Matcher.matches?(rule, build_event(new_state: :red))
    end

    test "handles invalid regex gracefully" do
      rule = %AlarmRule{conditions: %{"item_name_pattern" => "[invalid"}}

      # Invalid regex should not match
      refute Matcher.matches?(rule, build_event(item_name: "anything"))
    end
  end

  describe "find_matching_rule/2" do
    test "returns first matching rule" do
      rules = [
        %AlarmRule{id: "1", conditions: %{"limit_state" => ["yellow"]}},
        %AlarmRule{id: "2", conditions: %{"limit_state" => ["red"]}},
        %AlarmRule{id: "3", conditions: %{}}
      ]

      event = build_event(new_state: :red)
      result = Matcher.find_matching_rule(rules, event)

      assert result.id == "2"
    end

    test "returns nil when no rules match" do
      rules = [
        %AlarmRule{id: "1", conditions: %{"limit_state" => ["yellow"]}},
        %AlarmRule{id: "2", conditions: %{"item_name" => ["OTHER.item"]}}
      ]

      event = build_event(new_state: :red, item_name: "HEALTH.cpu_temp")

      assert Matcher.find_matching_rule(rules, event) == nil
    end

    test "respects rule order (specificity)" do
      # More specific rule first
      rules = [
        %AlarmRule{
          id: "specific",
          conditions: %{
            "limit_state" => ["red"],
            "item_name" => ["HEALTH.cpu_temp"]
          }
        },
        %AlarmRule{id: "general", conditions: %{"limit_state" => ["red"]}}
      ]

      event = build_event(new_state: :red, item_name: "HEALTH.cpu_temp")
      result = Matcher.find_matching_rule(rules, event)

      assert result.id == "specific"
    end
  end

  describe "find_all_matching_rules/2" do
    test "returns all matching rules" do
      rules = [
        %AlarmRule{id: "1", conditions: %{"limit_state" => ["red"]}},
        %AlarmRule{id: "2", conditions: %{}},
        %AlarmRule{id: "3", conditions: %{"limit_state" => ["yellow"]}}
      ]

      event = build_event(new_state: :red)
      results = Matcher.find_all_matching_rules(rules, event)

      assert length(results) == 2
      ids = Enum.map(results, & &1.id)
      assert "1" in ids
      assert "2" in ids
    end
  end

  describe "render_message/2" do
    test "renders default message when template is nil" do
      event = build_event(item_name: "HEALTH.cpu_temp", new_state: :red, value: 105.0)
      message = Matcher.render_message(nil, event)

      assert message =~ "HEALTH.cpu_temp"
      assert message =~ "red"
      assert message =~ "105.0"
    end

    test "renders template with variables" do
      template = "{{item_name}} is {{limit_state}} (value: {{value}})"
      event = build_event(item_name: "HEALTH.cpu_temp", new_state: :red, value: 105.5)

      message = Matcher.render_message(template, event)

      assert message == "HEALTH.cpu_temp is red (value: 105.50)"
    end

    test "renders all available variables" do
      template =
        "{{item_name}} | {{value}} | {{limit_state}} | {{previous_state}} | {{target_id}} | {{limit_set}}"

      event =
        build_event(
          item_name: "HEALTH.temp",
          value: 80.0,
          new_state: :yellow,
          previous_state: :green,
          target_id: "SAT-1",
          limit_set: "NOMINAL"
        )

      message = Matcher.render_message(template, event)

      assert message == "HEALTH.temp | 80.00 | yellow | green | SAT-1 | NOMINAL"
    end

    test "handles nil value" do
      template = "Value: {{value}}"
      event = build_event(value: nil)

      message = Matcher.render_message(template, event)

      assert message == "Value: N/A"
    end

    test "handles integer value" do
      template = "Value: {{value}}"
      event = build_event(value: 100)

      message = Matcher.render_message(template, event)

      assert message == "Value: 100"
    end
  end

  describe "default_severity_for_state/1" do
    test "maps red to critical" do
      assert Matcher.default_severity_for_state(:red) == :critical
    end

    test "maps yellow to warning" do
      assert Matcher.default_severity_for_state(:yellow) == :warning
    end

    test "maps blue to info" do
      assert Matcher.default_severity_for_state(:blue) == :info
    end

    test "maps green to info" do
      assert Matcher.default_severity_for_state(:green) == :info
    end

    test "maps unknown to info" do
      assert Matcher.default_severity_for_state(:unknown) == :info
    end
  end

  # Helper to build test events
  defp build_event(attrs) do
    TelemetryLimitEvent.new(%{
      mission_id: Keyword.get(attrs, :mission_id, "mission-123"),
      target_id: Keyword.get(attrs, :target_id, "SAT-1"),
      item_name: Keyword.get(attrs, :item_name, "HEALTH.cpu_temp"),
      previous_state: Keyword.get(attrs, :previous_state, :green),
      new_state: Keyword.get(attrs, :new_state, :red),
      value: Keyword.get(attrs, :value, 100.0),
      limit_set: Keyword.get(attrs, :limit_set, "NOMINAL")
    })
  end
end
