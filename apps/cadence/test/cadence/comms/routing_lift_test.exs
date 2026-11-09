defmodule Cadence.Comms.RoutingLiftTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{RoutingLift, RoutingRule, RoutingRuleStore, TransportStore}
  alias Cadence.Control.Configuration

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("lift")
    alice = member_scope(org, :member, "Alice")
    ctx = %{org: org, mission: mission, alice: alice}
    [a, b, ta, tb, profile] = Enum.map(~w(sta stb ta tb prof), &unique/1)

    apply_ops(ctx, "Stations, transports, profile", [
      create("ground_station", %{"display_name" => "Alpha", "code" => "ALP"}, a),
      create("ground_station", %{"display_name" => "Bravo", "code" => "BRV"}, b),
      create("transport", Map.put(transport_doc("TA"), "ground_station_id", a), ta),
      create("transport", Map.put(transport_doc("TB"), "ground_station_id", b), tb),
      create("spacecraft_profile", profile_doc("Block"), profile)
    ])

    [sc1, sc2] =
      apply_ops(ctx, "Fleet", [
        create("spacecraft", spacecraft_doc("SC-1", 1, {profile, 1})),
        create("spacecraft", spacecraft_doc("SC-2", 2, {profile, 1}))
      ])

    for {sc, transport} <- [{sc1, ta}, {sc1, tb}, {sc2, ta}], do: legacy_rule(ctx, sc, transport)

    Map.merge(ctx, %{a: a, b: b, ta: ta, tb: tb, profile: profile, sc1: sc1, sc2: sc2})
  end

  test "lifts shared rules into the profile with exclusions, keeping every spacecraft's routes",
       ctx do
    before = Map.new([ctx.sc1, ctx.sc2], &{&1, effective(ctx, &1)})

    assert {:ok, %{ops: ops, summary: %{profiles: 1, rules: 1, overrides: 1}}} =
             RoutingLift.ops(ctx.org, ctx.mission)

    [profile_op, override_op] = ops
    [%{value: [rule]}] = profile_op.changes
    assert rule["id"] == "lifted-downlink-primary"

    assert Enum.map(rule["stations"], & &1["ground_station_id"]) |> Enum.sort() ==
             Enum.sort([ctx.a, ctx.b])

    assert %{entity_id: sc2, changes: [%{value: %{"value" => [excluded]}}]} = override_op
    assert {sc2, excluded} == {ctx.sc2, ctx.b}

    apply_ops(ctx, "Lift", ops)

    for sc <- [ctx.sc1, ctx.sc2] do
      routes = active_routes(ctx, sc)
      assert Enum.all?(routes, &(&1.origin == :profile)), "legacy rules retired for #{sc}"
      assert effective(ctx, sc) == before[sc]
    end
  end

  test "a mission without legacy rules has nothing to lift", ctx do
    for sc <- [ctx.sc1, ctx.sc2],
        rule <- active_routes(ctx, sc),
        do: RoutingRuleStore.archive_routing_rule(ctx.org, ctx.mission, rule.routing_rule_id)

    assert {:ok, %{ops: [], summary: %{profiles: 0}}} = RoutingLift.ops(ctx.org, ctx.mission)
  end

  defp legacy_rule(ctx, spacecraft_id, transport_id) do
    {:ok, transport} = TransportStore.fetch_transport(ctx.org, ctx.mission, transport_id)

    {:ok, _} =
      RoutingRuleStore.create_routing_rule(
        ctx.org,
        RoutingRule.new(%{
          mission_id: ctx.mission,
          spacecraft_id: spacecraft_id,
          display_name: "#{transport.display_name} downlink",
          purpose_label: "TT&C",
          direction: :inbound,
          transport_id: transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )
  end

  defp active_routes(ctx, spacecraft_id),
    do: RoutingRuleStore.list_routing_rules_for_spacecraft(ctx.org, ctx.mission, spacecraft_id)

  defp effective(ctx, spacecraft_id) do
    ctx
    |> active_routes(spacecraft_id)
    |> Enum.map(&{&1.transport_id, &1.direction, &1.role})
    |> Enum.sort()
  end

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end

  defp create(kind, document, id \\ nil) do
    op = %{kind: kind, action: :create, document: document}
    if id, do: Map.put(op, :entity_id, id), else: op
  end
end
