defmodule Cadence.Configuration.SpacecraftRouteKindTest do
  @moduledoc """
  A spacecraft's own extra route (kind `spacecraft_route`, DECISIONS #3 per-spacecraft overrides;
  lead + ux 11-16): one craft, one station outside its profile, its legs; planned like a profile
  route, left alone by profile re-materialization, refused when the profile already gives it.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.ConfigKinds.SpacecraftRoute
  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Control.Configuration
  alias Cadence.Reads.ConfigKindSchema

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
        changes: [%{path: "uplink", value: "none"}]
      }
    ])

    assert [%{leg_direction: "downlink"}] = own_routes(ctx)

    # The loaded document exposes the same two direction paths the form edits.
    assert %{^id => %{"downlink" => "primary", "uplink" => "none"}} =
             SpacecraftRoute.load(ctx.org, ctx.mission, [id])

    apply_ops(ctx, "Recovered", [%{kind: "spacecraft_route", action: :delete, entity_id: id}])
    assert own_routes(ctx) == []
  end

  test "a route the profile already gives is refused, in ux's words", ctx do
    doc = %{extra(ctx) | "ground_station_id" => ctx.ids.svb, "uplink" => "none"}

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
    doc = %{extra(ctx) | "ground_station_id" => ctx.ids.svb, "downlink" => "none"}

    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(
               ctx.alice,
               ctx.mission,
               {:ops, [create("spacecraft_route", doc)]}
             )

    assert %{items: [%{errors: [%{path: "ground_station_id"}]}]} =
             Enum.find(checks, &(&1.key == "validation"))
  end

  test "both directions none is refused on downlink, before anything stages", ctx do
    doc = %{extra(ctx) | "downlink" => "none", "uplink" => "none"}

    assert {:error, {:invalid_op, 0, [%{path: "downlink", message: message}]}} =
             Configuration.preview(
               ctx.alice,
               ctx.mission,
               {:ops, [create("spacecraft_route", doc)]}
             )

    assert message == "Choose a role for downlink, uplink or both"
  end

  test "transport choice errors are on transport_id, in ux's words", ctx do
    # A transport at another station.
    elsewhere = Map.put(extra(ctx), "transport_id", ctx.ids.svb_tcp)
    assert [%{path: "transport_id", message: m1}] = validation_errors(ctx, elsewhere)
    assert m1 == "Svalbard TCP isn't at Inuvik"

    # Two transports at the station that can carry a leg, and none named.
    apply_ops(ctx, "A second Inuvik transport", [
      create("transport", station_transport("Inuvik spare", ctx.ids.inu, "bidirectional"))
    ])

    assert [%{path: "transport_id", message: m2} | _] = validation_errors(ctx, extra(ctx))
    assert m2 == "Inuvik has 2 transports that can carry downlink; choose one"

    # Naming one resolves it.
    named = Map.put(extra(ctx), "transport_id", ctx.ids.inu_tcp)
    assert validation_errors(ctx, named) == []
  end

  test "the form schema: required directions with ux's defaults; stations and transports listed",
       ctx do
    assert {:ok, fields} = ConfigKindSchema.fields("spacecraft_route", ctx.org, ctx.mission)
    by_path = Map.new(fields, &{&1.path, &1})

    assert Enum.map(fields, & &1.path) ==
             ~w(spacecraft_id ground_station_id transport_id downlink uplink display_name purpose_label)

    assert %{required: true, default: "primary"} = by_path["downlink"]
    assert %{required: true, default: "none"} = by_path["uplink"]
    assert %{value: "none", label: "Not used"} in by_path["uplink"].enum
    assert by_path["spacecraft_id"].create_only
    assert %{value: ctx.ids.inu, label: "Inuvik · INU"} in by_path["ground_station_id"].enum
    assert %{value: ctx.ids.inu_tcp, label: "Inuvik TCP · Inuvik"} in by_path["transport_id"].enum
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

  # The route as WRITTEN is the source; the rows are its resolved output (lead, fe-setup's catch).
  # load/3 returns exactly what was staged, so the console's Edit gets it back.
  describe "round trip: load(stage(doc)) == doc" do
    test "an empty transport stays empty (the station's transport per leg)", ctx do
      doc = extra(ctx)
      [id] = apply_ops(ctx, "Recovery via Inuvik", [create("spacecraft_route", doc)])

      assert Enum.all?(own_routes(ctx), &(&1.transport_id == ctx.ids.inu_tcp))
      assert SpacecraftRoute.load(ctx.org, ctx.mission, [id]) == %{id => doc}
    end

    test "two legs on two different station transports stay unpinned, and an edit keeps it so",
         ctx do
      kir = unique("kir")

      apply_ops(ctx, "Kiruna", [
        create("ground_station", %{"display_name" => "Kiruna", "code" => "KIR"}, kir),
        create("transport", station_transport("Kiruna down", kir, "inbound"), unique("kir-down")),
        create("transport", station_transport("Kiruna up", kir, "outbound"), unique("kir-up"))
      ])

      doc = %{extra(ctx) | "ground_station_id" => kir}
      [id] = apply_ops(ctx, "Via Kiruna", [create("spacecraft_route", doc)])

      assert own_routes(ctx) |> Enum.map(& &1.transport_id) |> Enum.uniq() |> length() == 2
      assert SpacecraftRoute.load(ctx.org, ctx.mission, [id]) == %{id => doc}

      apply_ops(ctx, "Relabel", [update("spacecraft_route", id, "purpose_label", "Test")])

      assert SpacecraftRoute.load(ctx.org, ctx.mission, [id]) == %{
               id => %{doc | "purpose_label" => "Test"}
             }
    end

    test "a name template stays a template; the rows carry it rendered", ctx do
      doc = Map.put(extra(ctx), "display_name", "Spare {station} for {spacecraft}")
      [id] = apply_ops(ctx, "Named", [create("spacecraft_route", doc)])

      assert Enum.all?(own_routes(ctx), &(&1.display_name == "Spare INU for EARENDIL-001"))
      assert SpacecraftRoute.load(ctx.org, ctx.mission, [id]) == %{id => doc}
    end

    test "an edit that resolves to the same rows still stores what was written", ctx do
      [id] = apply_ops(ctx, "Recovery via Inuvik", [create("spacecraft_route", extra(ctx))])
      before = own_routes(ctx) |> Enum.map(&{&1.routing_rule_id, &1.transport_id}) |> Enum.sort()

      # Pinning the transport the station resolves to anyway: same rows, a different document.
      apply_ops(ctx, "Pin", [update("spacecraft_route", id, "transport_id", ctx.ids.inu_tcp)])

      assert own_routes(ctx) |> Enum.map(&{&1.routing_rule_id, &1.transport_id}) |> Enum.sort() ==
               before

      assert %{^id => %{"transport_id" => pinned}} =
               SpacecraftRoute.load(ctx.org, ctx.mission, [id])

      assert pinned == ctx.ids.inu_tcp
    end
  end

  defp extra(ctx),
    do: %{
      "spacecraft_id" => ctx.sc,
      "ground_station_id" => ctx.ids.inu,
      "purpose_label" => "Recovery",
      "downlink" => "primary",
      "uplink" => "primary"
    }

  defp downlink, do: %{"direction" => "downlink", "role" => "primary"}

  defp validation_errors(ctx, doc) do
    {:ok, %{checks: checks}} =
      Configuration.preview(ctx.alice, ctx.mission, {:ops, [create("spacecraft_route", doc)]})

    case Enum.find(checks, &(&1.key == "validation")) do
      %{items: [%{errors: errors}]} -> errors
      _clean -> []
    end
  end

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

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}
end
