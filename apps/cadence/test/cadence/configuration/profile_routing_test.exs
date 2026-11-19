defmodule Cadence.Configuration.ProfileRoutingTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Control.{Configuration, ConfigurationRollback}
  alias Cadence.Reads.ProfileRouting
  alias Cadence.SpacecraftTypeStore

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("routing")
    alice = member_scope(org, :member, "Alice")
    ids = %{station: unique("svb"), transport: unique("transport"), profile: unique("block1")}

    apply_ops(%{alice: alice, mission: mission}, "Block 1 with Svalbard", [
      create("ground_station", %{"display_name" => "Svalbard", "code" => "SVB"}, ids.station),
      create(
        "transport",
        Map.put(transport_doc("Svalbard TCP"), "ground_station_id", ids.station),
        ids.transport
      ),
      create("spacecraft_profile", profile_with_rule(ids.station), ids.profile)
    ])

    [sc] =
      apply_ops(%{alice: alice, mission: mission}, "First spacecraft", [
        create("spacecraft", spacecraft_doc("EARENDIL-001", 1, {ids.profile, 1}))
      ])

    %{org: org, mission: mission, alice: alice, ids: ids, sc: sc}
  end

  test "profile rules materialize one route per spacecraft, station and leg", ctx do
    assert [route] = profile_routes(ctx)
    assert route.display_name == "SVB · EARENDIL-001"
    assert route.direction == :inbound
    assert route.transport_id == ctx.ids.transport
    assert route.profile_rule_id == "ttc"

    {:ok, %{head: %{revision: head}}} = Configuration.current(ctx.alice, ctx.mission)
    {:ok, %{entries: entries}} = Configuration.get_revision(ctx.alice, ctx.mission, head)
    assert Enum.any?(entries, &(&1.kind == "spacecraft_routes" and &1.entity_id == ctx.sc))
  end

  test "reads: rules with route counts and samples; overrides with since rN", ctx do
    {:ok, profile} =
      SpacecraftTypeStore.fetch_spacecraft_type(ctx.org, ctx.mission, ctx.ids.profile)

    assert [
             %{
               id: "ttc",
               route_count: 1,
               samples: ["SVB · EARENDIL-001"],
               stations: [%{code: "SVB"}]
             }
           ] =
             ProfileRouting.rules(ctx.org, ctx.mission, profile)

    apply_ops(ctx, "Exclude Svalbard", [
      override(ctx, %{"value" => [ctx.ids.station], "reason" => "Antenna 2 down"})
    ])

    {:ok, %{head: %{revision: head}}} = Configuration.current(ctx.alice, ctx.mission)

    {:ok, profile} =
      SpacecraftTypeStore.fetch_spacecraft_type(ctx.org, ctx.mission, ctx.ids.profile)

    assert [
             %{
               path: "routing.ttc.excluded_stations",
               section: :routing,
               since_revision: ^head,
               profile_value: [],
               reason: "Antenna 2 down"
             }
           ] =
             ProfileRouting.overrides(ctx.org, ctx.mission, profile)
  end

  test "an override excludes a station, and a reset brings the route back", ctx do
    exclude = override(ctx, %{"value" => [ctx.ids.station], "reason" => "Antenna 2 down"})
    apply_ops(ctx, "Exclude Svalbard", [exclude])
    assert [] = profile_routes(ctx)

    apply_ops(ctx, "Reset", [override(ctx, nil)])
    assert [%{display_name: "SVB · EARENDIL-001"}] = profile_routes(ctx)
  end

  test "editing the rule's name template renames the routes", ctx do
    rules = [Map.put(rule(ctx.ids.station), "name_template", "{spacecraft} via {station}")]

    apply_ops(ctx, "Rename routes", [
      %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: ctx.ids.profile,
        changes: [%{path: "routing_rules", value: rules}]
      }
    ])

    assert [%{display_name: "EARENDIL-001 via SVB", spacecraft_type_version: 2}] =
             profile_routes(ctx)
  end

  test "a rule naming a missing station is a NO-GO", ctx do
    op = %{
      kind: "spacecraft_profile",
      action: :update,
      entity_id: ctx.ids.profile,
      changes: [%{path: "routing_rules", value: [rule("nowhere")]}]
    }

    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(ctx.alice, ctx.mission, {:ops, [op]})

    assert %{items: [%{kind: "spacecraft_routes", errors: [%{message: message}]}]} =
             Enum.find(checks, &(&1.key == "validation"))

    assert message =~ "nowhere"
    assert [_still_there] = profile_routes(ctx)
  end

  test "rolling back a routing-rule edit skips the derived routes and re-derives them (#49)",
       ctx do
    {:ok, %{head: %{revision: before_edit}}} = Configuration.current(ctx.alice, ctx.mission)

    apply_ops(ctx, "Rename the rule", [
      %{
        kind: "spacecraft_profile",
        action: :update,
        entity_id: ctx.ids.profile,
        changes: [
          %{path: "routing_rules", value: [Map.put(rule(ctx.ids.station), "label", "TT&C B")]}
        ]
      }
    ])

    assert {:ok, %{ops: ops, preview: %{verdict: :go}}} =
             ConfigurationRollback.preview(ctx.alice, ctx.mission, before_edit)

    assert [%{kind: "spacecraft_profile", action: "update"}] = ops

    {:ok, staged} =
      ConfigurationRollback.stage(ctx.alice, ctx.mission, before_edit)

    {:ok, %{state: :applied}} =
      Configuration.submit(ctx.alice, ctx.mission, staged.change_set_id, %{
        reason: "Undo the rename",
        expected_version: staged.version
      })

    assert [_route] = profile_routes(ctx)
  end

  defp profile_with_rule(station),
    do: Map.put(profile_doc("Block 1"), "routing_rules", [rule(station)])

  defp rule(station) do
    %{
      "id" => "ttc",
      "label" => "TT&C",
      "stations" => [%{"ground_station_id" => station}],
      "legs" => [%{"direction" => "downlink", "role" => "primary"}]
    }
  end

  defp override(ctx, value) do
    %{
      kind: "spacecraft_override",
      action: :update,
      entity_id: ctx.sc,
      changes: [%{path: "routing/ttc/excluded_stations", value: value}]
    }
  end

  defp profile_routes(ctx) do
    ctx.org
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(ctx.mission, ctx.sc)
    |> Enum.filter(&(&1.origin == :profile))
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
