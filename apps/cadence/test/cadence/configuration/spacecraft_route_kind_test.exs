defmodule Cadence.Configuration.SpacecraftRouteKindTest do
  @moduledoc """
  A spacecraft's own extra route (kind `spacecraft_route`, DECISIONS #3 per-spacecraft overrides;
  lead + ux 11-16): one craft, one station outside its profile, its legs; planned like a profile
  route, left alone by profile re-materialization, refused when the profile already gives it.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Control.Configuration

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("extra-route")
    alice = member_scope(org, :member, "Alice")

    ids = %{
      svb: unique("svb"),
      inu: unique("inu"),
      svb_tcp: unique("svb-tcp"),
      inu_tcp: unique("inu-tcp"),
      profile: unique("block1")
    }

    apply_ops(%{alice: alice, mission: mission}, "Block 1 with Svalbard; Inuvik spare", [
      create("ground_station", %{"display_name" => "Svalbard", "code" => "SVB"}, ids.svb),
      create("ground_station", %{"display_name" => "Inuvik", "code" => "INU"}, ids.inu),
      create("transport", station_transport("Svalbard TCP", ids.svb, "inbound"), ids.svb_tcp),
      create("transport", station_transport("Inuvik TCP", ids.inu, "bidirectional"), ids.inu_tcp),
      create("spacecraft_profile", profile_with_rule(ids.svb), ids.profile)
    ])

    [sc] =
      apply_ops(%{alice: alice, mission: mission}, "First spacecraft", [
        create("spacecraft", spacecraft_doc("EARENDIL-001", 1, {ids.profile, 1}))
      ])

    %{org: org, mission: mission, alice: alice, ids: ids, sc: sc}
  end

  test "an extra route gives one spacecraft a station its profile doesn't", ctx do
    [id] = apply_ops(ctx, "Recovery via Inuvik", [create("spacecraft_route", extra(ctx))])

    assert [down, up] = Enum.sort_by(own_routes(ctx), & &1.leg_direction)
    assert {down.leg_direction, down.direction} == {"downlink", :inbound}
    assert {up.leg_direction, up.direction} == {"uplink", :outbound}

    for route <- [down, up] do
      assert route.origin == :spacecraft
      assert route.profile_rule_id == id
      assert route.transport_id == ctx.ids.inu_tcp
      assert route.display_name == "INU · EARENDIL-001"
      assert route.purpose_label == "Recovery"
    end

    # The profile's own route is untouched.
    assert [%{ground_station_id: svb}] = routes(ctx, :profile)
    assert svb == ctx.ids.svb
  end

  test "editing drops a leg; removing archives the routes", ctx do
    [id] = apply_ops(ctx, "Recovery via Inuvik", [create("spacecraft_route", extra(ctx))])

    apply_ops(ctx, "Downlink only", [
      %{
        kind: "spacecraft_route",
        action: :update,
        entity_id: id,
        changes: [%{path: "legs", value: [%{"direction" => "downlink", "role" => "primary"}]}]
      }
    ])

    assert [%{leg_direction: "downlink"}] = own_routes(ctx)

    apply_ops(ctx, "Recovered", [%{kind: "spacecraft_route", action: :delete, entity_id: id}])
    assert own_routes(ctx) == []
  end

  test "a route the profile already gives is refused, in ux's words", ctx do
    doc = %{extra(ctx) | "ground_station_id" => ctx.ids.svb, "legs" => [downlink()]}

    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(
               ctx.alice,
               ctx.mission,
               {:ops, [create("spacecraft_route", doc)]}
             )

    assert %{items: [%{errors: [error]}]} = Enum.find(checks, &(&1.key == "validation"))
    assert error.path == "ground_station_id"
    assert error.message == "EARENDIL-001 already has this route from its profile."
  end

  test "a leg the station's transport can't carry is refused", ctx do
    # Svalbard's only transport is inbound: no uplink leg there.
    doc = %{
      extra(ctx)
      | "ground_station_id" => ctx.ids.svb,
        "legs" => [%{"direction" => "uplink", "role" => "primary"}]
    }

    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(
               ctx.alice,
               ctx.mission,
               {:ops, [create("spacecraft_route", doc)]}
             )

    assert %{items: [%{errors: [%{path: "ground_station_id"}]}]} =
             Enum.find(checks, &(&1.key == "validation"))
  end

  test "profile re-materialization leaves the extra route alone", ctx do
    apply_ops(ctx, "Recovery via Inuvik", [create("spacecraft_route", extra(ctx))])

    # Excluding Svalbard re-materializes the craft's profile routes (none left)...
    apply_ops(ctx, "No Svalbard", [
      %{
        kind: "spacecraft_override",
        action: :update,
        entity_id: ctx.sc,
        changes: [
          %{
            path: "routing/ttc/excluded_stations",
            value: %{"value" => [ctx.ids.svb], "reason" => "Antenna down"}
          }
        ]
      }
    ])

    assert routes(ctx, :profile) == []
    # ... and the extra route is still there.
    assert length(own_routes(ctx)) == 2
  end

  defp extra(ctx),
    do: %{
      "spacecraft_id" => ctx.sc,
      "ground_station_id" => ctx.ids.inu,
      "purpose_label" => "Recovery",
      "legs" => [downlink(), %{"direction" => "uplink", "role" => "primary"}]
    }

  defp downlink, do: %{"direction" => "downlink", "role" => "primary"}

  defp station_transport(name, station, direction) do
    name
    |> transport_doc()
    |> put_in(["configuration", "direction_capability"], direction)
    |> Map.put("ground_station_id", station)
  end

  defp profile_with_rule(station),
    do:
      Map.put(profile_doc("Block 1"), "routing_rules", [
        %{
          "id" => "ttc",
          "label" => "TT&C",
          "stations" => [%{"ground_station_id" => station}],
          "legs" => [downlink()]
        }
      ])

  defp routes(ctx, origin),
    do:
      ctx.org
      |> RoutingRuleStore.list_routing_rules_for_spacecraft(ctx.mission, ctx.sc)
      |> Enum.filter(&(&1.origin == origin))

  defp own_routes(ctx), do: routes(ctx, :spacecraft)

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
