defmodule Cadence.Reads.RoutingRuleGroupsTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.RoutingRule
  alias Cadence.Reads.{CommsDirectory, OrganizationMissions}

  defp rule(id, spacecraft, transport, opts \\ []) do
    %RoutingRule{
      routing_rule_id: id,
      spacecraft_id: spacecraft,
      transport_id: transport,
      direction: Keyword.get(opts, :direction, :inbound),
      role: Keyword.get(opts, :role, :primary),
      enabled?: Keyword.get(opts, :enabled, true),
      lifecycle_state: Keyword.get(opts, :state, :active)
    }
  end

  test "groups active rules by transport, direction and role, counting enabled ones" do
    rules = [
      rule("r1", "sc-1", "t-fai"),
      rule("r2", "sc-2", "t-fai"),
      rule("r3", "sc-3", "t-fai", enabled: false),
      rule("r4", "sc-1", "t-fai", role: :candidate),
      rule("r5", "sc-1", "t-sva", direction: :outbound),
      rule("r6", "sc-9", "t-sva", direction: :outbound, state: :archived)
    ]

    transports = %{"t-fai" => "Fairbanks downlink", "t-sva" => "Svalbard uplink"}

    assert CommsDirectory.group_rules(rules, transports) == [
             %{
               transport: %{id: "t-fai", name: "Fairbanks downlink"},
               direction: :inbound,
               role: :candidate,
               enabled_count: 1,
               disabled_count: 0,
               spacecraft_count: 1
             },
             %{
               transport: %{id: "t-fai", name: "Fairbanks downlink"},
               direction: :inbound,
               role: :primary,
               enabled_count: 2,
               disabled_count: 1,
               spacecraft_count: 3
             },
             %{
               transport: %{id: "t-sva", name: "Svalbard uplink"},
               direction: :outbound,
               role: :primary,
               enabled_count: 1,
               disabled_count: 0,
               spacecraft_count: 1
             }
           ]
  end

  # Lead's drift sweep: the console reads transport.name as a string.
  test "a group on a transport missing from the active list is named by its id" do
    assert [%{transport: %{id: "t-gone", name: "t-gone"}}] =
             CommsDirectory.group_rules([rule("r1", "sc-1", "t-gone")], %{})
  end

  test "a mission's worst state is the worst one with any spacecraft" do
    assert OrganizationMissions.worst(%{critical: 0, caution: 2, stale: 5, nominal: 9}) ==
             :caution

    assert OrganizationMissions.worst(%{never_heard: 3}) == :never_heard
    assert OrganizationMissions.worst(%{total: 0}) == nil
  end
end
