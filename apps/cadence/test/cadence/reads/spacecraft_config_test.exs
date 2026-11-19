defmodule Cadence.Reads.SpacecraftConfigTest do
  @moduledoc "Investigate's Configuration tab read."
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Control.Configuration
  alias Cadence.Reads.SpacecraftConfig

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("sccfg")
    alice = member_scope(org, :member, "Alice")
    ids = %{station: unique("svb"), transport: unique("transport"), profile: unique("block1")}
    ctx = %{alice: alice, mission: mission}

    apply_ops(ctx, "Block 1 with Svalbard", [
      create("ground_station", %{"display_name" => "Svalbard", "code" => "SVB"}, ids.station),
      create(
        "transport",
        Map.put(transport_doc("Svalbard TCP"), "ground_station_id", ids.station),
        ids.transport
      ),
      create("spacecraft_profile", profile_with_rule(ids.station), ids.profile)
    ])

    [sc] =
      apply_ops(ctx, "First spacecraft", [
        create("spacecraft", spacecraft_doc("EARENDIL-001", 1, {ids.profile, 1}))
      ])

    Map.merge(ctx, %{org: org, ids: ids, sc: sc})
  end

  test "an unknown spacecraft is not found", ctx do
    assert {:error, :spacecraft_not_found} = SpacecraftConfig.load(ctx.org, ctx.mission, "nobody")
  end

  test "running, its overrides, routing, and the revisions that touched it", ctx do
    apply_ops(ctx, "Shorter frames", [frame_override(ctx, %{"value" => 892, "reason" => "Bench"})])

    assert {:ok, config} = SpacecraftConfig.load(ctx.org, ctx.mission, ctx.sc)

    assert %{name: "EARENDIL-001", scid: 1, archived: nil} = config.spacecraft
    assert %{id: profile_id, version: 1} = config.profile
    assert profile_id == ctx.ids.profile
    assert %{running: nil, profile: nil} = config.catalog

    assert [
             %{
               section: "Framing",
               path: "frame_parameters.frame_size",
               label: "TM frame length",
               unit: "bytes",
               profile_value_json: "1115",
               spacecraft_value_json: "892",
               reason: "Bench"
             }
           ] = config.overrides

    assert [_ | _] = config.routing_rules
    assert Enum.all?(config.routing_rules, &match?(%{station: %{code: "SVB"}}, &1))

    assert [%{via: ["spacecraft_override"], entries: entries} | older] = config.recent_revisions
    assert Enum.all?(entries, &(&1.entity_id == ctx.sc))
    assert Enum.any?(older, &("spacecraft" in &1.via))
    assert config.pending == []
  end

  test "a staged change touching it is pending, with Setup's change shape", ctx do
    {:ok, _staged} =
      Configuration.stage(ctx.alice, ctx.mission, %{summary: "Shorter frames"}, [
        frame_override(ctx, %{"value" => 892, "reason" => "Bench"})
      ])

    assert {:ok, %{pending: [pending]}} = SpacecraftConfig.load(ctx.org, ctx.mission, ctx.sc)
    assert %{state: "open", changes: [%{summary: "Shorter frames", via: via, ops: [_]}]} = pending
    assert via == "spacecraft_override"
  end

  defp frame_override(ctx, value) do
    %{
      kind: "spacecraft_override",
      action: :update,
      entity_id: ctx.sc,
      changes: [%{path: "frame_parameters/frame_size", value: value}]
    }
  end

  defp profile_with_rule(station),
    do:
      Map.put(profile_doc("Block 1"), "routing_rules", [
        %{
          "id" => "ttc",
          "label" => "TT&C",
          "stations" => [%{"ground_station_id" => station}],
          "legs" => [%{"direction" => "downlink", "role" => "primary"}]
        }
      ])

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
