defmodule Cadence.Configuration.StationCodeTest do
  @moduledoc """
  A ground station's Code (ux U25): optional while none is stored (an empty field means none),
  changeable once set, never emptied (pass titles and filters show it).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.GroundStationStore
  alias Cadence.Control.Configuration
  alias Cadence.Reads.ConfigKindSchema

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("station-code")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  test "a station can be added without a code; an empty code means none", ctx do
    [plain] = apply_ops(ctx, "Plain", [create(%{"display_name" => "Inuvik"})])
    [blank] = apply_ops(ctx, "Blank", [create(%{"display_name" => "Kiruna", "code" => "  "})])

    for id <- [plain, blank] do
      assert {:ok, %{code: nil}} =
               GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)
    end
  end

  test "a set code can be changed", ctx do
    [id] = apply_ops(ctx, "Inuvik", [create(%{"display_name" => "Inuvik", "code" => "INU"})])
    apply_ops(ctx, "Recode", [edit(id, "code", "INV")])

    assert {:ok, %{code: "INV"}} =
             GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)
  end

  test "a set code can't be emptied, in ux's words naming it", ctx do
    [id] = apply_ops(ctx, "Inuvik", [create(%{"display_name" => "Inuvik", "code" => "INU"})])

    for empty <- [nil, ""] do
      assert {:ok, %{verdict: :no_go, checks: checks}} =
               Configuration.preview(ctx.alice, ctx.mission, {:ops, [edit(id, "code", empty)]})

      assert %{items: [%{errors: [%{path: "code", message: message}]}]} =
               Enum.find(checks, &(&1.key == "validation"))

      assert message ==
               "INU is already used in pass titles and filters, so it can be changed but not removed."
    end
  end

  test "the form no longer requires a code", ctx do
    {:ok, fields} = ConfigKindSchema.fields("ground_station", ctx.org, ctx.mission)
    code = Enum.find(fields, &(&1.path == "code"))

    assert %{required: false} = code
  end

  defp create(document), do: %{kind: "ground_station", action: :create, document: document}

  defp edit(id, path, value),
    do: %{
      kind: "ground_station",
      action: :update,
      entity_id: id,
      changes: [%{path: path, value: value}]
    }

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end
end
