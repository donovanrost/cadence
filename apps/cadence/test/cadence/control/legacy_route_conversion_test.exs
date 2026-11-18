defmodule Cadence.Control.LegacyRouteConversionTest do
  @moduledoc """
  TEMPORARY with the conversion (deleted with 9ac6dc8ee): legacy routing rules become extra routes
  through change sets, faithfully, in batches, each batch alone in its set, applied only after an
  independent approval (director 11-16).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, TransportStore}
  alias Cadence.Configuration.Submission
  alias Cadence.Control.{Configuration, LegacyRouteConversion}

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("conversion")
    stager = member_scope(org, :organization_admin, "Mira")
    reviewer = member_scope(org, :organization_admin, "Ana")

    ids = %{
      fbk: unique("fbk"),
      down: unique("fbk-down"),
      up: unique("fbk-up"),
      loose: unique("loose")
    }

    apply_ops(%{alice: stager, mission: mission}, "Fairbanks", [
      create("ground_station", %{"display_name" => "Fairbanks", "code" => "FBK"}, ids.fbk),
      create("transport", station_transport("FBK down", ids.fbk, "inbound"), ids.down),
      create("transport", station_transport("FBK up", ids.fbk, "outbound"), ids.up),
      create("transport", Map.delete(transport_doc("No station"), "ground_station_id"), ids.loose)
    ])

    craft =
      for n <- 1..3 do
        [sc] =
          apply_ops(%{alice: stager, mission: mission}, "Craft #{n}", [
            create("spacecraft", spacecraft_doc("EARENDIL-00#{n}", n))
          ])

        sc
      end

    ctx = %{
      org: org,
      mission: mission,
      stager: stager,
      reviewer: reviewer,
      ids: ids,
      craft: craft
    }

    for sc <- craft do
      legacy!(
        ctx,
        sc,
        ids.down,
        :inbound,
        :primary,
        "Fairbanks (Demo) — primary",
        "TT&C downlink"
      )

      legacy!(ctx, sc, ids.up, :outbound, :primary, "Fairbanks (Demo) — uplink", "TT&C uplink")
    end

    # One the conversion can't map: its transport has no station.
    legacy!(ctx, hd(craft), ids.loose, :inbound, :candidate, "Loose", "TT&C downlink")
    ctx
  end

  test "progress before anything is staged", ctx do
    assert {:ok, progress} = LegacyRouteConversion.progress(ctx.stager, ctx.mission, 2)

    assert %{
             routes_converted: 0,
             routes_total: 7,
             batch_size: 2,
             batches_total: 2,
             next_batch: 1,
             staged_batch: nil,
             can_stage: true,
             unmappable: %{count: 1, routes: [%{reason: "transport_has_no_station"} = loose]}
           } = progress

    assert loose.spacecraft.name == "EARENDIL-001"
    member = member_scope(ctx.org, :member, "Op")
    assert {:ok, %{can_stage: false}} = LegacyRouteConversion.progress(member, ctx.mission)

    assert {:error, :forbidden} = LegacyRouteConversion.stage_next_batch(member, ctx.mission, 2)
  end

  test "a batch converts faithfully, alone, and only another admin's approval applies it", ctx do
    before = plan(ctx)

    assert {:ok, staged} = LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission, 2)

    assert %{
             batch: 1,
             batches_total: 2,
             route_count: 4,
             spacecraft_count: 2,
             remaining_route_count: 3,
             unmappable: [%{reason: "transport_has_no_station"}]
           } = staged

    assert LegacyRouteConversion.change_set_batch(ctx.mission, staged.change_set_id) ==
             %{batch: 1, batches_total: 2}

    # One batch at a time, alone in its set.
    assert {:error, {:conversion_already_staged, %{batch: 1, author: %{name: "Mira"}}}} =
             LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission, 2)

    assert {:error, {:conversion_in_progress, %{change_set_id: _, batch: 1}}} =
             Configuration.stage(ctx.reviewer, ctx.mission, %{summary: "Other"}, [
               create("ground_station", %{"display_name" => "Elsewhere"})
             ])

    # Approval is forced (the mission doesn't require it), so the stager can't apply it.
    {:ok, set} = Configuration.change_set(ctx.stager, ctx.mission, staged.change_set_id)

    assert {:ok, %{state: :in_review}} =
             Configuration.submit(ctx.stager, ctx.mission, staged.change_set_id, %{
               reason: "Convert batch 1",
               expected_version: set.version
             })

    assert Submission.review_blocked_reason(
             ctx.org,
             ctx.mission,
             staged.change_set_id,
             actor(ctx.stager)
           ) ==
             :reviewer_is_author

    assert Submission.review_blocked_reason(
             ctx.org,
             ctx.mission,
             staged.change_set_id,
             actor(ctx.reviewer)
           ) ==
             nil

    {:ok, set} = Configuration.change_set(ctx.stager, ctx.mission, staged.change_set_id)

    assert {:error, :reviewer_is_author} =
             Configuration.review(ctx.stager, ctx.mission, staged.change_set_id, :approve, %{
               comment: "Mine",
               expected_version: set.version
             })

    assert {:ok, %{state: :applied}} =
             Configuration.review(ctx.reviewer, ctx.mission, staged.change_set_id, :approve, %{
               comment: "Checked: plan unchanged",
               expected_version: set.version
             })

    # The plan is unchanged; the two converted craft now hold extra routes, not legacy rules.
    assert plan(ctx) == before
    [one, two, three] = ctx.craft

    for sc <- [one, two] do
      origins = ctx |> rules(sc) |> Enum.reject(&(&1.transport_id == ctx.ids.loose))
      assert Enum.all?(origins, &(&1.origin == :spacecraft))
    end

    assert Enum.all?(rules(ctx, three), &(&1.origin == :legacy))

    assert {:ok, %{routes_converted: 4, routes_total: 7, next_batch: 2, staged_batch: nil}} =
             LegacyRouteConversion.progress(ctx.stager, ctx.mission, 2)
  end

  # lead: the block on other staging lasts only while a batch is staged-not-applied. A discard
  # lifts it as an apply does, so a discarded batch never leaves the mission frozen.
  test "discarding a staged batch lifts the block and leaves the legacy rules as they were",
       ctx do
    before = plan(ctx)
    {:ok, staged} = LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission, 2)
    {:ok, set} = Configuration.change_set(ctx.stager, ctx.mission, staged.change_set_id)

    assert {:error, {:conversion_in_progress, %{change_set_id: _, batch: 1}}} =
             Configuration.stage(ctx.reviewer, ctx.mission, %{summary: "Other"}, [
               create("ground_station", %{"display_name" => "Elsewhere"})
             ])

    assert {:ok, _discarded} =
             Configuration.discard(ctx.stager, ctx.mission, staged.change_set_id, set.version)

    assert plan(ctx) == before

    assert {:ok, %{staged_batch: nil, next_batch: 1, routes_converted: 0}} =
             LegacyRouteConversion.progress(ctx.stager, ctx.mission, 2)

    # Other staging works again, and the same batch can be staged again later.
    assert {:ok, other} =
             Configuration.stage(ctx.reviewer, ctx.mission, %{summary: "Other"}, [
               create("ground_station", %{"display_name" => "Elsewhere"})
             ])

    assert {:ok, _} =
             Configuration.discard(ctx.reviewer, ctx.mission, other.change_set_id, other.version)

    assert {:ok, %{batch: 1, route_count: 4}} =
             LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission, 2)
  end

  test "a batch needs an empty open change set", ctx do
    {:ok, staged} =
      Configuration.stage(ctx.reviewer, ctx.mission, %{summary: "Other"}, [
        create("ground_station", %{"display_name" => "Elsewhere"})
      ])

    assert {:error, {:open_change_set_not_empty, id}} =
             LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission)

    assert id == staged.change_set_id
  end

  test "the batch size is 1..100", ctx do
    for bad <- [0, 101, "50"] do
      assert {:error, {:invalid_params, :spacecraft}} =
               LegacyRouteConversion.stage_next_batch(ctx.stager, ctx.mission, bad)
    end
  end

  test "a replacing route whose legs don't match the legacy rule is refused", ctx do
    [rule | _] =
      ctx
      |> rules(hd(ctx.craft))
      |> Enum.filter(&(&1.direction == :inbound and &1.transport_id == ctx.ids.down))

    op = %{
      kind: "spacecraft_route",
      action: "create",
      document: %{
        "spacecraft_id" => hd(ctx.craft),
        "ground_station_id" => ctx.ids.fbk,
        "transport_id" => ctx.ids.down,
        "downlink" => "primary",
        "uplink" => "none",
        "display_name" => "Renamed",
        "purpose_label" => "TT&C downlink"
      },
      options: %{"replaces" => [rule.routing_rule_id]}
    }

    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(ctx.stager, ctx.mission, {:ops, [op]})

    errors =
      for %{key: "validation", items: items} <- checks,
          %{errors: errors} <- items,
          error <- errors,
          do: error

    assert %{
             path: "replaces",
             message: "The route's legs don't match the legacy routes it replaces"
           } in Enum.map(errors, &Map.take(&1, [:path, :message]))
  end

  defp legacy!(ctx, spacecraft_id, transport_id, direction, role, name, purpose) do
    {:ok, transport} = TransportStore.fetch_transport(ctx.org, ctx.mission, transport_id)

    {:ok, _rule} =
      RoutingRuleStore.create_routing_rule(
        ctx.org,
        RoutingRule.new(%{
          mission_id: ctx.mission,
          spacecraft_id: spacecraft_id,
          display_name: name,
          purpose_label: purpose,
          direction: direction,
          transport_id: transport_id,
          transport_version: transport.version,
          role: role
        })
      )
  end

  defp rules(ctx, spacecraft_id),
    do: RoutingRuleStore.list_routing_rules_for_spacecraft(ctx.org, ctx.mission, spacecraft_id)

  # What routing does per craft: transport, direction, role, name, purpose.
  defp plan(ctx) do
    routes =
      for sc <- ctx.craft,
          rule <- rules(ctx, sc),
          rule.lifecycle_state == :active,
          do:
            {sc, rule.transport_id, rule.direction, rule.role, rule.display_name,
             rule.purpose_label}

    Enum.sort(routes)
  end

  defp actor(scope),
    do: %{"kind" => "user", "id" => scope.user.user_id, "name" => scope.user.display_name}

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
