defmodule Cadence.Configuration.LegacyRoutingRuleKindTest do
  @moduledoc """
  Removing an older (legacy) routing rule through a change set (director 11-16, ux U79): delete
  only, refused at stage in ux's words when it can't be removed, and never restored by a rollback.
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, TransportStore}
  alias Cadence.Control.{Configuration, ConfigurationRollback, LegacyRouteConversion}

  @converted "This route was converted already. Remove it as an extra route."
  @not_removable "This rule can't be removed here."

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("legacy-remove")
    mira = member_scope(org, :organization_admin, "Mira")
    ana = member_scope(org, :organization_admin, "Ana")
    ids = %{fbk: unique("fbk"), down: unique("fbk-down")}

    apply_ops(%{alice: mira, mission: mission}, "Fairbanks", [
      create("ground_station", %{"display_name" => "Fairbanks", "code" => "FBK"}, ids.fbk),
      create("transport", station_transport("FBK down", ids.fbk, "inbound"), ids.down)
    ])

    [sc] =
      apply_ops(%{alice: mira, mission: mission}, "Craft", [
        create("spacecraft", spacecraft_doc("EARENDIL-389", 1))
      ])

    ctx = %{org: org, mission: mission, mira: mira, ana: ana, ids: ids, sc: sc}
    Map.put(ctx, :rule, legacy!(ctx, "qa-pre-routing-175358"))
  end

  test "an older route is removed through a change set, and archived on apply", ctx do
    op = remove(ctx.rule)

    assert {:ok, %{verdict: :go}} = Configuration.preview(ctx.mira, ctx.mission, {:ops, [op]})
    apply_ops(%{alice: ctx.mira, mission: ctx.mission}, "Remove older route", [op])

    assert {:ok, %{lifecycle_state: :archived}} =
             RoutingRuleStore.fetch_routing_rule_state(ctx.org, ctx.mission, ctx.rule)

    # Gone now: a second removal says so in ux's words, at stage.
    assert {:error, {:invalid_op, 0, [%{path: "", message: @not_removable}]}} =
             Configuration.stage(ctx.mira, ctx.mission, %{summary: "Again"}, [op])
  end

  test "a rule the conversion replaced is refused at stage, pointing to the extra route", ctx do
    {:ok, staged} = LegacyRouteConversion.stage_next_batch(ctx.mira, ctx.mission, 1)
    {:ok, set} = Configuration.change_set(ctx.mira, ctx.mission, staged.change_set_id)

    {:ok, %{state: :in_review}} =
      Configuration.submit(ctx.mira, ctx.mission, staged.change_set_id, %{
        reason: "Convert batch 1 for the test",
        expected_version: set.version
      })

    {:ok, set} = Configuration.change_set(ctx.mira, ctx.mission, staged.change_set_id)

    {:ok, %{state: :applied}} =
      Configuration.review(ctx.ana, ctx.mission, staged.change_set_id, :approve, %{
        comment: "Plan unchanged",
        expected_version: set.version
      })

    assert {:error, {:invalid_op, 0, [%{path: "", message: @converted}]}} =
             Configuration.stage(ctx.mira, ctx.mission, %{summary: "Remove"}, [remove(ctx.rule)])
  end

  test "anything that isn't an active older route of this mission can't be removed here", ctx do
    for id <- [unique("routing_rule"), ctx.sc] do
      assert {:error, {:invalid_op, 0, [%{path: "", message: @not_removable}]}} =
               Configuration.stage(ctx.mira, ctx.mission, %{summary: "Remove"}, [remove(id)])
    end
  end

  test "older routes can only be removed, never edited", ctx do
    edit = %{
      kind: "legacy_routing_rule",
      action: :update,
      entity_id: ctx.rule,
      changes: [%{path: "display_name", value: "Renamed"}]
    }

    assert {:error, {:invalid_op, 0, [%{path: "", message: "Older routes can only be removed."}]}} =
             Configuration.stage(ctx.mira, ctx.mission, %{summary: "Edit"}, [edit])
  end

  test "a rollback past a removal is NO-GO: the older route can't be restored", ctx do
    apply_ops(%{alice: ctx.mira, mission: ctx.mission}, "Remove older route", [remove(ctx.rule)])
    {:ok, %{head: %{revision: head}}} = Configuration.current(ctx.mira, ctx.mission)

    assert {:ok, %{preview: %{verdict: :no_go, checks: checks}}} =
             ConfigurationRollback.preview(ctx.mira, ctx.mission, head - 1)

    messages =
      for %{key: "validation", items: items} <- checks,
          %{errors: errors} <- items,
          %{message: message} <- errors,
          do: message

    assert ("The older route “qa-pre-routing-175358” · EARENDIL-389 was removed and can't be " <>
              "restored. To route that way again, add an extra route.") in messages

    assert {:ok, %{lifecycle_state: :archived}} =
             RoutingRuleStore.fetch_routing_rule_state(ctx.org, ctx.mission, ctx.rule)
  end

  defp remove(id), do: %{kind: "legacy_routing_rule", action: :delete, entity_id: id}

  defp legacy!(ctx, name) do
    {:ok, transport} = TransportStore.fetch_transport(ctx.org, ctx.mission, ctx.ids.down)

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        ctx.org,
        RoutingRule.new(%{
          mission_id: ctx.mission,
          spacecraft_id: ctx.sc,
          display_name: name,
          purpose_label: "TT&C downlink",
          direction: :inbound,
          transport_id: ctx.ids.down,
          transport_version: transport.version,
          role: :primary
        })
      )

    rule.routing_rule_id
  end

  defp station_transport(name, station, direction) do
    name
    |> transport_doc()
    |> put_in(["configuration", "direction_capability"], direction)
    |> Map.put("ground_station_id", station)
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
