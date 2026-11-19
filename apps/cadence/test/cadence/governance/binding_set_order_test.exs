defmodule Cadence.Governance.BindingSetOrderTest do
  @moduledoc """
  #56 R2: a hydrated binding set is hashed (activation evidence, the runtime spec), so its rules
  come back in a bytewise order, not the database's text collation. Under en_US (CI) the old
  ORDER BY gave rule-a, rule-b, rule-B for equal priorities; bytewise it's rule-B, rule-a, rule-b.
  """
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Telemetry.PacketDefinition

  @mission "mission-collation"

  setup do
    persist_mission_scope("org-collation", @mission)
    :ok
  end

  defp rule(id, apid, priority) do
    BindingRule.new(%{
      binding_rule_id: id,
      priority: priority,
      handler_key: :definition_bound_telemetry,
      packet_kind: :space_packet,
      apid: apid,
      handler_configuration:
        PacketDefinition.new(%{
          mission_id: @mission,
          packet_definition_id: "hk-#{apid}",
          packet_name: "HK#{apid}",
          apid: apid,
          fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
        })
    })
  end

  test "rules hydrate by priority, then id bytewise" do
    binding_set =
      BindingSet.new(%{
        mission_id: @mission,
        binding_set_id: "collation-set",
        version: 1,
        rules: [
          rule("rule-b", 41, 100),
          rule("rule-a", 42, 100),
          rule("rule-B", 43, 100),
          rule("rule-z", 44, 50)
        ]
      })

    assert {:ok, _} = Cadence.Governance.persist_binding_set(binding_set)
    assert {:ok, fetched} = Cadence.Governance.fetch_binding_set(@mission, "collation-set", 1)

    assert Enum.map(fetched.rules, & &1.binding_rule_id) ==
             ["rule-z", "rule-B", "rule-a", "rule-b"]
  end
end
